# MATCH-1 — Targeted Matchmaking Verification Report

Run date: 2026-07-08. Build: c4797a5 (Debug, iPhone 17 Pro simulator). Bundle: com.vishnu.myapp.

## Step results

| # | Flow | Result | Evidence |
|---|------|--------|----------|
| 1 | Build/install/launch | PASS | build_run_sim SUCCEEDED, landed on login screen |
| 2 | Create Account C (matchtest.c.1783571354@healthbar.test, @matchc571354) + wizard | PASS | Signup, username claim, full wizard incl. AI plan generation completed; landed on Home |
| 3 | Sign out C, create Account D (matchtest.d.1783571354@healthbar.test, @matchd571354) + wizard | PASS | Same as above for D |
| 4 | D seeds queue (Battle → Find Match → 1-Day → Enter Queue), terminate app | PASS | "SEARCHING…" screenshot captured (0:13 elapsed at capture); app terminated via stop_app_sim at 21:56:57 |
| 5 | Relaunch, expect signed in as D, no stuck searching modal, sign out D | PASS | Relaunched cleanly to Home (mood-check prompt shown, unrelated, skipped); no stuck modal; signed out |
| 6 | Sign in as C | PASS | Typed credentials, no AutoFill dialog interruption on login (only occurs on signup/new-password fields), landed on Profile confirming @matchc571354 |
| 7 | C enqueues (Battle → Find Match → 1-Day → Enter Queue) | DEGRADED | Enqueued 21:59:43. Searched past 60s (screenshot at 1:31 still "Searching…", RR range auto-widened to ±100,000). No match, no error. Cancelled. |
| 7b | Re-seed (roles swapped): C enqueue → terminate → relaunch → sign out C → sign in D → D enqueue | FAIL-AMBIGUOUS | C re-seeded 22:01:50, terminated 22:02:13. D relaunched, signed out C, signed in D, enqueued 22:04:34. Searched past 60s (screenshot at 1:13 still "Searching…", RR range at ±100,000). No match, no error. Cancelled. |
| 8 | Verify both sides see duel | N/A (skipped) | No match occurred in either attempt, so there was no duel to verify on either account |
| 9 | Teardown: delete Account D | PASS | Danger Zone → password + DELETE → "Delete My Account" → returned cleanly to login screen |
| 10 | Teardown: delete Account C | PASS | Same flow, returned cleanly to login screen |
| 11 | Console/log grep for permission-denied and crashes | PASS | Zero matches for "missing or insufficient permissions" across all session logs. Zero matches for "fatal error\|EXC_BAD". |

## Timing

- **First attempt:** D's ticket entered the queue ≈21:56:05–21:56:13, terminated 21:56:57. C enqueued 21:59:43 — **≈3m38s** after D's ticket entry. No match after 60s+ of searching (RR range widened to ±100,000, indicating the client kept polling/searching with no candidate ticket found).
- **Re-seed attempt:** C's ticket entered the queue 22:01:50, terminated 22:02:13. D re-enqueued 22:04:34 — **≈2m44s** after C's ticket entry. Same outcome: no match after 60s+ of searching.
- Both attempts were well inside the ~10-minute TTL window described in the runbook, yet neither produced a match.

## Permission-denied lines

**None.** Grep across every runtime and oslog file captured during this session (`grep -in "missing or insufficient permissions"`) returned zero matches. Grep for `fatal error|EXC_BAD` also returned zero matches. The one non-trivial console line observed was benign: `Keyboard cannot present view controllers (attempted to present <UIKeyboardHiddenViewController_Save...>)`, a known iOS Simulator AutoFill/keyboard quirk unrelated to Firestore.

## Re-seed needed

Yes — the first attempt DEGRADED (no match after 60s), so a re-seed with roles swapped was performed per protocol. The re-seed also produced no match with zero permission-denied lines, which the runbook explicitly calls FAIL-AMBIGUOUS rather than a plain FAIL.

## Verdict

**The D2 queue-match (claim-by-update transaction) is NOT field-verified as working under the current F1 rules from this run — but the failure mode does not indict the rules.** In both attempts, the seeding account's ticket write succeeded (searching UI appeared normally, matching prior SMOKE-1 behavior), and the claiming account's search ran well past the expected ~15s match window with zero `Missing or insufficient permissions` lines anywhere in the console output. If the F1 M2 ticket-binding rules were rejecting the claim-by-update transaction, that would surface as a permission-denied error during the claiming account's search — none appeared, in either attempt. The complete absence of errors combined with the complete absence of a match points toward the ticket being unavailable to claim by the time the second account searched (most likely ticket cleanup/invalidation triggered by the seeding account's app termination-and-relaunch cycle, or by the intervening sign-out, rather than a rules rejection or true 10-minute TTL expiry, since both re-seed attempts failed well inside that window). This is the same open question the runbook flagged in advance: a design/lifecycle question about ticket persistence across process termination and sign-out, not a client-vs-rules permission conflict. It should be escalated for design review rather than treated as a rules bug to fix.

## Incidental finding (not a runbook deviation)

The signup flow's "Use Strong Password?" system AutoFill dialog is not exposed in the app's accessibility tree and cannot be dismissed via a direct tap on its own controls through UI automation. It reliably reappears on the first edit of a `.newPassword`-typed secure field each time the app process is freshly launched. The reliable workaround found empirically: submit the form once (triggering client-side validation, which resigns first responder on the password field and clears the dialog as a side effect), then immediately re-fill both password fields with `replaceExisting`, then submit again. This added several extra round-trips during Account D's signup but did not require any source/rules/config changes and did not affect the timed phase (all slow setup happened before the TTL clock started, per the runbook's own sequencing).
