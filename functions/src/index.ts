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

import { App, getApp, initializeApp } from 'firebase-admin/app';
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
  CATEGORY_GUIDANCE,
  FOOD_CATEGORIES,
  FoodCategory,
  IMAGE_ONLY_USER_PROMPT,
  IMAGE_RECONCILIATION_RULE,
  ONBOARDING_GOALS_SYSTEM_PROMPT,
  SYSTEM_PROMPT_GENERAL,
  SYSTEM_PROMPT_SCHEMA_ONWARD,
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
/** Accept bound for the short structured fields (`amount`, `extras`). */
const MAX_FIELD_CHARS = 200;

/**
 * Port of `AIFoodRecognitionService.maxInputLength` (500).
 *
 * VERIFIED at the 1a base commit: 500 <= MAX_TEXT_CHARS (4000), so the server's
 * ACCEPT bound is looser than the client's truncation, as required. The two are
 * different things and must stay that way: MAX_TEXT_CHARS rejects an absurd
 * payload, MAX_INPUT_LENGTH reproduces the client's own truncation so the
 * assembled prompt is identical.
 */
const MAX_INPUT_LENGTH = 500;
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

type AiProxyKind = 'foodRecognition' | 'onboardingGoals';

const AI_PROXY_KINDS: readonly AiProxyKind[] = ['foodRecognition', 'onboardingGoals'];

interface ValidatedImage {
  base64: string;
  mediaType: AllowedMediaType;
}

/**
 * A validated request. Parsing produces one of these or throws.
 *
 * The `foodRecognition` shape mirrors
 * `AIFoodRecognitionService.recognize(description:imageData:category:amount:extras:)`
 * one-for-one. Fields are NORMALISED at parse time — trimmed, truncated, and
 * collapsed to `undefined` when the client's equivalent `hasText` / `hasAmount`
 * / `hasExtras` flag would be false — so the assembly port below can branch on
 * presence exactly as the Swift does.
 */
type ValidatedRequest =
  | {
      kind: 'foodRecognition';
      /** Trimmed then truncated to MAX_INPUT_LENGTH; undefined when !hasText. */
      description: string | undefined;
      image: ValidatedImage | undefined;
      category: FoodCategory | undefined;
      /** Trimmed; undefined when !hasAmount. */
      amount: string | undefined;
      /** Trimmed; undefined when !hasExtras. */
      extras: string | undefined;
    }
  | { kind: 'onboardingGoals'; text: string };

interface AiProxyResponse {
  text: string;
  requestsRemainingToday: number;
}

interface KindConfig {
  readonly model: string;
  readonly maxTokens: number;
}

/**
 * Per-kind model and token cap. This table is the ONLY source of those two
 * values; nothing derived from the request can reach them.
 */
const KIND_CONFIG: Readonly<Record<AiProxyKind, KindConfig>> = {
  foodRecognition: {
    model: MODEL_SONNET,
    maxTokens: MAX_TOKENS_RECOGNITION,
  },
  onboardingGoals: {
    model: MODEL_SONNET,
    maxTokens: MAX_TOKENS_ONBOARDING_GOALS,
  },
};

// MARK: - Firestore access

let firestoreInstance: Firestore | undefined;

/**
 * Lazy so that importing this module never requires credentials.
 *
 * Gate on `getApp()`, NOT on `getApps().length`. Those ask different questions:
 * `getApps()` returns EVERY app including named ones, while `getFirestore()`
 * needs the DEFAULT app specifically. The callable runtime verifies the auth
 * token before our handler runs and initialises its own named app along the
 * way, so `getApps().length` is already non-zero by then — the old guard
 * skipped `initializeApp()` and every request died with "The default Firebase
 * app does not exist" (outcome: counter-error). `getApp()` throws iff the
 * default app is absent, which is exactly the precondition being checked.
 *
 * The try/catch also stays correct if something else initialises the default
 * app first, where an unconditional module-scope `initializeApp()` would throw
 * at load time and take the whole function down.
 */
