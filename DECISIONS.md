# Daily Command decisions

App-level decisions. Platform decisions are in `jpower9/clawd` `canon/DECISIONS.md` (D-019, D-020).

| # | Date | Decision | Why |
|---|---|---|---|
| DC-001 | 2026-11-09 | Standalone app named **Daily Command**, brand line "by ExecClone", bundle `com.execclone.dailycommand`, same Apple team as ExecClone. | Joseph: a standalone for people who may become ExecClone clients, with the option to use it inside ExecClone or on its own. Funnel/upgrade wiring is deferred until the ExecClone iPhone app clears App Review. |
| DC-002 | 2026-11-09 | One backend: the app calls the same `planner*` actions as Executive OS; no separate schema or functions. | No second system to migrate; a user who later joins ExecClone keeps their data. |
| DC-003 | 2026-11-09 | Self-signup by email code via a dedicated `dc-auth/start` function; the Supabase project keeps public signups off. | ExecClone client accounts stay team-provisioned (fail closed); planner-only users are marked server-side as a role. |
| DC-004 | 2026-11-09 | Shared `DailyCommandKit` package; UI in SwiftUI; XcodeGen project; no local Swift toolchain assumed (CI on macOS runners is the build of record until a Mac is wired in). | Mirrors `execclone-ios` so the same code can later become a tab in the ExecClone app. |
| DC-005 | 2026-11-09 | Entries are edited as plain text on the phone and stored as simple `<p>` HTML. | The web app stores sanitized HTML; this keeps entries readable on both without a rich-text editor on day one. |
| DC-006 | 2026-11-09 | Search covers tasks, calendar, daily notes and the planning records (weeks, rocks, quarters, goals). Journals and notebooks are never searched. Daily notes live on the Day tab as `dd_days.notes`. | Joseph: "journal entries aren't searchable, just daily notes (not notebook), tasks, and calendar, stuff related to daily weekly monthly annual stuff." |
