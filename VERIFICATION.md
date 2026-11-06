# Verification — activated phone build

2026-11-06, Asia/Colombo.

## Completed

- Original candidate archive SHA256 verified: `89cc7769aac26c833bf86f2cf97687d1f2132fd6c3e237e7513c11fb1b8483f8`. All archived manifest entries matched before activation.
- Owner authorized the reviewed backend changes. Existing organization rechecked as Free and project ACTIVE_HEALTHY.
- Private pre-change snapshot of all 14 public tables plus function/policy definitions saved before migration; no Auth password was exported or reset.
- `phone_pwa_gateway_v1` successfully applied on hosted Postgres 17. Seven private tables have RLS; anonymous phone RPC execution denied; service credential-stamp function inaccessible to normal authenticated users; all 13 restrictive active-session policies verified.
- Account function `early-birds-phone-users` deployed ACTIVE, version 1, with platform JWT verification enabled. Actual unauthenticated POST returned 401; actual CORS preflight returned 200 with the expected Pages origin.
- **11 hosted role-simulated transaction checks passed**: assignment scope, Supervisor/Admin denial, approval does not credit cash, confirmed receipt, pending/approved bill treatment with exact cents, reversal, negative quantity rejection, stock issue, duplicate approval rejection and damaged-return conservation. Every test record was rolled back. Private audit test rows remaining: 0.
- All pre-existing data in **14 public tables compared before/after: unchanged**, excluding the two newly added profile fields at their defaults. Table data snapshots are private and never uploaded to the repository.
- **29 local Postgres cases**, **48 Chromium browser checks**, **13 mocked account-handler cases** pass. Browser tests cover desktop, Android-sized and iPhone-sized layouts, the actual pinned SDK, mocked login/data responses, real subpath service-worker install, owner-scoped offline queue, old-schema detection and legacy export. The export test confirms old password hashes are excluded and source localStorage is untouched.
- Internal mobile visual review completed, Sinhala font packaged locally. Runtime syntax checks passed. Node/Python are not required to run the hosted app.

## Still requires the owner

- Actual owner/Supervisor sign-in and two physical devices. Database role simulation and mocked browser authentication are not real user login tests. No existing password was requested, recovered or changed by the assistant.
- Actual iPhone Safari/Android Chrome installation, launch, GPS permissions/accuracy and photo upload. Chromium viewport emulation is not physical-device testing.
- Google OAuth Client ID, consent and actual Drive upload/download. Drive remains optional and is not yet configured.
- Cloud recovery drills and import review for old local/Firebase data. A private export prompt preserves access to old browser records; they are not silently imported or deleted.

## Security review notes

Only the publishable key is in static config. Runtime Auth and financial/media responses are excluded from the service-worker cache. Private tables intentionally have no public client table grants/policies; authenticated gateway functions perform explicit role/ownership checks. Public wrappers use SECURITY INVOKER, privileged helpers stay in a private schema and use an empty search_path. Password fields are stripped from business replay/audit payloads.

Advisors were checked after deployment. Private no-policy INFO findings are intentional fail-closed tables. Existing exposed trigger-function EXECUTE notices and the existing leaked-password-protection setting were present before this change; no paid setting was enabled. Review references:
- https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

See evidence/deployment-status.txt for repository commit and observed public-page status. A frontend rollback does not undo already-confirmed cash moves, handovers, reversals or changed Auth credentials; reconcile before resuming an old client.
