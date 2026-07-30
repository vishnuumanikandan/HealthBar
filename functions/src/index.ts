/**
 * AIPROXY-1a — `aiProxy`, the only sanctioned path between the app and the
 * Anthropic API.
 *
 * The function requires Firebase Auth, enforces a per-uid daily call limit via
 * a Firestore counter, holds the Anthropic API key in Secret Manager, holds all
 * prompt text server-side, forwards to Anthropic, and returns the model's text.
 *
 * Guardrail: the client sends RAW USER INPUT ONLY. It never sends a system
 * prompt, a message array, a model id, or a token cap, and no client-supplied
 * value can reach those fields. That is what keeps this a narrow app proxy
 * rather than a general-purpose Anthropic gateway.
 *
 * This stage ships NO client changes — the live app still calls Anthropic
 * directly with the bundled key until AIPROXY-1b migrates it.
 *
 * deletion-cascade: aiUsage handled in AIPROXY-1b
 */

import { getApps, initializeApp } from 'firebase-admin/app';
import {
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  getFirestore,
} from 'firebase-admin/firestore';
import { defineSecret } from 'firebase-functions/params';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';

import {
  DESCRIBE_MEAL_SYSTEM_PROMPT,
  IMAGE_ONLY_USER_PROMPT,
  ONBOARDING_GOALS_SYSTEM_PROMPT,
  PHOTO_RECOGNITION_SYSTEM_PROMPT,
} from './prompts';

// MARK: - Deployment constants

/**
 * Pinned in code and passed explicitly to the function declaration — never
 * inherited from CLI or config defaults. Co-located with the project's
 * Firestore database (`nam5`, verified 2026-07-29).
 */
const FUNCTION_REGION = 'us-central1';
const FUNCTION_TIMEOUT_SECONDS = 120;
/** Base64 image payloads are held in memory while the request is forwarded. */
const FUNCTION_MEMORY = '512MiB';

/**
 * Secret Manager binding. The symbol and the secret name are frozen — the
 * deploy runbook's `firebase functions:secrets:set ANTHROPIC_API_KEY` step
 * depends on both.
 */
const anthropicApiKey = defineSecret('ANTHROPIC_API_KEY');

// MARK: - Quota constants

/** Unified across all request kinds. */
const DAILY_AI_CALL_LIMIT = 15;
/** `details.code` on the resource-exhausted error; AIPROXY-1b maps it to copy. */
const AI_DAILY_LIMIT_CODE = 'AI_DAILY_LIMIT';

const USERS_COLLECTION = 'users';
const AI_USAGE_COLLECTION = 'aiUsage';
const COUNT_FIELD = 'count';
const UPDATED_AT_FIELD = 'updatedAt';

// MARK: - Validation constants

const MAX_IMAGE_BYTES = 8_000_000;
const MAX_TEXT_CHARS = 4000;
const ALLOWED_MEDIA_TYPES = [
  'image/jpeg',
  'image/png',
  'image/heic',
  'image/webp',
] as const;

/** Cap on the rejected-request `kind` echoed into logs. */
const MAX_LOGGED_KIND_CHARS = 64;

const BASE64_ALPHABET = /^[A-Za-z0-9+/]*={0,2}$/;
const BASE64_GROUP_SIZE = 4;
const BASE64_GROUP_BYTES = 3;

// MARK: - Anthropic constants

const ANTHROPIC_MESSAGES_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';
const ANTHROPIC_TIMEOUT_MS = 60_000;
const ANTHROPIC_USER_ROLE = 'user';
const ANTHROPIC_TEXT_BLOCK = 'text';
const ANTHROPIC_IMAGE_BLOCK = 'image';
const ANTHROPIC_BASE64_SOURCE = 'base64';

/**
 * Server-side knobs. Model choice and token caps never involve the client
 * again. Frozen for this stage: infra migration and behavior change must not
 * ride the same PR.
 */
const MODEL_SONNET = 'claude-sonnet-4-6';
const MAX_TOKENS_RECOGNITION = 4096;
const MAX_TOKENS_ONBOARDING_GOALS = 256;

// MARK: - Wire types

type AllowedMediaType = (typeof ALLOWED_MEDIA_TYPES)[number];

type AiProxyKind = 'photoRecognition' | 'describeMeal' | 'onboardingGoals';

const AI_PROXY_KINDS: readonly AiProxyKind[] = [
  'photoRecognition',
  'describeMeal',
  'onboardingGoals',
];

/** A validated request. Parsing produces one of these or throws. */
type ValidatedRequest =
  | { kind: 'photoRecognition'; imageBase64: string; mediaType: AllowedMediaType }
  | { kind: 'describeMeal'; text: string }
  | { kind: 'onboardingGoals'; text: string };