function db(): Firestore {
  if (firestoreInstance === undefined) {
    let app: App;
    try {
      app = getApp();
    } catch {
      app = initializeApp();
    }
    firestoreInstance = getFirestore(app);
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

function isFoodCategory(value: unknown): value is FoodCategory {
  return typeof value === 'string' && FOOD_CATEGORIES.includes(value as FoodCategory);
}

/**
 * Port of Swift's `CharacterSet.whitespacesAndNewlines`: the Unicode Zs
 * category plus U+0009, U+000A-U+000D, U+0085, U+2028 and U+2029.
 *
 * Deliberately NOT `String.prototype.trim()`. JS trims U+FEFF (which Swift does
 * not) and does not trim U+0085 (which Swift does), so `.trim()` would produce
 * a different `hasText` verdict and a different assembled prompt on those two
 * characters.
 */
const SWIFT_WHITESPACE_CLASS =
  '\\t\\n\\v\\f\\r\\u0085\\u0020\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000';
const SWIFT_TRIM_PATTERN = new RegExp(
  `^[${SWIFT_WHITESPACE_CLASS}]+|[${SWIFT_WHITESPACE_CLASS}]+$`,
  'g'
);

/** Port of `.trimmingCharacters(in: .whitespacesAndNewlines)`. */
function swiftTrim(value: string): string {
  return value.replace(SWIFT_TRIM_PATTERN, '');
}

/**
 * Grapheme-cluster segmenter, pinned to a fixed locale for determinism.
 * Swift's `String.prefix(_:)` counts Characters (extended grapheme clusters),
 * NOT UTF-16 code units, so a naive `.slice()` would cut a different amount of
 * text out of any string containing emoji or combining marks.
 */
const GRAPHEME_SEGMENTER = new Intl.Segmenter('en', { granularity: 'grapheme' });

/** Port of `String(value.prefix(limit))`. */
function truncateToCharacters(value: string, limit: number): string {
  // A string can never have more Characters than UTF-16 code units, so this
  // fast path is exact, and it keeps the common case off the segmenter.
  if (value.length <= limit) {
    return value;
  }
  let result = '';
  let taken = 0;
  for (const { segment } of GRAPHEME_SEGMENTER.segment(value)) {
    if (taken === limit) {
      break;
    }
    result += segment;
    taken += 1;
  }
  return result;
}

/**
 * Trims, then collapses an empty result to undefined — the server-side
 * equivalent of the client computing `hasAmount` / `hasExtras`.
 */
function normalizeOptionalField(value: string | undefined): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  const trimmed = swiftTrim(value);
  return trimmed.length > 0 ? trimmed : undefined;
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

/** Absent (undefined or null) or a string; anything else is invalid-argument. */
function optionalString(
  data: Record<string, unknown>,
  field: string
): string | undefined {
  const value = data[field];
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'string') {
    throw invalid(`${field} must be a string`);
  }
  return value;
}

function boundedField(
  data: Record<string, unknown>,
  field: string,
  limit: number
): string | undefined {
  const value = optionalString(data, field);
  if (value !== undefined && value.length > limit) {
    throw invalid(`${field} exceeds ${limit} characters`);
  }
  return value;
}

/** Validates the image pair. Both fields present or both absent. */
function parseImage(data: Record<string, unknown>): ValidatedImage | undefined {
  const base64 = optionalString(data, 'imageBase64');
  const rawMediaType = data.mediaType;
  const hasMediaType = rawMediaType !== undefined && rawMediaType !== null;

  if (base64 === undefined) {
    if (hasMediaType) {
      throw invalid('mediaType requires imageBase64');
    }
    return undefined;
  }
  if (!hasMediaType) {
    throw invalid('imageBase64 requires mediaType');
  }
  if (!isAllowedMediaType(rawMediaType)) {
    throw invalid('mediaType must be one of: ' + ALLOWED_MEDIA_TYPES.join(', '));
  }
  if (base64.length === 0) {
    throw invalid('imageBase64 must not be empty');
  }
  if (!isWellFormedBase64(base64)) {
    throw invalid('imageBase64 must be valid base64');
  }
  if (base64DecodedByteLength(base64) > MAX_IMAGE_BYTES) {
    throw invalid(`imageBase64 exceeds ${MAX_IMAGE_BYTES} decoded bytes`);
  }
  return { base64, mediaType: rawMediaType };
}

/**
 * Validates `kind` and the per-kind fields. Every invalid-argument check runs
 * here, before any Firestore access, so a malformed request never burns a
 * credit.
 */
export function parseRequest(raw: unknown): ValidatedRequest {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw invalid('request data must be an object');
  }
  const data = raw as Record<string, unknown>;

  const kind = data.kind;
  if (!isAiProxyKind(kind)) {
    throw invalid('kind must be one of: ' + AI_PROXY_KINDS.join(', '));
  }

  if (kind === 'foodRecognition') {
    const image = parseImage(data);

    const rawText = boundedField(data, 'text', MAX_TEXT_CHARS);
    // Mirrors the client: trim first, and `hasText` is the POST-trim verdict,
    // so a whitespace-only description does not count as text.
    const trimmedText = rawText === undefined ? '' : swiftTrim(rawText);
    const hasText = trimmedText.length > 0;

    // Mirrors `guard hasText || hasImage else { throw .noFoodFound }`.
    if (!hasText && image === undefined) {
      throw invalid('foodRecognition requires text or imageBase64');
    }

    const rawCategory = optionalString(data, 'category');
    let category: FoodCategory | undefined;
    if (rawCategory !== undefined) {
      if (!isFoodCategory(rawCategory)) {
        throw invalid('category must be one of: ' + FOOD_CATEGORIES.join(', '));
      }
      category = rawCategory;
    }

    return {
      kind,
      description: hasText
        ? truncateToCharacters(trimmedText, MAX_INPUT_LENGTH)
        : undefined,
      image,
      category,
      amount: normalizeOptionalField(boundedField(data, 'amount', MAX_FIELD_CHARS)),
      extras: normalizeOptionalField(boundedField(data, 'extras', MAX_FIELD_CHARS)),
    };
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

// MARK: - Prompt assembly (port of AIFoodRecognitionService)

const CATEGORY_LINE_PREFIX = 'Category: ';
const ITEM_LINE_PREFIX = 'Item: ';
const AMOUNT_LINE_PREFIX = 'Amount: ';
const EXTRAS_LINE_PREFIX = 'Extras: ';
const STRUCTURED_LINE_SEPARATOR = '\n';

/**
 * Port of `AIFoodRecognitionService.buildSystemPromptBase(category:)`.
 *
 * No category -> general + " " + schema. With a category, that category's
 * frozen guidance is injected between the two, joined by single spaces.
 */
export function buildSystemPromptBase(category: FoodCategory | undefined): string {
  if (category === undefined) {
    return SYSTEM_PROMPT_GENERAL + ' ' + SYSTEM_PROMPT_SCHEMA_ONWARD;
  }
  return (
    SYSTEM_PROMPT_GENERAL +
    ' ' +
    CATEGORY_GUIDANCE[category] +
    ' ' +
    SYSTEM_PROMPT_SCHEMA_ONWARD
  );
}

/**
 * Port of `AIFoodRecognitionService.composeStructuredInput(...)`.
 *
 * Callers pass ALREADY-NORMALISED values, so `!== undefined` here is exactly
 * the client's `hasText` / `category != nil` / `hasAmount` / `hasExtras`.
 *
 * Two subtleties this port preserves:
 *  - With no structured field at all, the result is the raw description, or —
 *    when there is no text — the `imageOnlyPrompt` constant.
 *  - With a structured field present but NO text, the line block is emitted
 *    WITHOUT an `Item:` line. It does NOT fall back to `imageOnlyPrompt`, and
 *    no placeholder sentence is invented.
 */
export function composeStructuredInput(
  description: string | undefined,
  category: FoodCategory | undefined,
  amount: string | undefined,
  extras: string | undefined
): string {
  if (category === undefined && amount === undefined && extras === undefined) {
    return description !== undefined ? description : IMAGE_ONLY_USER_PROMPT;
  }

  const lines: string[] = [];
  if (category !== undefined) {
    lines.push(CATEGORY_LINE_PREFIX + category);
  }
  if (description !== undefined) {
    lines.push(ITEM_LINE_PREFIX + description);
  }
  if (amount !== undefined) {
    lines.push(AMOUNT_LINE_PREFIX + amount);
  }
  if (extras !== undefined) {
    lines.push(EXTRAS_LINE_PREFIX + extras);
  }
  return lines.join(STRUCTURED_LINE_SEPARATOR);
}

/** Port of the `system:` argument at both `recognize()` call sites. */
function systemPromptFor(request: ValidatedRequest): string {
  if (request.kind === 'onboardingGoals') {
    return ONBOARDING_GOALS_SYSTEM_PROMPT;
  }
  const base = buildSystemPromptBase(request.category);
  // Swift appends the reconciliation rule on the multimodal branch only.
  return request.image === undefined ? base : base + IMAGE_RECONCILIATION_RULE;
}

/**
 * Port of the `messages[0].content` at both `recognize()` call sites: a plain
 * string when there is no image, otherwise `[image, text]` content blocks in
 * that order.
 */
function userContentFor(request: ValidatedRequest): unknown {
  if (request.kind === 'onboardingGoals') {
    return request.text;
  }
  const userText = composeStructuredInput(
    request.description,
    request.category,
    request.amount,
    request.extras
  );
  if (request.image === undefined) {
    return userText;
  }
  return [
    {
      type: ANTHROPIC_IMAGE_BLOCK,
      source: {
        type: ANTHROPIC_BASE64_SOURCE,
        media_type: request.image.mediaType,
        data: request.image.base64,
      },
    },
    { type: ANTHROPIC_TEXT_BLOCK, text: userText },
  ];
}

/** Assembles the request body server-side from constants plus validated input. */
export function buildAnthropicBody(request: ValidatedRequest): Record<string, unknown> {
  const config = KIND_CONFIG[request.kind];
  return {
    model: config.model,
    max_tokens: config.maxTokens,
    system: systemPromptFor(request),
    messages: [{ role: ANTHROPIC_USER_ROLE, content: userContentFor(request) }],
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
