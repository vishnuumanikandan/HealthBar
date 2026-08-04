/**
 * AIMODEL-AB-1 — offline {model} x {resolution} A/B harness for food recognition.
 *
 * Runs a user-supplied set of real food photos and text descriptions through a
 * grid of cells against the Anthropic API and writes one human-readable HTML
 * comparison report. Its output drives two rulings: the `aiProxy` model
 * constant (server-side) and possibly the client's `maxDimension`.
 *
 * This file deploys nothing, changes no client code, changes no function
 * behavior, and is excluded from every build. It is a local analysis tool.
 *
 * THE PROMPTS AND REQUEST ASSEMBLY ARE IMPORTED FROM `functions/src`, NEVER
 * COPIED. `parseRequest` + `buildAnthropicBody` are the same functions the
 * deployed `aiProxy` calls, so the bytes tested here are production bytes by
 * construction. The grid varies exactly two things: the model string and the
 * image long edge. Everything else — system prompt, max_tokens, message
 * shape, media type — comes from the production constants.
 *
 * Usage (see README.md):
 *   AB_ANTHROPIC_API_KEY=... npm run ab
 *   npm run ab:dry          # every preprocessing step, zero network requests
 */

import * as fs from 'node:fs';
import * as path from 'node:path';

import sharp from 'sharp';

import {
  ANTHROPIC_MESSAGES_URL,
  ANTHROPIC_TIMEOUT_MS,
  ANTHROPIC_VERSION,
  MODEL_SONNET,
  buildAnthropicBody,
  parseRequest,
} from '../../functions/src/index';

// MARK: - Grid

/** The two models under test. `MODEL_SONNET` is what `aiProxy` ships today. */
export const BASELINE_MODEL = MODEL_SONNET;
const CANDIDATE_MODEL = 'claude-haiku-4-5';
const MODELS: readonly string[] = [BASELINE_MODEL, CANDIDATE_MODEL];

/**
 * Long edges under test, in pixels. 1568 is the client's current
 * `maxDimension` (`FoodLogViewModel.processImageForRecognition`); 1092 is the
 * cheaper resolution class the report exists to price.
 */
export const BASELINE_LONG_EDGE = 1568;
const PHOTO_LONG_EDGES: readonly number[] = [BASELINE_LONG_EDGE, 1092];

// MARK: - Frozen resize settings

/**
 * Frozen so two machines produce identical bytes from identical inputs. This
 * APPROXIMATES the iOS encoder (`processImageForRecognition`); it does not
 * replicate it. The comparison axis is model behavior vs resolution CLASS, not
 * encoder parity — byte-level encoder differences are out of scope (README).
 *
 * `.rotate()` with no argument applies the EXIF orientation before the pixels
 * are resized. It is required, not optional: EXIF is stripped on the way out
 * (no `withMetadata()`), so without it a portrait phone photo would be sent
 * sideways. iOS normalizes orientation the same way, via
 * `kCGImageSourceCreateThumbnailWithTransform`. It is deterministic, so the
 * identical-bytes property holds.
 */
const JPEG_QUALITY = 70;

// MARK: - Execution

/** Fixed delay between outbound requests. Execution is strictly sequential. */
const INTER_REQUEST_DELAY_MS = 1000;
const MAX_RETRIES = 2;
const RETRY_BASE_DELAY_MS = 2000;

/** The ONLY key path. Never read from Secret Manager, never written to disk. */
const API_KEY_ENV = 'AB_ANTHROPIC_API_KEY';

// MARK: - Paths

const HARNESS_DIR = __dirname;
const FIXTURES_DIR = path.join(HARNESS_DIR, 'fixtures');
const MANIFEST_PATH = path.join(FIXTURES_DIR, 'manifest.json');
const RESULTS_DIR = path.join(HARNESS_DIR, 'results');
const RAW_DIR = path.join(RESULTS_DIR, 'raw');

// MARK: - Pricing (observational metadata ONLY)

/**
 * Published list prices, USD per million tokens.
 *
 * Source: platform.claude.com pricing, read 2026-08-03.
 *
 * These are for the report's cost column and NOTHING else. They must never be
 * imported into `functions/src` or any production code — the server does not
 * price requests, and a stale constant that reached production would be a
 * silent billing lie rather than a stale report footnote.
 */
const PRICING: Readonly<Record<string, { inputPerMTok: number; outputPerMTok: number }>> = {
  'claude-sonnet-4-6': { inputPerMTok: 3.0, outputPerMTok: 15.0 },
  'claude-haiku-4-5': { inputPerMTok: 1.0, outputPerMTok: 5.0 },
};
const PRICING_SOURCE_DATE = '2026-08-03';

// MARK: - Manifest types

interface PhotoCase {
  id: string;
  file: string;
  truth?: string | null;
  category?: string | null;
  text?: string | null;
}