interface AiProxyResponse {
  text: string;
  requestsRemainingToday: number;
}

interface KindConfig {
  readonly model: string;
  readonly maxTokens: number;
  readonly systemPrompt: string;
}

/**
 * Per-kind model, token cap, and system prompt. This table is the ONLY source
 * of those three values; nothing derived from the request can reach them.
 */
const KIND_CONFIG: Readonly<Record<AiProxyKind, KindConfig>> = {
  photoRecognition: {
    model: MODEL_SONNET,
    maxTokens: MAX_TOKENS_RECOGNITION,
    systemPrompt: PHOTO_RECOGNITION_SYSTEM_PROMPT,
  },
  describeMeal: {
    model: MODEL_SONNET,
    maxTokens: MAX_TOKENS_RECOGNITION,
    systemPrompt: DESCRIBE_MEAL_SYSTEM_PROMPT,
  },
  onboardingGoals: {
    model: MODEL_SONNET,
    maxTokens: MAX_TOKENS_ONBOARDING_GOALS,
    systemPrompt: ONBOARDING_GOALS_SYSTEM_PROMPT,
  },
};

// MARK: - Firestore access

let firestoreInstance: Firestore | undefined;

/** Lazy so that importing this module never requires credentials. */
function db(): Firestore {
  if (firestoreInstance === undefined) {
    if (getApps().length === 0) {
      initializeApp();
    }
    firestoreInstance = getFirestore();
  }
  return firestoreInstance;
}

/**
 * The per-day counter document: `users/{uid}/aiUsage/{yyyyMMdd}`.
 *
 * Client-inaccessible: `firestore.rules` grants `users/{uid}/{collection}/{doc}`
 * only for collections on an explicit allowlist, and `aiUsage` is deliberately
 * absent from it. Admin SDK writes bypass rules.
 */
function usageDoc(uid: string, dayKey: string): DocumentReference {
  return db()
    .collection(USERS_COLLECTION)
    .doc(uid)
    .collection(AI_USAGE_COLLECTION)
    .doc(dayKey);
}

// MARK: - Day key

/**
 * The UTC calendar day as `yyyyMMdd` (Gregorian, ASCII digits, zero-padded).
 *
 * Deterministic doc id = per-day idempotency, matching the app's established
 * pattern. Built from the UTC getters with manual padding: `toLocaleDateString`
 * and `Intl` formatters are BANNED here — both are locale- and calendar-
 * sensitive and would silently produce a non-Gregorian or non-ASCII key under
 * an unexpected runtime locale.
 */
export function utcDayKey(date: Date): string {
  const year = date.getUTCFullYear();
  const month = date.getUTCMonth() + 1;
  const day = date.getUTCDate();
  return `${year}${padTwo(month)}${padTwo(day)}`;
}

function padTwo(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

// MARK: - Request validation

function invalid(message: string): HttpsError {
  return new HttpsError('invalid-argument', message);
}

/**
 * Best-effort `kind` for logging a REJECTED request, so every request produces
 * a log line even when validation failed. Length-capped so a caller cannot use
 * it to flood the logs. Never trusted for anything downstream.
 */
function loggableKind(raw: unknown): string | undefined {
  if (typeof raw !== 'object' || raw === null) {
    return undefined;
  }
  const value = (raw as { kind?: unknown }).kind;
  return typeof value === 'string' ? value.slice(0, MAX_LOGGED_KIND_CHARS) : undefined;
}

function isAiProxyKind(value: unknown): value is AiProxyKind {
  return typeof value === 'string' && AI_PROXY_KINDS.includes(value as AiProxyKind);
}

function isAllowedMediaType(value: unknown): value is AllowedMediaType {
  return (
    typeof value === 'string' &&
    ALLOWED_MEDIA_TYPES.includes(value as AllowedMediaType)
  );
}

/**
 * Decoded byte length of a well-formed base64 string, computed without
 * allocating the buffer.
 */
function base64DecodedByteLength(value: string): number {
  if (value.length === 0) {
    return 0;
  }
  const padding = value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0;
  return (value.length / BASE64_GROUP_SIZE) * BASE64_GROUP_BYTES - padding;
}

function isWellFormedBase64(value: string): boolean {
  return value.length % BASE64_GROUP_SIZE === 0 && BASE64_ALPHABET.test(value);
}

function requireString(data: Record<string, unknown>, field: string): string {
  const value = data[field];
  if (typeof value !== 'string') {
    throw invalid(`${field} must be a string`);
  }
  return value;
}

/**
 * Validates `kind` and the per-kind fields. Every invalid-argument check runs
 * here, before any Firestore access, so a malformed request never burns a
 * credit.
 */
function parseRequest(raw: unknown): ValidatedRequest {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw invalid('request data must be an object');
  }
  const data = raw as Record<string, unknown>;

  const kind = data.kind;
  if (!isAiProxyKind(kind)) {
    throw invalid('kind must be one of: ' + AI_PROXY_KINDS.join(', '));
  }

  if (kind === 'photoRecognition') {
    const imageBase64 = requireString(data, 'imageBase64');
    const mediaType = data.mediaType;
    if (!isAllowedMediaType(mediaType)) {
      throw invalid('mediaType must be one of: ' + ALLOWED_MEDIA_TYPES.join(', '));
    }
    if (imageBase64.length === 0) {
      throw invalid('imageBase64 must not be empty');
    }
    if (!isWellFormedBase64(imageBase64)) {
      throw invalid('imageBase64 must be valid base64');
    }
    if (base64DecodedByteLength(imageBase64) > MAX_IMAGE_BYTES) {
      throw invalid(`imageBase64 exceeds ${MAX_IMAGE_BYTES} decoded bytes`);
    }
    return { kind, imageBase64, mediaType };
  }

  const text = requireString(data, 'text');
  if (text.length === 0) {
    throw invalid('text must not be empty');
  }
  if (text.length > MAX_TEXT_CHARS) {
    throw invalid(`text exceeds ${MAX_TEXT_CHARS} characters`);
  }
  return { kind, text };
}

