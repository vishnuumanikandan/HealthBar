# AIMODEL-AB-1 — offline model × resolution A/B harness

A standalone TypeScript harness that runs **your own** food photos and text
descriptions through a grid of `{model} × {resolution}` cells against the
Anthropic API, and writes one human-readable HTML comparison report.

It exists to inform two rulings:

1. the `aiProxy` model constant (server-side, `functions/src/index.ts`), and
2. possibly the client's `maxDimension` (`FoodLogViewModel.processImageForRecognition`) —
   a **later** micro-prompt, not this one.

**This harness deploys nothing.** It changes no client code, changes no function
behavior, and is excluded from every build. Its only output is a report you read
with your own eyes — it computes no score and issues no verdict.

---

## The grid

| Case type  | Cells                                                                 |
| ---------- | --------------------------------------------------------------------- |
| Photo      | `claude-sonnet-4-6` / `claude-haiku-4-5` × long edge `1568` / `1092` → **4 cells** |
| Text-only  | the two models → **2 cells**                                          |

**The grid varies exactly two things: the model string and the image long edge.**
Max tokens, the system prompt, the message shape, and the media type all come
from the production constants — the harness *imports* `parseRequest` and
`buildAnthropicBody` from `functions/src/index.ts` rather than copying them, so
the bytes it tests are the bytes `aiProxy` sends, by construction.

The **baseline** is the `claude-sonnet-4-6` / `1568` cell, chosen by identity
rather than by execution order. Text-only cases have no resolution axis, so
their baseline is the `claude-sonnet-4-6` cell.

---

## Prerequisites

