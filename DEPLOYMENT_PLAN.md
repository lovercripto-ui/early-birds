# Activation status — owner authorized

Owner explicitly authorized proceeding after the reviewed scope and rollback were presented. The previously rejected migration was retried only after that authorization.

- `phone_pwa_gateway_v1`: applied successfully.
- `early-birds-phone-users`: ACTIVE, version 1, JWT verification enabled.
- Pre-change public-data/function/policy snapshot: saved privately; never committed to GitHub.
- Existing data in all 14 public tables compared after tests: unchanged (excluding the two new default-valued profile fields).
- 11 hosted role-simulated transaction checks passed and rolled back; private audit fixture rows remaining: 0.
- GitHub repository access now works. Release status and commit are recorded under evidence.

The original review plan below is retained as historical scope documentation. Statements that approval/access was pending describe the earlier preparation phase.

---

# Reviewable activation plan

## Target and current state

- Static site: `lovercripto-ui/early-birds`, existing `main` HEAD inspected at `c18bc8aea2f201bb032ce98e8449037a231ece79`.
- Existing Supabase project: `stwnvhgocwgwwprmypmv`, organization Early Birds, verified Free plan.
- No new project, paid branch, billing change, GitHub Actions workflow, hosted SQL change or live Edge Function deployment has been completed.
- Read-only verification confirmed `phone_state` and `profiles.phone_active` are not installed.
- Branch creation was attempted and failed with GitHub integration HTTP 403. No repository file/branch was modified.
- An attempt to apply the live backend migration was rejected by automatic approval review because it changes an existing database's schema, permissions/RLS and financial operations without sufficiently explicit scope authorization and rollback evidence. It was not applied and was not bypassed.

## Exact backend change requiring owner approval

| Change | Purpose / impact |
|---|---|
| Add `profiles.phone_active` and `phone_must_change`, defaulting to existing access | Account status and temporary-password enforcement; existing profile rows retained |
| Add private `eb_phone` schema, metadata, replay, cash, reversal, handover and audit tables | Durable transaction handling and history without deleting old rows |
| Add a restrictive active-session layer to 13 existing table policies | Existing ownership rules remain; inactive/reset phone sessions additionally fail closed |
| Update `assigned_to(uuid)`, `is_admin()` and receipt-confirmation guards | Permanent/temporary Supervisor replacement affects project access; inactive/reset sessions are checked by existing transaction RPCs too |
| Add authenticated `phone_state` / `phone_action` wrappers | Scoped reads and atomic approved-only cash, stock, daily, attendance and handover operations |
| Add service-only credential invalidation stamp | Previously issued phone tokens stop working after reset/change |
| Deploy new `early-birds-phone-users` Edge Function from phone-users.ts | Admin creates/resets Supervisor accounts; own-password change verifies current password; no secret is sent to the browser |

The gateway reuses the existing projects, assignments, money requests, transfers, expenses, inventory, movements, daily updates and checkins. Request approval still creates a pending transfer through the existing approved-request RPC. Balance counts received transfers and approved expenses only. Extra cash moves and reversals are retained separately and included by the new phone gateway.

## Activation sequence, only after approval

1. Retain a provider/database backup plus private media export; record existing function/policy definitions. `rollback.sql` already contains the exact inspected previous assignment, Admin and receipt guards and removes only the added restrictive policy layer.
2. Apply the reviewed `backend/phone.sql` once using migration name `phone_pwa_gateway_v1`.
3. Check grants/RLS/advisors and run hosted read-only and transaction-with-rollback smoke checks. No real financial fixture should be committed.
4. Deploy `early-birds-phone-users` with JWT verification enabled and platform-provided service credentials kept server-side.
5. Run an owner login smoke test. The assistant cannot do this without the owner's authenticated account; do not send passwords into chat.
6. With repository write access, commit static deploy contents on a separate review branch, then publish only after reviewing the complete diff. No workflow file is added.
7. Verify the actual HTTPS Pages URL, installed app launch, a Supervisor's assigned-project scope, receipt access, GPS, queue sync and a reversible sandbox transaction.

## Rollback boundaries

- Restore the previous frontend from the inspected commit or the included local rollback copy.
- Run `backend/rollback.sql` to restore the original assignment/Admin/receipt guards, remove the added restrictive policy layer and revoke phone gateway access.
- Do not drop the new private schema or delete records. Confirmed handovers, cash moves, reversal history and credential changes are business events and are NOT automatically undone by a frontend rollback.
- Before resuming an old client after new phone transactions, reconcile private cash/reversal records with its older reporting logic. Do not assume the old balance view understands new extensions.
- Existing passwords changed through Auth are not recoverable from an export. Use a proper reset/recovery procedure.

## Remaining user actions / constraints

Explicit approval is needed for the reviewed hosted backend changes. GitHub integration write access is needed for this exact repository. Google OAuth consent and real Android/iPhone checks require the owner. The package is a tested candidate, not an already-published or 100%-verified production service.