// MARK: - Daily limit

function readCount(snapshot: DocumentSnapshot): number {
  if (!snapshot.exists) {
    return 0;
  }
  const raw = snapshot.get(COUNT_FIELD);
  if (typeof raw !== 'number' || !Number.isFinite(raw) || raw <= 0) {
    return 0;
  }
  return Math.floor(raw);
}

/**
 * Checks the limit and increments the counter INSIDE ONE TRANSACTION, so
 * concurrent requests serialize and the limit can never overshoot.
 *
 * @returns credits remaining after this call.
 */
async function consumeDailyCredit(uid: string, dayKey: string): Promise<number> {
  const ref = usageDoc(uid, dayKey);
  return db().runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const current = readCount(snapshot);
    if (current >= DAILY_AI_CALL_LIMIT) {
      throw new HttpsError('resource-exhausted', 'Daily AI limit reached.', {
        code: AI_DAILY_LIMIT_CODE,
      });
    }
    const next = current + 1;
    tx.set(
      ref,
      { [COUNT_FIELD]: next, [UPDATED_AT_FIELD]: FieldValue.serverTimestamp() },
      { merge: true }
    );
    return DAILY_AI_CALL_LIMIT - next;
  });
}

/**
 * Best-effort refund after an our-side failure. Transactional so it cannot lose
 * a concurrent increment, clamped at zero, and every failure is swallowed —
 * worst case is one lost credit, which beats failing the user's request twice.
 */
async function refundDailyCredit(uid: string, dayKey: string): Promise<void> {
  try {
    const ref = usageDoc(uid, dayKey);
    await db().runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const current = readCount(snapshot);
      if (current <= 0) {
        return;
      }
      tx.set(
        ref,
        {
          [COUNT_FIELD]: current - 1,
          [UPDATED_AT_FIELD]: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });
  } catch (error) {
    logger.warn('aiProxy refund failed', {
      uid,
      dayKey,
      error: errorMessage(error),
    });
  }
}

// MARK: - Anthropic

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** Assembles the request body server-side from constants plus validated input. */
function buildAnthropicBody(request: ValidatedRequest): Record<string, unknown> {
  const config = KIND_CONFIG[request.kind];
  const content =
    request.kind === 'photoRecognition'
      ? [
          {
            type: ANTHROPIC_IMAGE_BLOCK,
            source: {
              type: ANTHROPIC_BASE64_SOURCE,
              media_type: request.mediaType,
              data: request.imageBase64,
            },
          },
          { type: ANTHROPIC_TEXT_BLOCK, text: IMAGE_ONLY_USER_PROMPT },
        ]
      : request.text;

  return {
    model: config.model,
    max_tokens: config.maxTokens,
    system: config.systemPrompt,
    messages: [{ role: ANTHROPIC_USER_ROLE, content }],
  };
}

/**
 * Concatenates every `text` content block in array order, ignoring all other
 * block types. Returns null when the payload carries no text block at all —
 * the caller treats that as a failure (refund + internal).
 */
function concatTextBlocks(payload: unknown): string | null {
  if (typeof payload !== 'object' || payload === null) {
    return null;
  }
  const content = (payload as { content?: unknown }).content;
  if (!Array.isArray(content)) {
    return null;
  }
  let combined = '';
  let sawTextBlock = false;
  for (const block of content) {
    if (typeof block !== 'object' || block === null) {
      continue;
    }
    const typed = block as { type?: unknown; text?: unknown };
    if (typed.type !== ANTHROPIC_TEXT_BLOCK || typeof typed.text !== 'string') {
      continue;
    }
    combined += typed.text;
    sawTextBlock = true;
  }
  return sawTextBlock ? combined : null;
}