- **Node 20+** (this repo's Cloud Functions runtime; the harness is tested on 24).
- The Cloud Functions dependencies installed, because the harness imports
  `functions/src`:

  ```sh
  npm --prefix ../../functions install
  ```

- The harness's own dependencies:

  ```sh
  cd scripts/ai-model-ab
  npm install
  ```

---

## The API key: mint it, use it, delete it

The key is read from the environment variable **`AB_ANTHROPIC_API_KEY`** and
nothing else. The harness never reads Secret Manager, never touches the
function's `ANTHROPIC_API_KEY` secret or the `healthbar-aiproxy` key, and never
writes a key to disk — not to the report, not to the raw JSON records.

1. In the [Anthropic Console](https://console.anthropic.com/settings/keys),
   create a **temporary** key named something like `ab-harness-temp`.
2. Export it for the run only — don't put it in a shell profile or a `.env`:

   ```sh
   export AB_ANTHROPIC_API_KEY='...'
   ```

3. **Delete that key in the console when the run is done.**

---

## Fixtures — never committed

Put your photos and a `manifest.json` in `fixtures/`. Reports and raw per-call
JSON land in `results/`. **Both directories are gitignored, and must stay that
way: this repository is public, so a committed food photo is a published
photo.** The raw records also embed model output and (in `--dry-run`) full
base64 image payloads.

### `fixtures/manifest.json`

```jsonc
{
  "photoCases": [
    {
      "id": "lunch-01",                  // required, used in filenames and the report
      "file": "lunch-01.jpg",            // required, relative to fixtures/
      "truth": "grilled chicken breast, white rice, steamed broccoli",
      "category": "meal",                // meal | snack | drink | fruit | veggie | sweet, or null
      "text": "chicken and rice bowl"    // optional describe-text sent alongside the photo, or null
    }
  ],
  "textCases": [
    {
      "id": "txt-01",                    // required
      "text": "two scrambled eggs and buttered toast",  // required
      "truth": "two scrambled eggs and one slice of buttered toast",
      "category": null
    }
  ]
}
```

`truth` is your human ground-truth description. **It is used only for display in
the report** — the harness performs no automated scoring against it. Both arrays
are optional individually, but the manifest must contain at least one case.

Accepted image formats are whatever the installed `sharp` build decodes. HEIC
works when that build carries HEIF support; when it doesn't, the case is marked
failed with the decode error and the run continues — convert those files to JPEG
and re-run.

---

## Running it

```sh
cd scripts/ai-model-ab

# Preprocessing only: resize, base64, assemble, write the exact outbound
# request JSON to results/raw/. Zero network requests, no API key needed.
npm run ab:dry

# The real run.
AB_ANTHROPIC_API_KEY='...' npm run ab
```

Execution is strictly **sequential**, with a fixed 1000 ms delay between
requests and up to 2 retries on 429/5xx with exponential backoff. A cell that
still fails is recorded as a failed cell in the report — a failure never aborts
the run.

Re-runs append a new timestamped report; **nothing is overwritten**.

```
results/
  report-YYYYMMDD-HHMMSS.html      # UTC timestamp, ASCII digits
  raw/YYYYMMDD-HHMMSS/
    <caseId>__<model>@<longEdge>.json
```

In `--dry-run` the raw record holds the **exact** outbound request, base64
payload included. In a live run it holds the full response plus the request with
the image payload elided (a `<base64 elided: N chars>` marker), so the files stay
readable — the exact request for any cell is reproducible with `npm run ab:dry`.

---

## Estimating the cost before you run

```
cost = (inputTokens × inputPricePerMTok + outputTokens × outputPricePerMTok) / 1,000,000
```

Published list prices, USD per million tokens (source: platform.claude.com, read
2026-08-03 — they are pinned at the top of `run.ts`):

| Model               | Input | Output |
| ------------------- | ----- | ------ |
| `claude-sonnet-4-6` | $3.00 | $15.00 |
| `claude-haiku-4-5`  | $1.00 | $5.00  |

These constants are **observational metadata for the report only**. They must
never be imported into `functions/src` or any production code.

To size a run: a 1568 px photo is roughly 1.5–1.8 k input tokens and a 1092 px
photo roughly 0.8–1.0 k, on top of ~0.9 k for the system prompt; a recognition
reply is typically 250–600 output tokens. So one photo case (4 cells) lands
around **$0.02–$0.04**, and one text case (2 cells) around **$0.005**. Twenty
photo cases is well under a dollar. Take the numbers the report prints as the
real answer — the estimate above is only for deciding how many fixtures to shoot.

---

## Encoder-parity caveat (read this before drawing conclusions)

Resizing uses `sharp` with frozen settings — fit the long edge without
upscaling, apply the EXIF orientation and then strip metadata, encode JPEG at
quality 70, progressive off, default chroma subsampling, mozjpeg off. Frozen so
two machines produce identical bytes from identical inputs.

**This approximates the iOS encoder, it does not replicate it.** The client
(`FoodLogViewModel.processImageForRecognition`) downsamples through
`CGImageSourceCreateThumbnailAtIndex` and then re-encodes with
`UIImage.jpegData(compressionQuality:)`, starting at 0.7 and stepping down until
the payload is under 1 MB. Different resampling kernel, different JPEG encoder,
different quality-vs-size loop.

So the axis this report measures is **model behavior versus resolution class**,
not encoder parity. Byte-level encoder differences are out of scope; a result
here says "1092 px is/isn't enough for this model," not "the client's exact
1092 px bytes behave this way."

The orientation step is not optional, by the way: EXIF is stripped on the way
out, so without applying it first a portrait phone photo would reach the model
sideways. iOS normalizes orientation the same way, via
`kCGImageSourceCreateThumbnailWithTransform`.

---

## Reading the report

- **Summary table** — per cell: calls, failures, PARSE-FAIL count, total cost,
  mean latency, mean resized image size, and item-count agreement with the
  baseline cell.
- **Per case** — every cell side by side: parsed items (name / calories /
  protein), tokens in and out, cost, latency, resized image size, and the raw
  model text on demand.

The parsed items are a **display aid**, produced by a minimal TypeScript port of
the client's JSON-extraction step (`AIFoodRecognitionService.parseRecognitionJSON`:
strip ``` fences → take first `{` through last `}` → decode). The production
parser is Swift and cannot be imported, so the port is a hand copy of those three
steps and nothing more — it does not reproduce `normalizeItems`' clamping or
Atwater reconciliation. **The measurement is always the raw model text**, which
every cell shows on demand; a cell whose text won't parse is flagged
`PARSE-FAIL` and shows the raw text.

Item-count agreement is likewise display only: same item count as the baseline
means "agree", and that is all it means. **There is no pass/fail verdict in this
report. The ruling is your eyeball.**
