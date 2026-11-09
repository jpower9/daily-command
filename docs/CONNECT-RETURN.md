# Connect flows: returning to the app

`plannerCalendarConnectStart` and `plannerRemindersConnectStart` only accept an **https** `returnTo`
on an allow-listed origin (`DD_RETURN_ORIGINS`, default `https://app.execclone.com`). The app therefore
uses `https://app.execclone.com/dc/connected` as its return page and opens Microsoft sign-in in
`ASWebAuthenticationSession(callback: .https(host: "app.execclone.com", path: "/dc/connected"))`.

For the session to close automatically, two things outside this repo are needed (tracked for the
first TestFlight build):

1. **execclone-apps/web:** a tiny `/dc/connected` page ("Connected — you can return to Daily Command")
   and the app's ID (`G53Y6B5LN4.com.execclone.dailycommand`) added to
   `/.well-known/apple-app-site-association` for that path.
2. **This app:** the `applinks:app.execclone.com` associated domain in `project.yml` once (1) is live.

Until then the flow still works: the user sees the web page and switches back to the app, which
refreshes on the next load.