interface TextCase {
  id: string;
  text: string;
  truth?: string | null;
  category?: string | null;
}

interface Manifest {
  photoCases?: PhotoCase[];
  textCases?: TextCase[];
}

// MARK: - Cells

export interface Cell {
  readonly model: string;
  /** null on text-only cases, which have no resolution axis. */
  readonly longEdge: number | null;
  readonly key: string;
  readonly label: string;
  readonly isBaseline: boolean;
  /** True for the model `aiProxy` currently ships. */
  readonly isProduction: boolean;
}

function makeCell(model: string, longEdge: number | null): Cell {
  const suffix = longEdge === null ? 'text' : String(longEdge);
  return {
    model,
    longEdge,
    key: `${model}@${suffix}`,
    label: longEdge === null ? model : `${model} @ ${longEdge}px`,
    // Baseline by IDENTITY, never by execution order.
    isBaseline: model === BASELINE_MODEL && (longEdge === null || longEdge === BASELINE_LONG_EDGE),
    isProduction: model === MODEL_SONNET,
  };
}

/** 4 cells per image: {both models} x {both long edges}, model-major. */
export function photoCells(): Cell[] {
  const cells: Cell[] = [];
  for (const model of MODELS) {
    for (const longEdge of PHOTO_LONG_EDGES) {
      cells.push(makeCell(model, longEdge));
    }
  }
  return cells;
}

/** 2 cells per text case: the two models only. */
export function textCells(): Cell[] {
  return MODELS.map((model) => makeCell(model, null));
}

// MARK: - Pure helpers

/**
 * Cost of one call, computed as exactly
 *   (inputTokens * inputPricePerMTok + outputTokens * outputPricePerMTok) / 1e6
 * Returns null for a model with no pricing entry, so an unpriced cell reads as
 * unknown rather than free.
 */
export function costUsd(model: string, inputTokens: number, outputTokens: number): number | null {
  const price = PRICING[model];
  if (price === undefined) {
    return null;
  }
  return (inputTokens * price.inputPerMTok + outputTokens * price.outputPerMTok) / 1_000_000;
}

/**
 * `YYYYMMDD-HHMMSS` in UTC with ASCII digits, built from the UTC getters with
 * manual padding. `toLocaleDateString` and `Intl` formatters are banned here
 * for the same reason they are in `functions/src/index.ts`: both are locale-
 * and calendar-sensitive and could produce a non-Gregorian or non-ASCII stamp.
 */
export function utcStamp(date: Date): string {
  const pad = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
  const y = date.getUTCFullYear();
  const mo = pad(date.getUTCMonth() + 1);
  const d = pad(date.getUTCDate());
  const h = pad(date.getUTCHours());
  const mi = pad(date.getUTCMinutes());
  const s = pad(date.getUTCSeconds());
  return `${y}${mo}${d}-${h}${mi}${s}`;
}

/** Every model-authored string and every `truth` goes through this. */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Minimal TypeScript port of the CLIENT's JSON-extraction step. The production
 * parser is Swift and cannot be imported, so this is a hand port — and it is a
 * DISPLAY AID, not the measurement. Every cell always shows the raw model text
 * on demand, and a parse failure shows that raw text flagged PARSE-FAIL.
 *
 * Swift source (Nutrition/AIFoodRecognitionService.swift, parseRecognitionJSON):
 *
 *     var text = rawText
 *     text = text.replacingOccurrences(of: "```json", with: "")
 *     text = text.replacingOccurrences(of: "```", with: "")
 *     text = text.trimmingCharacters(in: .whitespacesAndNewlines)
 *     guard let firstBrace = text.firstIndex(of: "{"),
 *           let lastBrace = text.lastIndex(of: "}") else { throw ...decodingFailed }
 *     let jsonString = String(text[firstBrace...lastBrace])
 *     ... JSONDecoder().decode(RecognitionResponse.self, from: jsonData)
 *
 * The one intentional divergence is `.trim()` vs Swift's
 * `.whitespacesAndNewlines`: they differ only on U+FEFF and U+0085, neither of
 * which can appear between the braces of a JSON object.
 */
export function extractRecognitionJSON(rawText: string): unknown {
  let text = rawText.split('```json').join('');
  text = text.split('```').join('');
  text = text.trim();

  const firstBrace = text.indexOf('{');
  const lastBrace = text.lastIndexOf('}');
  if (firstBrace === -1 || lastBrace === -1 || lastBrace < firstBrace) {
    return null;
  }
  try {
    return JSON.parse(text.slice(firstBrace, lastBrace + 1));
  } catch {
    return null;
  }
}

export interface DisplayItem {
  name: string;
  calories: string;
  protein: string;
}

export interface ParsedDisplay {
  parseFailed: boolean;
  items: DisplayItem[];
}

