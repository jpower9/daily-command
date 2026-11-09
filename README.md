# Daily Command by ExecClone

The standalone planner app: Day · Week · Quarter · Goals · Journal. Anyone can sign up with an
email; the same planner is also a section of Executive OS for ExecClone clients, and the two
share one backend, so an account that later becomes an ExecClone client keeps everything.

- `ios/` — the iPhone/iPad app (SwiftUI, iOS 18, Swift 6).
  - `ios/DailyCommandKit` — `DailyCommandCore`: the API client, sign-in, Keychain session,
    models, date/phase math, task parsing, the quarter scorecard and the journal encryption.
    Pure Swift, tested with `swift test` on a Mac.
  - `ios/App` — the SwiftUI app. Generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
    from `ios/project.yml`.
- `docs/` — how the pieces connect (see `docs/ARCHITECTURE.md`, `docs/CONNECT-RETURN.md`).
- `DECISIONS.md` — product decisions for this app; platform decisions live in the ExecClone
  canon (`jpower9/clawd`, `canon/DECISIONS.md`, D-019/D-020).

## Backend

Every data call is one `POST` to ExecClone's client API (`mobile-bootstrap`, the `planner*`
actions in `execclone-apps/contract/client-api.md` §22), authorized by the signed-in user's token.
The app never reads a database table directly and holds no keys beyond the user's own session.

| Need | Where it is |
|---|---|
| Planner actions, schema, RLS | `jpower9/clawd` — `supabase/migrations/2026110918*`, `supabase/functions/mobile-bootstrap/planner-actions.ts` |
| Calendar (Microsoft 365) and Apple Reminders sync | `jpower9/clawd` — `supabase/functions/dd-calendar`, `dd-reminders` |
| Self-signup (`dc-auth/start`) | `jpower9/clawd` — pending, D-020 |
| Web version (Executive OS) | `jpower9/execclone-apps` — `web/src/components/planner` |

## Build locally

```sh
brew install xcodegen
cd ios
cp Config/Local.xcconfig.example Config/Local.xcconfig   # fill in the publishable key
xcodegen generate
open DailyCommand.xcodeproj
```

Tests: `cd ios/DailyCommandKit && swift test`. CI runs the same on every push (`.github/workflows/ios.yml`),
builds the app for the simulator, and fails if any runtime or staff name shows up in a client surface.

## TestFlight

Actions → **TestFlight** → Run workflow (from `main`). It archives on a GitHub Mac with the team's App Store
Connect API key and uploads; the build number is the run number. One-time repo settings: secrets `ASC_KEY_P8`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`; variable `DC_SUPABASE_PUBLISHABLE_KEY`. The same `ios/scripts/release.sh`
runs from a Mac in Terminal.

## Journal encryption

Locked notebooks are encrypted on the device: PBKDF2-HMAC-SHA256 (310,000 iterations, 16-byte salt)
derives an AES-256-GCM key from the passphrase; entries are stored as `enc:v1:<nonce>:<ciphertext>`.
The same format as the web app, so a notebook opens on both. The server never sees the passphrase
or the key; a forgotten passphrase cannot be recovered by anyone.