/** Numeric `usage` fields only — safe to log, never carries user content. */
function extractUsage(payload: unknown): Record<string, number> | undefined {
  if (typeof payload !== 'object' || payload === null) {
    return undefined;
  }
  const usage = (payload as { usage?: unknown }).usage;
  if (typeof usage !== 'object' || usage === null) {
    return undefined;
  }
  const counts: Record<string, number> = {};
  for (const [key, value] of Object.entries(usage as Record<string, unknown>)) {
    if (typeof value === 'number' && Number.isFinite(value)) {
      counts[key] = value;
    }
  }
  return Object.keys(counts).length > 0 ? counts : undefined;
}

interface AnthropicOutcome {
  text: string;
  usage?: Record<string, number>;
}

/**
 * Calls Anthropic and extracts the text. Throws on non-2xx, network failure,
 * timeout, unparseable JSON, or a response with no text block — the caller
 * refunds and reports `internal` for every one of those.
 */
async function callAnthropic(
  request: ValidatedRequest,
  apiKey: string
): Promise<AnthropicOutcome> {
  const response = await fetch(ANTHROPIC_MESSAGES_URL, {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': ANTHROPIC_VERSION,
      'content-type': 'application/json',
    },
    body: JSON.stringify(buildAnthropicBody(request)),
    signal: AbortSignal.timeout(ANTHROPIC_TIMEOUT_MS),
  });

  if (!response.ok) {
    throw new Error(`Anthropic responded ${response.status}`);
  }

  const payload: unknown = await response.json();
  const text = concatTextBlocks(payload);
  if (text === null) {
    throw new Error('Anthropic response contained no text block');
  }
  return { text, usage: extractUsage(payload) };
}

// MARK: - Callable

export const aiProxy = onCall<unknown, Promise<AiProxyResponse>>(
  {
    region: FUNCTION_REGION,
    secrets: [anthropicApiKey],
    // Monitor-only for now: we log token absence and decide on enforcement
    // once we have observed false-positive rates.
    enforceAppCheck: false,
    timeoutSeconds: FUNCTION_TIMEOUT_SECONDS,
    memory: FUNCTION_MEMORY,
  },
  async (request: CallableRequest<unknown>): Promise<AiProxyResponse> => {
    const appCheckPresent = request.app !== undefined;

    if (request.auth === undefined) {
      logger.info('aiProxy rejected', {
        appCheckPresent,
        outcome: 'unauthenticated',
      });
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    const uid = request.auth.uid;

    if (!appCheckPresent) {
      logger.warn('aiProxy request without App Check token', {
        uid,
        appCheckPresent,
      });
    }

    // 1. Validate everything before touching Firestore, so a malformed
    //    request can never burn a credit.
    let parsed: ValidatedRequest;
    try {
      parsed = parseRequest(request.data);
    } catch (error) {
      logger.info('aiProxy rejected', {
        uid,
        kind: loggableKind(request.data),
        appCheckPresent,
        outcome: 'invalid-argument',
      });
      throw error;
    }
    const kind = parsed.kind;

    // 2. Limit check + increment, in one transaction.
    const dayKey = utcDayKey(new Date());
    let requestsRemainingToday: number;
    try {
      requestsRemainingToday = await consumeDailyCredit(uid, dayKey);
    } catch (error) {
      if (error instanceof HttpsError) {
        logger.info('aiProxy blocked', {
          uid,
          kind,
          appCheckPresent,
          outcome: error.code,
        });
        throw error;
      }
      logger.error('aiProxy counter failed', {
        uid,
        kind,
        appCheckPresent,
        outcome: 'counter-error',
        error: errorMessage(error),
      });
      throw new HttpsError('internal', 'AI request failed.');
    }

    // 3-5. Forward to Anthropic and return its text.
    try {
      const outcome = await callAnthropic(parsed, anthropicApiKey.value());
      logger.info('aiProxy ok', {
        uid,
        kind,
        appCheckPresent,
        outcome: 'ok',
        requestsRemainingToday,
        usage: outcome.usage,
      });
      return { text: outcome.text, requestsRemainingToday };
    } catch (error) {
      // 6. Our-side failure: best-effort refund, then `internal`.
      await refundDailyCredit(uid, dayKey);
      logger.error('aiProxy upstream failed', {
        uid,
        kind,
        appCheckPresent,
        outcome: 'upstream-error',
        error: errorMessage(error),
      });
      throw new HttpsError('internal', 'AI request failed.');
    }
  }
);
