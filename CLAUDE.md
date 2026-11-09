# daily-command: notes for coding agents

This is an ExecClone product repo. Before changing anything, load and follow the ExecClone canon and
the Engineering Mandate. Their source is `jpower9/clawd` on branch `feat/continuity-auto-delegation`:
`EXEC-CLONE-CANON.md`, `EXEC-CLONE-PRODUCT-CONSTITUTION.md`, `ENGINEERING-MANDATE.md`. Read-only mirrors:

@~/execclone-ops/CANON.md
@~/.claude/execclone/CANON.md

- **Authority:** Joseph is final authority. Code and old notes never override the canon. Raise conflicts
  before continuing.
- **Branch:** `main` is canonical. Work on `claude/*` branches, open small draft PRs into `main`, merge
  only what Joseph names in chat. Joseph does no git work; agents handle branches, commits, pushes, PRs,
  failing checks and review replies.
- **Decisions:** this app exists under canon D-019 (Daily Command) and D-020 (self-signup). App-level
  decisions go in `DECISIONS.md` here; anything touching the platform goes in clawd's `canon/DECISIONS.md`.

## What this repo is
The standalone Daily Command app (iPhone/iPad). It is the public-facing version of the planner that
ExecClone clients get inside Executive OS (`jpower9/execclone-apps`), on the same backend.

## Rules specific to this app
- **Client surface language:** no runtime, vendor or staff names anywhere a user can see (CI brand check).
  Daily Command never mentions clones; it is a planner. "by ExecClone" is the only brand line.
- **Every data call goes through the client API** (`mobile-bootstrap` `planner*` actions). Never talk to a
  database table or storage bucket directly. New actions are added to the contract in `execclone-apps`
  and implemented in `clawd` first, then used here.
- **No keys in source.** The publishable key comes from `ios/Config/Local.xcconfig` (gitignored) or CI.
  The session lives in the Keychain, not synced, not backed up to other devices.
- **Journal crypto is a contract.** `JournalCrypto` must stay byte-compatible with the web app
  (`execclone-apps/contract/parity-spec.md` §22). Any change is a cross-app decision.
- **Credentials never rest on the phone.** Microsoft sign-in happens in Microsoft's page; the Apple
  app-specific password is posted once to the server's one-time URL and dropped.

## Build and test
`cd ios/DailyCommandKit && swift test` (macOS). `cd ios && xcodegen generate` then build the
`DailyCommand` scheme. CI: `.github/workflows/ios.yml`.
