---
name: stillfail-browser
description: Use the station's own Chrome (this chat's own environment in it) for web work that needs a login or should look like a person's browser (sites, dashboards, consoles, anything behind a sign-in), ask a person to sign in or solve a captcha in it, and keep and reuse sign-ins through the vault.
---

# The station's browser

Each station keeps one real Google Chrome, with no window on the machine, and in it an environment of this chat's own:
its tabs, cookies and storage are this chat's alone, kept in memory only, and gone when the chat is archived. No other
chat sees them, and you see nothing of another chat's. Get it with the `browser` tool (it starts it if needed): it
gives this chat's address of it, `ws://127.0.0.1:<port>/browser/<…>`. Drive it there with your own client:

- chrome-devtools-mcp: `npx -y chrome-devtools-mcp@latest --wsEndpoint <that address>`
- Playwright: `chromium.connectOverCDP("<that address>")`, then `browser.contexts()[0].newPage()` (the default
  context is this chat's environment).

Through that address you reach this chat's environment only: what touches another chat's tabs or the browser as a
whole (closing it, a session of the browser's own) is refused. People see this chat's tabs in their app, and may
close them there.

Rules:

- Use it, not a Chrome or Chromium you launch yourself, for anything behind a login: sites often refuse to sign in an
  automated one, and the vault's sign-ins go only into this one.
- Close the tabs you are done with.
- `browser` with action `tabs` lists this chat's tabs; `stop` closes this chat's environment (its tabs and the
  cookies in it; sign-ins still granted go in again when you next ask).
- When your connection drops (the browser was restarted, the station restarted), connect again to the same address.
  A browser restarted gives this chat a new environment: sign-ins made in it by hand are gone, sign-ins still granted
  from the vault go in again.

## Sign-ins: kept in the vault, given by grant

What this chat is signed in to comes from the vault, the person's, as a sign-in (kind `browser`: the cookies of the
sites it is for):

- `secret_list` lists the sign-ins you may ask for; `secret_use {item, reason}` (its mode `browser`) asks for one. Once
  granted, its cookies are in this chat's environment for as long as the grant lasts, then taken out again (the
  site's newer cookies kept in the vault). Nothing is run with secret_run; you never get the cookies.
- None there yet: have the person sign in here (below); once they did, offer to keep it: `secret_save {name, kind:
  "browser", hosts: [the sites, e.g. "github.com"], reason}` reads the cookies from this chat's environment (never
  shown to you), and its card asks them to keep it. Other chats then ask for it instead of signing in again.
- A sign-in made before each chat had its own environment is still in the station's own profile: `secret_save {…,
  kind: "browser", browser: "station"}` reads it from there.

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
"solve the captcha"), and end your turn. When they say it is done, carry on in the same tab; then offer to keep the
sign-in (above), so it outlives this chat.

Never ask for passwords or codes in the chat, and never type someone's credentials you were not given for that
purpose.
