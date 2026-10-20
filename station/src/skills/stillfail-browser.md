---
name: stillfail-browser
description: Use the station's own Chrome for web work that needs a login or should look like a person's browser (sites, dashboards, consoles, anything behind a sign-in), and ask a person to sign in or solve a captcha in it.
---

# The station's browser

Each station keeps one real Google Chrome with its own persistent profile: whatever someone signs into there stays
signed in, for every session on the station. Get it with the `browser` tool (it starts it if needed) and drive it
with your own client:

- chrome-devtools-mcp: `npx -y chrome-devtools-mcp@latest --browserUrl http://127.0.0.1:<port>`
- Playwright: `chromium.connectOverCDP("http://127.0.0.1:<port>")`, then `browser.contexts()[0].newPage()` (the
  default context has the sign-ins; a new context has none).

Rules:

- Use it, not a Chrome or Chromium you launch yourself, for anything behind a login: a browser you start has none of
  the sign-ins, and sites often refuse to sign in an automated one.
- It is shared. Open a tab of your own and close it when done; leave other tabs alone; do not close the browser.
- `browser` with action `tabs` lists the tabs; `stop` closes it for everyone (only when it is stuck).
- It is closed after an hour unused and restarted if it dies while in use; call `browser` again when your
  connection drops (the address usually stays).

## Its tabs as screens (the `computer` tool)

The `computer` tool takes screenshots of a screen of the station and clicks, drags, scrolls, types and presses keys
on it, in the screenshot's pixels: a tab of this browser (`browser:<targetId>`, from `screen`) or the machine's display
(`desktop`). For web pages prefer DevTools (Playwright, chrome-devtools-mcp): they read and act on the page itself and
are faster and surer. Use `computer` for native apps on the desktop, and for what DevTools cannot reach (a browser
dialog, a canvas). A person watching sees you work; while one is driving the screen your input is refused, so wait or
ask them. When you are stuck, hand over as below.

## When a person is needed

A sign-in (password, 2FA, a code sent to their phone), a captcha or a consent that only a person may give: do not try
to get around it. Leave the page on that step, give the tab to a person with the `screen` tool (a link that opens the
tab in their still.fail app, where they see it and type into it), ask in the chat with need_human ("log in here",
"solve the captcha"), and end your turn. When they say it is done, carry on in the same tab: the sign-in is now in
the profile for later too.

Never ask for passwords or codes in the chat, and never type someone's credentials you were not given for that
purpose.
