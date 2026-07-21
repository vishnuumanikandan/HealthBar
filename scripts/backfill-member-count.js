#!/usr/bin/env node
/**
 * backfill-member-count.js — GUILD-CAP-1 one-off backfill.
 *
 * Sets `memberCount` on every `guilds/{code}` doc to the true size of its
 * `members` subcollection, so the field the new security rules enforce against
 * EXISTS and is ACCURATE before those rules are deployed.
 *
 * ── RUNSHEET ORDER (load-bearing) ────────────────────────────────────────────
 * Run this backfill (dry-run, review, then live) BEFORE
 * `firebase deploy --only firestore:rules`. The new rules require every
 * membership batch to carry a memberCount ±1 paired against the EXISTING field
 * (`getAfter(guild).memberCount == get(guild).memberCount + 1`, etc.). A guild
 * still missing `memberCount` would have every join/leave DENIED — the
 * `get(...).memberCount` on a missing field fails the rule. Backfilling first
 * guarantees the field is present so the deploy is safe. The old rules ignore
 * `memberCount` entirely, so this backfill changes nothing observable until the
 * rules deploy that follows it.
 *
 * ── IDEMPOTENT ───────────────────────────────────────────────────────────────
 * Safe to re-run: each guild's count is recomputed from the LIVE roster and
 * written only when it differs. Re-running therefore also HEALS transitional
 * drift (e.g. the accepted owner-tamper limitation documented in the rules).
 *
 * ── CREDENTIALS (never hardcoded) ────────────────────────────────────────────
 * Set GOOGLE_APPLICATION_CREDENTIALS to the path of a service-account JSON key
 * with Firestore access to the project (healthbar-e055c). The key is read from
 * disk by the Admin SDK; nothing is embedded in this file.
 *
 * ── USAGE ────────────────────────────────────────────────────────────────────
 *   npm i firebase-admin                                   # once, if not present
 *   export GOOGLE_APPLICATION_CREDENTIALS=/abs/path/serviceAccount.json
 *   node scripts/backfill-member-count.js --dry-run        # review planned writes
 *   node scripts/backfill-member-count.js                  # apply
 *
 * Exits nonzero on any failure so operators / CI notice.
 */

'use strict';

const admin = require('firebase-admin');

const DRY_RUN = process.argv.includes('--dry-run');
const MAX_RETRIES = 5;

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  fail(
    'GOOGLE_APPLICATION_CREDENTIALS is not set. Point it at a service-account ' +
      'JSON key path with Firestore access, then re-run.'
  );
}

// applicationDefault() reads the key path from GOOGLE_APPLICATION_CREDENTIALS and
// derives the project id from the key — no credentials in source.
admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();

async function main() {
  console.log(
    `GUILD-CAP-1 memberCount backfill — ${DRY_RUN ? 'DRY RUN (no writes)' : 'LIVE'}`
  );

  const guildsSnap = await db.collection('guilds').get();
  console.log(`Found ${guildsSnap.size} guild(s).`);

  // BulkWriter batches + parallelises the writes and auto-retries transient
  // errors, so this scales regardless of guild volume.
  const writer = db.bulkWriter();
  let failures = 0;
  writer.onWriteError((err) => {
    if (err.failedAttempts < MAX_RETRIES) {
      return true; // bounded auto-retry on transient errors
    }
    console.error(
      `  write FAILED (gave up after ${err.failedAttempts}) for ` +
        `${err.documentRef.path}: ${err.message}`
    );
    failures += 1;
    return false;
  });

  let planned = 0;
  let unchanged = 0;

  for (const guildDoc of guildsSnap.docs) {
    const code = guildDoc.id;
    // Aggregate count — returns the roster size without reading the member docs.
    const countSnap = await guildDoc.ref.collection('members').count().get();
    const actual = countSnap.data().count;

    const current = guildDoc.get('memberCount');
    const currentStr = current === undefined ? '(absent)' : String(current);

    if (current === actual) {
      unchanged += 1;
      console.log(`  ${code}: memberCount already ${currentStr} — no change`);
      continue;
    }

    planned += 1;
    console.log(`  ${code}: memberCount ${currentStr} -> ${actual}`);
    if (!DRY_RUN) {
      // update (not set/merge): a concurrently-deleted guild fails cleanly here
      // rather than being resurrected as a malformed { memberCount }-only doc.
      writer.update(guildDoc.ref, { memberCount: actual });
    }
  }

  if (!DRY_RUN) {
    await writer.close(); // flush + await every buffered write
  }

  console.log(
    `${DRY_RUN ? 'Would update' : 'Updated'} ${planned} guild(s), ` +
      `${unchanged} already correct, ${failures} failure(s).`
  );

  if (failures > 0) {
    fail(`${failures} write(s) failed — the backfill is INCOMPLETE; re-run it.`);
  }
}

main().catch((err) => {
  fail(err && err.stack ? err.stack : String(err));
});