const MISSING = '—';

function displayNumber(value: unknown): string {
  return typeof value === 'number' && Number.isFinite(value) ? String(value) : MISSING;
}

/**
 * Display view of one model response. `items` absent or empty is a VALID parse
 * (the schema's clarification path returns `{"items":[], ...}`, and every field
 * on the Swift DTO is optional) — only unparseable text is a PARSE-FAIL.
 */
export function parseForDisplay(rawText: string): ParsedDisplay {
  const decoded = extractRecognitionJSON(rawText);
  if (typeof decoded !== 'object' || decoded === null || Array.isArray(decoded)) {
    return { parseFailed: true, items: [] };
  }
  const rawItems = (decoded as { items?: unknown }).items;
  if (!Array.isArray(rawItems)) {
    return { parseFailed: false, items: [] };
  }
  const items: DisplayItem[] = [];
  for (const raw of rawItems) {
    if (typeof raw !== 'object' || raw === null) {
      continue;
    }
    const typed = raw as { name?: unknown; calories?: unknown; protein?: unknown };
    items.push({
      name: typeof typed.name === 'string' && typed.name.length > 0 ? typed.name : '(unnamed)',
      calories: displayNumber(typed.calories),
      protein: displayNumber(typed.protein),
    });
  }
  return { parseFailed: false, items };
}

/** Display-only comparison against the baseline cell. No pass/fail verdict. */
export function itemCountVerdict(
  baselineCount: number | null,
  cellCount: number | null
): 'agree' | 'differ' | 'n/a' {
  if (baselineCount === null || cellCount === null) {
    return 'n/a';
  }
  return baselineCount === cellCount ? 'agree' : 'differ';
}

/**
 * The production request body with the cell's model swapped in. `parseRequest`
 * and `buildAnthropicBody` are imported from `functions/src`, so validation,
 * normalisation, prompt selection, and message shape are all the deployed
 * code. Throws on an invalid request rather than sending something the server
 * would reject.
 */
export function buildCellBody(raw: unknown, model: string): Record<string, unknown> {
  return { ...buildAnthropicBody(parseRequest(raw)), model };
}

// MARK: - Results

export interface CellResult {
  caseId: string;
  cell: Cell;
  status: 'ok' | 'failed' | 'dry-run';
  error?: string;
  imageBytes?: number;
  latencyMs?: number;
  attempts?: number;
  inputTokens?: number;
  outputTokens?: number;
  cost?: number | null;
  rawText?: string;
  display?: ParsedDisplay;
}

export interface CaseResult {
  id: string;
  kind: 'photo' | 'text';
  truth: string | null;
  category: string | null;
  text: string | null;
  file: string | null;
  cells: CellResult[];
}

// MARK: - Manifest loading

const USAGE = [
  'AIMODEL-AB-1 — offline model x resolution A/B harness.',
  '',
  '  npm run ab        AB_ANTHROPIC_API_KEY must be set',
  '  npm run ab:dry    preprocessing only, zero network requests',
  '',
  `Expects a manifest at ${path.join('fixtures', 'manifest.json')} with at least`,
  'one entry. See README.md for the schema and a worked example.',
].join('\n');

function fail(message: string): never {
  console.error(`${message}\n\n${USAGE}`);
  process.exit(1);
}

function requireString(value: unknown, where: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    fail(`manifest: ${where} must be a non-empty string`);
  }
  return value;
}

function optionalString(value: unknown, where: string): string | null {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    fail(`manifest: ${where} must be a string or null`);
  }
  return value;
}

