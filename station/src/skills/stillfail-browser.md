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

## Sign-ins: one call, `sign_in`

To be signed in to a site in this chat's browser, open its sign-in page here and call `sign_in {site, reason}`. It
is the one way to ask:

- The vault keeps a sign-in for the site (kind `browser`: its cookies, and its passkeys): it is asked for, as
  `secret_use` does (a card the person approves); granted, it is put into this chat's browser for as long as the grant
  lasts, then taken out again (the site's newer cookies kept in the vault). You never get the cookies.
- None kept: a card asks the person to sign in. Their app fills the page from their own password manager (1Password,
  the system's autofill) and the station types it in, step by step (account, password, one-time code), and sends it;
  where only they can go on (a captcha, a code sent by mail), the card gives them the tab's screen. You never see what
  they typed. You are told in your session when the page has left its sign-in: look whether it is signed in, then call
  `sign_in {site, done: true}` (it is kept in their vault if they chose so on the card, with no other card; other chats
  then ask for it instead of signing in again), or `sign_in {site, stuck: "what is left"}` in their language.
- It does not wait: go on with what does not need it, else end your turn need_human (about the card). Do not post the
  tab's screen for a sign-in yourself, and never ask for a password or a code in the chat.
- The vault's sign-in ran out (the site asks you to sign in although it was granted): sign in with the site's passkey if
  it offers one (below: the browser signs it), else `sign_in {site, again: true}`.
- Passkeys: each tab of this chat's environment has an authenticator of the browser's own, so a site's "add a passkey"
  (on its account or security page) makes one here with no prompt, and a site asking for one it has signs with it. Once
  signed in to a site that takes passkeys, add one there (a second passkey beside the person's own; most sites take
  several; the site may ask for the password again: call `sign_in {site}` again on that page and it is typed in
  again) before `done`: the sign-in kept carries
  it, and when its cookies run out later, its passkey signs in again with nobody asked.
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

A captcha or a consent that only a person may give (a sign-in: `sign_in`, above): do not try to get around it. Leave
the page on that step, give the tab to a person with the `screen` tool (a link that opens the tab in their still.fail
app, where they see it and type into it), ask in the chat with need_human ("solve the captcha"), and end your turn.
When they say it is done, carry on in the same tab.

Never ask for passwords or codes in the chat, and never type someone's credentials you were not given for that
purpose.
