# Handoff brief
## Goal
Fix invoice totals that are off by one cent when a discount applies.
## Done (verified)
- Root cause found: line totals rounded before the discount (`invoice/totals.js:42`).
- Fix and a regression test pushed; PR #128 open, CI green.
## In flight
Applying the same fix to credit notes (`credit/totals.js`), uncommitted.
## Decisions and constraints
- "Round once, at the end" — no per-line rounding.
## Tried and rejected
- Switching to `toFixed(2)` per line: still off by a cent on 3-item invoices (test `discount-3-lines` fails).
## Next step
Finish `credit/totals.js`, run `npm test`, push to PR #128.