function loadManifest(): Manifest {
  if (!fs.existsSync(MANIFEST_PATH)) {
    fail(`No manifest found at ${MANIFEST_PATH}`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
  } catch (error) {
    fail(`Manifest is not valid JSON: ${errorMessage(error)}`);
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    fail('Manifest must be a JSON object.');
  }
  const manifest = parsed as Manifest;

  const photoCases = manifest.photoCases ?? [];
  const textCases = manifest.textCases ?? [];
  if (!Array.isArray(photoCases) || !Array.isArray(textCases)) {
    fail('manifest: photoCases and textCases must be arrays.');
  }
  if (photoCases.length === 0 && textCases.length === 0) {
    fail('Manifest is empty — nothing to run.');
  }

  photoCases.forEach((entry, i) => {
    requireString(entry?.id, `photoCases[${i}].id`);
    requireString(entry?.file, `photoCases[${i}].file`);
    optionalString(entry?.truth, `photoCases[${i}].truth`);
    optionalString(entry?.category, `photoCases[${i}].category`);
    optionalString(entry?.text, `photoCases[${i}].text`);
  });
  textCases.forEach((entry, i) => {
    requireString(entry?.id, `textCases[${i}].id`);
    requireString(entry?.text, `textCases[${i}].text`);
    optionalString(entry?.truth, `textCases[${i}].truth`);
    optionalString(entry?.category, `textCases[${i}].category`);
  });

  return { photoCases, textCases };
}

// MARK: - Image preprocessing

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Resize to the target long edge (never upscaling) and re-encode as JPEG with
 * the frozen settings. HEIC input decodes here too, when the installed sharp
 * build carries HEIF support; when it does not, the throw surfaces as a failed
 * case and the run continues.
 */
async function resizeToLongEdge(source: Buffer, longEdge: number): Promise<Buffer> {
  return sharp(source)
    .rotate()
    .resize({ width: longEdge, height: longEdge, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: JPEG_QUALITY, progressive: false, mozjpeg: false })
    .toBuffer();
}

// MARK: - Anthropic

function concatTextBlocks(payload: unknown): string | null {
  if (typeof payload !== 'object' || payload === null) {
    return null;
  }
  const content = (payload as { content?: unknown }).content;
  if (!Array.isArray(content)) {
    return null;
  }
  let combined = '';
  let sawText = false;
  for (const block of content) {
    if (typeof block !== 'object' || block === null) {
      continue;
    }
    const typed = block as { type?: unknown; text?: unknown };
    if (typed.type === 'text' && typeof typed.text === 'string') {
      combined += typed.text;
      sawText = true;
    }
  }
  return sawText ? combined : null;
}

function usageCount(payload: unknown, field: string): number {
  if (typeof payload !== 'object' || payload === null) {
    return 0;
  }
  const usage = (payload as { usage?: unknown }).usage;
  if (typeof usage !== 'object' || usage === null) {
    return 0;
  }
  const value = (usage as Record<string, unknown>)[field];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

interface CallOutcome {
  rawText: string;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
  attempts: number;
  payload: unknown;
}

/**
 * One cell's call. Retries up to MAX_RETRIES on 429/5xx with exponential
 * backoff (honouring an integer `retry-after` when the server sends one).
 * Anything else throws, and the caller records a failed cell — a failure never
 * aborts the run.
 */
async function callAnthropic(body: Record<string, unknown>, apiKey: string): Promise<CallOutcome> {
  let lastError = 'unknown error';

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt += 1) {
    if (attempt > 0) {
      await sleep(RETRY_BASE_DELAY_MS * 2 ** (attempt - 1));
    }
    const startedAt = Date.now();
    let response: Response;
    try {
      response = await fetch(ANTHROPIC_MESSAGES_URL, {
        method: 'POST',
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': ANTHROPIC_VERSION,
          'content-type': 'application/json',
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(ANTHROPIC_TIMEOUT_MS),
      });
    } catch (error) {
      throw new Error(`network: ${errorMessage(error)}`);
    }
    const latencyMs = Date.now() - startedAt;

    if (response.status === 429 || response.status >= 500) {
      lastError = `HTTP ${response.status}`;
      const retryAfter = Number(response.headers.get('retry-after'));
      if (Number.isFinite(retryAfter) && retryAfter > 0 && attempt < MAX_RETRIES) {
        await sleep(retryAfter * 1000);
      }
      continue;
    }
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const payload: unknown = await response.json();
    const rawText = concatTextBlocks(payload);
    if (rawText === null) {
      throw new Error('response contained no text block');
    }
    return {
      rawText,
      inputTokens: usageCount(payload, 'input_tokens'),
      outputTokens: usageCount(payload, 'output_tokens'),
      latencyMs,
      attempts: attempt + 1,
      payload,
    };
  }
  throw new Error(`${lastError} after ${MAX_RETRIES + 1} attempts`);
}

// MARK: - Raw per-call records

const IMAGE_ELIDED = (chars: number): string => `<base64 elided: ${chars} chars>`;

function safeFileName(value: string): string {
  return value.replace(/[^A-Za-z0-9._@-]/g, '_');
}

function writeRawRecord(rawRunDir: string, caseId: string, cell: Cell, record: unknown): void {
  const file = path.join(rawRunDir, `${safeFileName(caseId)}__${safeFileName(cell.key)}.json`);
  fs.writeFileSync(file, `${JSON.stringify(record, null, 2)}\n`, 'utf8');
}

/** The request as sent, minus the image payload. Never carries the API key. */
function elideImage(body: Record<string, unknown>): Record<string, unknown> {
  const clone = JSON.parse(JSON.stringify(body)) as Record<string, unknown>;
  const messages = clone.messages;
  if (!Array.isArray(messages)) {
    return clone;
  }
  for (const message of messages) {
    const content = (message as { content?: unknown }).content;
    if (!Array.isArray(content)) {
      continue;
    }
    for (const block of content) {
      const source = (block as { source?: { data?: unknown } }).source;
      if (source !== undefined && typeof source.data === 'string') {
        source.data = IMAGE_ELIDED(source.data.length);
      }
    }
  }
  return clone;
}

// MARK: - Runner

interface RunOptions {
  dryRun: boolean;
  apiKey: string;
  rawRunDir: string;
}

async function runCell(
  caseId: string,
  cell: Cell,
  raw: Record<string, unknown>,
  imageBytes: number | undefined,
  options: RunOptions,
  state: { sentAny: boolean }
): Promise<CellResult> {
  const base: CellResult = { caseId, cell, status: 'failed', imageBytes };

  let body: Record<string, unknown>;
  try {
    body = buildCellBody(raw, cell.model);
  } catch (error) {
    return { ...base, error: `assembly: ${errorMessage(error)}` };
  }

  if (options.dryRun) {
    // The EXACT outbound request JSON, image payload included.
    writeRawRecord(options.rawRunDir, caseId, cell, {
      mode: 'dry-run',
      caseId,
      cell: cell.key,
      model: cell.model,
      longEdge: cell.longEdge,
      imageBytes: imageBytes ?? null,
      url: ANTHROPIC_MESSAGES_URL,
      anthropicVersion: ANTHROPIC_VERSION,
      request: body,
    });
    return { ...base, status: 'dry-run' };
  }

  if (state.sentAny) {
    await sleep(INTER_REQUEST_DELAY_MS);
  }
  state.sentAny = true;

  try {
    const outcome = await callAnthropic(body, options.apiKey);
    const result: CellResult = {
      ...base,
      status: 'ok',
      latencyMs: outcome.latencyMs,
      attempts: outcome.attempts,
      inputTokens: outcome.inputTokens,
      outputTokens: outcome.outputTokens,
      cost: costUsd(cell.model, outcome.inputTokens, outcome.outputTokens),
      rawText: outcome.rawText,
      display: parseForDisplay(outcome.rawText),
    };
    writeRawRecord(options.rawRunDir, caseId, cell, {
      mode: 'live',
      caseId,
      cell: cell.key,
      model: cell.model,
      longEdge: cell.longEdge,
      imageBytes: imageBytes ?? null,
      latencyMs: outcome.latencyMs,
      attempts: outcome.attempts,
      requestWithoutImage: elideImage(body),
      response: outcome.payload,
    });
    return result;
  } catch (error) {
    const message = errorMessage(error);
    writeRawRecord(options.rawRunDir, caseId, cell, {
      mode: 'live',
      caseId,
      cell: cell.key,
      error: message,
      requestWithoutImage: elideImage(body),
    });
    return { ...base, error: message };
  }
}

async function runPhotoCase(entry: PhotoCase, options: RunOptions, state: { sentAny: boolean }): Promise<CaseResult> {
  const cells = photoCells();
  const result: CaseResult = {
    id: entry.id,
    kind: 'photo',
    truth: entry.truth ?? null,
    category: entry.category ?? null,
    text: entry.text ?? null,
    file: entry.file,
    cells: [],
  };

  // Resize once per long edge, so both models at the same resolution see
  // byte-identical input.
  const resized = new Map<number, Buffer>();
  try {
    const source = fs.readFileSync(path.resolve(FIXTURES_DIR, entry.file));
    for (const longEdge of PHOTO_LONG_EDGES) {
      resized.set(longEdge, await resizeToLongEdge(source, longEdge));
    }
  } catch (error) {
    const message = `image: ${errorMessage(error)}`;
    console.log(`    ! ${entry.id}: ${message}`);
    result.cells = cells.map((cell) => ({ caseId: entry.id, cell, status: 'failed', error: message }));
    return result;
  }

  for (const cell of cells) {
    const buffer = resized.get(cell.longEdge as number) as Buffer;
    const raw = {
      kind: 'foodRecognition',
      text: entry.text ?? null,
      category: entry.category ?? null,
      imageBase64: buffer.toString('base64'),
      mediaType: 'image/jpeg',
    };
    const cellResult = await runCell(entry.id, cell, raw, buffer.length, options, state);
    console.log(`    ${cellResult.status === 'failed' ? '!' : '.'} ${cell.key} (${cellResult.status})`);
    result.cells.push(cellResult);
  }
  return result;
}

async function runTextCase(entry: TextCase, options: RunOptions, state: { sentAny: boolean }): Promise<CaseResult> {
  const result: CaseResult = {
    id: entry.id,
    kind: 'text',
    truth: entry.truth ?? null,
    category: entry.category ?? null,
    text: entry.text,
    file: null,
    cells: [],
  };
  for (const cell of textCells()) {
    const raw = { kind: 'foodRecognition', text: entry.text, category: entry.category ?? null };
    const cellResult = await runCell(entry.id, cell, raw, undefined, options, state);
    console.log(`    ${cellResult.status === 'failed' ? '!' : '.'} ${cell.key} (${cellResult.status})`);
    result.cells.push(cellResult);
  }
  return result;
}

// MARK: - Report

function fmtUsd(value: number | null | undefined): string {
  return value === null || value === undefined ? MISSING : `$${value.toFixed(4)}`;
}

function fmtMs(value: number | undefined): string {
  return value === undefined ? MISSING : `${(value / 1000).toFixed(2)} s`;
}

function fmtBytes(value: number | undefined): string {
  return value === undefined ? MISSING : `${(value / 1024).toFixed(0)} KB`;
}

function itemCountOf(result: CellResult | undefined): number | null {
  if (result === undefined || result.status !== 'ok' || result.display === undefined) {
    return null;
  }
  return result.display.parseFailed ? null : result.display.items.length;
}

function renderItems(result: CellResult): string {
  if (result.status === 'dry-run') {
    return '<span class="muted">not sent</span>';
  }
  if (result.status === 'failed') {
    return `<span class="bad">FAILED</span><div class="muted">${escapeHtml(result.error ?? '')}</div>`;
  }
  const display = result.display as ParsedDisplay;
  if (display.parseFailed) {
    return '<span class="bad">PARSE-FAIL</span><div class="muted">raw text below</div>';
  }
  if (display.items.length === 0) {
    return '<span class="muted">no items</span>';
  }
  const rows = display.items
    .map(
      (item) =>
        `<li><b>${escapeHtml(item.name)}</b><br><span class="muted">${escapeHtml(item.calories)} kcal · ${escapeHtml(item.protein)} g protein</span></li>`
    )
    .join('');
  return `<ol class="items">${rows}</ol>`;
}

function renderRawText(result: CellResult): string {
  if (result.rawText === undefined) {
    return `<span class="muted">${MISSING}</span>`;
  }
  return `<details><summary>raw model text (${result.rawText.length} chars)</summary><pre>${escapeHtml(result.rawText)}</pre></details>`;
}

export function renderCaseBlock(entry: CaseResult): string {
  const cells = entry.cells;
  const baseline = cells.find((c) => c.cell.isBaseline);
  const baselineCount = itemCountOf(baseline);

  const meta: string[] = [];
  if (entry.truth !== null) {
    meta.push(`<div><span class="k">ground truth</span> ${escapeHtml(entry.truth)}</div>`);
  }
  if (entry.text !== null) {
    meta.push(`<div><span class="k">describe text</span> ${escapeHtml(entry.text)}</div>`);
  }
  if (entry.category !== null) {
    meta.push(`<div><span class="k">category</span> ${escapeHtml(entry.category)}</div>`);
  }
  if (entry.file !== null) {
    meta.push(`<div><span class="k">file</span> ${escapeHtml(entry.file)}</div>`);
  }

  const head = cells
    .map((c) => {
      const tags: string[] = [];
      if (c.cell.isBaseline) tags.push('<span class="tag">baseline</span>');
      if (c.cell.isProduction) tags.push('<span class="tag">production model</span>');
      return `<th>${escapeHtml(c.cell.label)}<div>${tags.join(' ')}</div></th>`;
    })
    .join('');

  const row = (label: string, render: (c: CellResult) => string): string =>
    `<tr><th class="rowhead">${label}</th>${cells.map((c) => `<td>${render(c)}</td>`).join('')}</tr>`;

  const body = [
    row('items', renderItems),
    row('item count vs baseline', (c) => {
      if (c.cell.isBaseline) return '<span class="muted">baseline</span>';
      const verdict = itemCountVerdict(baselineCount, itemCountOf(c));
      const cls = verdict === 'agree' ? 'good' : verdict === 'differ' ? 'warn' : 'muted';
      return `<span class="${cls}">${verdict}</span>`;
    }),
    row('resized image', (c) => fmtBytes(c.imageBytes)),
    row('tokens in / out', (c) =>
      c.status === 'ok' ? `${c.inputTokens} / ${c.outputTokens}` : MISSING
    ),
    row('cost', (c) => (c.status === 'ok' ? fmtUsd(c.cost) : MISSING)),
    row('latency', (c) => fmtMs(c.latencyMs)),
    row('raw', renderRawText),
  ].join('');

  return `<section class="case">
  <h3>${escapeHtml(entry.id)} <span class="muted">(${entry.kind})</span></h3>
  <div class="meta">${meta.join('')}</div>
  <div class="scroll"><table class="cells"><thead><tr><th class="rowhead"></th>${head}</tr></thead><tbody>${body}</tbody></table></div>
</section>`;
}

export function renderSummary(cases: CaseResult[]): string {
  const keys: string[] = [];
  const byKey = new Map<string, CellResult[]>();
  for (const entry of cases) {
    for (const result of entry.cells) {
      const list = byKey.get(result.cell.key);
      if (list === undefined) {
        keys.push(result.cell.key);
        byKey.set(result.cell.key, [result]);
      } else {
        list.push(result);
      }
    }
  }

  const baselineCountByCase = new Map<string, number | null>();
  for (const entry of cases) {
    baselineCountByCase.set(entry.id, itemCountOf(entry.cells.find((c) => c.cell.isBaseline)));
  }

  const rows = keys
    .map((key) => {
      const results = byKey.get(key) as CellResult[];
      const cell = results[0].cell;
      const ok = results.filter((r) => r.status === 'ok');
      const failed = results.filter((r) => r.status === 'failed').length;
      const parseFails = ok.filter((r) => r.display?.parseFailed === true).length;
      const totalCost = ok.reduce((sum, r) => sum + (r.cost ?? 0), 0);
      const anyUnpriced = ok.some((r) => r.cost === null || r.cost === undefined);
      const meanLatency =
        ok.length === 0 ? undefined : ok.reduce((s, r) => s + (r.latencyMs ?? 0), 0) / ok.length;
      const withBytes = results.filter((r) => r.imageBytes !== undefined);
      const meanBytes =
        withBytes.length === 0
          ? undefined
          : withBytes.reduce((s, r) => s + (r.imageBytes as number), 0) / withBytes.length;

      let agreement = '<span class="muted">baseline</span>';
      if (!cell.isBaseline) {
        let agree = 0;
        let comparable = 0;
        for (const r of results) {
          const verdict = itemCountVerdict(baselineCountByCase.get(r.caseId) ?? null, itemCountOf(r));
          if (verdict === 'n/a') continue;
          comparable += 1;
          if (verdict === 'agree') agree += 1;
        }
        agreement = comparable === 0 ? `<span class="muted">${MISSING}</span>` : `${agree} / ${comparable}`;
      }

      const tags: string[] = [];
      if (cell.isBaseline) tags.push('<span class="tag">baseline</span>');
      if (cell.isProduction) tags.push('<span class="tag">production model</span>');

      return `<tr>
    <td>${escapeHtml(cell.label)} ${tags.join(' ')}</td>
    <td>${results.length}</td>
    <td class="${failed > 0 ? 'bad' : ''}">${failed}</td>
    <td class="${parseFails > 0 ? 'warn' : ''}">${parseFails}</td>
    <td>${ok.length === 0 ? MISSING : fmtUsd(totalCost)}${anyUnpriced ? ' <span class="warn">(unpriced cells)</span>' : ''}</td>
    <td>${fmtMs(meanLatency)}</td>
    <td>${fmtBytes(meanBytes)}</td>
    <td>${agreement}</td>
  </tr>`;
    })
    .join('');

  return `<div class="scroll"><table class="summary">
  <thead><tr>
    <th>cell</th><th>calls</th><th>failed</th><th>PARSE-FAIL</th>
    <th>total cost</th><th>mean latency</th><th>mean image</th><th>item-count agreement</th>
  </tr></thead>
  <tbody>${rows}</tbody>
</table></div>`;
}

const STYLE = `
:root { color-scheme: light dark; --fg:#1a1a1a; --muted:#6b6b6b; --line:#d8d8d8; --bg:#fff; --panel:#f7f7f7; }
@media (prefers-color-scheme: dark) {
  :root { --fg:#e8e8e8; --muted:#9a9a9a; --line:#3a3a3a; --bg:#131313; --panel:#1c1c1c; }
}
* { box-sizing: border-box; }
body { margin:0; padding:24px; background:var(--bg); color:var(--fg);
  font:14px/1.5 ui-sans-serif,-apple-system,"Segoe UI",Roboto,sans-serif; }
h1 { font-size:20px; margin:0 0 4px; }
h2 { font-size:16px; margin:32px 0 8px; border-bottom:1px solid var(--line); padding-bottom:6px; }
h3 { font-size:15px; margin:0 0 8px; }
.scroll { overflow-x:auto; max-width:100%; }
table { border-collapse:collapse; font-size:13px; }
th, td { border:1px solid var(--line); padding:6px 10px; text-align:left; vertical-align:top; }
thead th { background:var(--panel); white-space:nowrap; }
.rowhead { background:var(--panel); white-space:nowrap; font-weight:600; width:1%; }
.cells td { min-width:220px; }
.case { margin:24px 0 32px; }
.meta { margin-bottom:10px; font-size:13px; }
.meta .k { display:inline-block; min-width:110px; color:var(--muted); }
.items { margin:0; padding-left:18px; }
.items li { margin-bottom:4px; }
pre { white-space:pre-wrap; word-break:break-word; margin:6px 0 0; padding:8px;
  background:var(--panel); border:1px solid var(--line); font-size:12px; max-height:340px; overflow:auto; }
summary { cursor:pointer; color:var(--muted); }
.muted { color:var(--muted); }
.good { color:#1a7f37; font-weight:600; }
.warn { color:#9a6700; font-weight:600; }
.bad  { color:#b42318; font-weight:600; }
.tag { display:inline-block; font-size:11px; padding:1px 6px; border:1px solid var(--line);
  border-radius:10px; color:var(--muted); white-space:nowrap; }
.note { background:var(--panel); border:1px solid var(--line); padding:12px 14px; margin:16px 0; font-size:13px; }
.note p { margin:0 0 8px; } .note p:last-child { margin:0; }
`;

function renderReport(cases: CaseResult[], stamp: string, dryRun: boolean): string {
  const priceRows = Object.entries(PRICING)
    .map(([model, p]) => `${escapeHtml(model)}: $${p.inputPerMTok.toFixed(2)} in / $${p.outputPerMTok.toFixed(2)} out per MTok`)
    .join(' · ');

  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AIMODEL-AB-1 report ${escapeHtml(stamp)}</title>
<style>${STYLE}</style></head><body>
<h1>AIMODEL-AB-1 — model x resolution comparison</h1>
<div class="muted">${escapeHtml(stamp)} UTC${dryRun ? ' · <b>DRY RUN</b> — no requests were sent' : ''}</div>

<div class="note">
  <p><b>Grid.</b> Photo cases: {${MODELS.map(escapeHtml).join(', ')}} x {${PHOTO_LONG_EDGES.join(', ')}} px long edge.
  Text-only cases: the two models. The baseline is the
  <b>${escapeHtml(BASELINE_MODEL)} / ${BASELINE_LONG_EDGE}</b> cell by identity, regardless of execution order.</p>
  <p><b>Pricing (observational only).</b> ${priceRows}. Source: platform.claude.com, read ${PRICING_SOURCE_DATE}.
  Cost = (input x inPrice + output x outPrice) / 1,000,000.</p>
  <p><b>Encoder caveat.</b> Resizing here uses sharp (long-edge fit, no upscaling, JPEG q${JPEG_QUALITY},
  EXIF applied then stripped). That approximates the iOS encoder, it does not replicate it — the axis this
  report measures is model behavior vs resolution <i>class</i>, not encoder parity.</p>
  <p><b>Parsed items are a display aid.</b> They come from a TypeScript port of the client's JSON-extraction
  step, not from the measurement. Every cell shows the raw model text on demand; a failed parse is flagged
  PARSE-FAIL and shows raw text. Item-count agreement is display only — there is no pass/fail verdict here.</p>
</div>

<h2>Summary</h2>
${renderSummary(cases)}

<h2>Cases</h2>
${cases.map(renderCaseBlock).join('\n')}
</body></html>
`;
}

// MARK: - Entry point

async function main(): Promise<void> {
  const dryRun = process.argv.includes('--dry-run');
  const apiKey = process.env[API_KEY_ENV] ?? '';
  if (!dryRun && apiKey.length === 0) {
    fail(`${API_KEY_ENV} is not set.`);
  }

  const manifest = loadManifest();
  const photoCases = manifest.photoCases ?? [];
  const textCases = manifest.textCases ?? [];
  const plannedCalls = photoCases.length * photoCells().length + textCases.length * textCells().length;

  const stamp = utcStamp(new Date());
  const rawRunDir = path.join(RAW_DIR, stamp);
  fs.mkdirSync(rawRunDir, { recursive: true });

  console.log(`AIMODEL-AB-1${dryRun ? ' (dry run — zero network requests)' : ''}`);
  console.log(`  ${photoCases.length} photo case(s), ${textCases.length} text case(s) -> ${plannedCalls} cell(s)`);

  const options: RunOptions = { dryRun, apiKey, rawRunDir };
  const state = { sentAny: false };
  const results: CaseResult[] = [];

  for (const entry of photoCases) {
    console.log(`  ${entry.id}`);
    results.push(await runPhotoCase(entry, options, state));
  }
  for (const entry of textCases) {
    console.log(`  ${entry.id}`);
    results.push(await runTextCase(entry, options, state));
  }

  // Re-runs append a new timestamped report; nothing is overwritten.
  const reportPath = path.join(RESULTS_DIR, `report-${stamp}.html`);
  fs.writeFileSync(reportPath, renderReport(results, stamp, dryRun), 'utf8');

  const failed = results.flatMap((r) => r.cells).filter((c) => c.status === 'failed').length;
  console.log(`\nreport: ${reportPath}`);
  console.log(`raw:    ${rawRunDir}`);
  if (failed > 0) {
    console.log(`${failed} cell(s) failed — see the report.`);
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(errorMessage(error));
    process.exit(1);
  });
}
