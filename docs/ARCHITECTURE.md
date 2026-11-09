# How Daily Command fits together

```
iPhone app (this repo)        Executive OS web (execclone-apps/web)
        │                                 │
        └──────── POST /functions/v1/mobile-bootstrap { action: planner* } ────────┐
                                                                                    ▼
                                   ExecClone client API (clawd) — authorizes the caller,
                                   scopes every row to that user, audits each call
                                                                                    │
                        dd_* tables (RLS) ◄──────────────┬──────────────► dd-calendar (Microsoft 365)
                                                         └──────────────► dd-reminders (Apple CalDAV)
```

- **Identity:** Supabase Auth email codes. Planner-only users are created by `dc-auth/start` and marked
  server-side; ExecClone client accounts are provisioned by the team. One `auth.users` row either way,
  so becoming a client later changes a role, not an account.
- **Session:** access + refresh token in the Keychain (`KeychainSessionStore`, this-device-only).
  `TokenRefresher` serializes refreshes; a refused refresh signs out, an outage does not.
- **Data:** `PlannerAPI` → `planner*` actions. Payloads are read through `JSON` into the models in
  `Models.swift`; dates are `yyyy-MM-dd` strings in the user's zone (the server tells us `today`).
- **Journal:** `JournalCrypto` (CryptoKit + CommonCrypto PBKDF2). Keys in memory; dropped on background
  and after 15 idle minutes.
- **Connections:** calendar connect opens a one-time server URL in `ASWebAuthenticationSession` and returns
  via a universal link (see `CONNECT-RETURN.md`); Reminders posts the app-specific password once to the
  server's one-time URL.
