---
name: stillfail-vault
description: Keep and use credentials through the person's still.fail vault (secret_save, secret_use, secret_run). Read it when a password, token, API key or SSH key turns up or is needed (an item read with op or bw, a token a person pastes, a key you created, one only the person has, a script that logs in somewhere): what to offer, how to keep it without seeing it, how to ask them to type one in, and what to do when their vault is not turned on.
---

# Credentials through the still.fail vault

The person's vault keeps their secrets encrypted to their own devices (in a workspace without security mode, in their
library on the station). You never see a value: you ask to keep one (`secret_save`), ask to use one (`secret_use`) and
run a command with it (`secret_run`). Each is approved by the person on a card in the still.fail app.

Whose vault: whoever started the chat, unless you name another with `person` (their email) on `secret_list`,
`secret_use` and `secret_save`: someone who wrote in this chat from the still.fail app. Name the one who asked for the
secret when that is not the starter, and always where the chat was started in Slack and the person now writes from
still.fail (a card for a Slack starter cannot be approved in the app).

## When to offer it

As soon as you see a credential will be needed more than once, before using it another way:

- you are about to read one with a password manager's CLI (`op`, `bw`), above all where each read needs the person
  (1Password's approval on a station's screen);
- a person pastes or tells you a token, password or key: keep it rather than leave it to be pasted again;
- you created one (a deploy token, an API key from a console you signed in to);
- a script you write logs in somewhere (a router, a dashboard, an API);
- you need one nobody gave you and you cannot read (an API key from a console only they sign in to): ask them to type it
  in on the card (below), not to add it in the vault page themselves or paste it in the chat.

Say it in a line (我把 UX7 的密码存进你的密钥库，以后用它在卡片上批准就行，不用再点 1Password) and call
`secret_save`: its card is the question, so ask nothing separately.

Not for what the station keeps itself: CLI logins (`login`, skill stillfail-login), the agents' model accounts (the
station's profiles), or anything the person said not to keep.

## Keeping one

- `secret_list` first: what is kept already (by name), and whether their vault is on. Do not keep a second copy.
- `secret_save {name, about, kind, reason, command | path | value | none, username?, filename?, modes?, hosts?, env?}`:
  - `command` prints the secret and nothing else; it runs here, in your workspace, and you never see what it prints:
    `op read 'op://Personal/Ui/password'`, `op item get <id> --fields password --reveal`, `bw get password <id>`. Its
    approval (1Password's) is asked once. Where the password manager is signed in on another station (1Password's
    desktop app on a Mac), give `station`: the command runs there, in this chat's directory (where station_task runs).
  - `path` for a file (kind `file`): kept as it is, its bytes; `station` reads it there.
  - `value` only for one you already hold (a token you made or were given).
  - None of these, for one you do not have: the card has a field the person types or pastes it in (a login's account
    too, when you give no `username`; a file, a button that picks it), kept as they approve it and never shown to you. Say in `reason` where they get it
    (OpenCode 控制台 → API Keys), and give `hosts` and `env` as for any.
  - `kind`: `token` (an API key, a bearer token), `login` (a password, with `username`), `ssh_key` (a private key, with
    `public_key` if known), `file` (a credential that is a whole file, at most 64 KB: a kubeconfig, a service account's
    JSON key, a `.p12` certificate, a `.env`).
  - How agents get it later: `proxy` with `hosts` for an HTTP API that takes it in a header (`Authorization: Bearer`,
    `X-Api-Key`): the command only holds a placeholder. `env` (with `env`, the variable's name) for anything else: a
    password sent in a login form or JSON body, a database client, a CLI reading a variable. `ssh` for an SSH key.
    `file` for a file: each command gets it written out where only it reads it, removed when it ends, its path in
    `env` (`KUBECONFIG`, `GOOGLE_APPLICATION_CREDENTIALS`) and `$STILLFAIL_SECRET`.
  - `name`: what a person and the next agent know at a glance: the service and the account or site, and where it is
    reached when that is not plain (测试服务 admin 登录, GitHub deploy token · AFK-surf/still.fail, UniFi 后台登录态（经
    Studio 转发到 127.0.0.1:8443）). Never a bare host (`127.0.0.1 登录态`): nobody knows what it was.
  - `about` (required): what it is for and how it is used, in the person's language: what it opens, the steps to reach it
    (a forward from which station, a tunnel, the page to open), the tool or command that takes it. `secret_list` shows
    it to every agent after you beside the name; never a secret in it.
- It does not wait for the person: you are told in your session when they decide. Meanwhile go on with what does not
  need it (answer the chat, other work); with nothing else left, end your turn need_human about the card. Only their
  approval in the app keeps it: a yes written in the chat does not.
- A later chat message closes the card, but does not decide the request. If it is still needed, call
  `secret_reask {request}` with its original request id: the same request gets a new card, without reading or capturing
  the secret again. It will not replace another pending card.
- Their vault not turned on (secret_list says so: security mode is on, but no device of theirs has it set up): call
  `secret_save` anyway. The card says so and offers 开启密钥库 in the app; once they turn it on, it keeps the secret.
  Tell them in a line that turning it on takes a minute and shows recovery words to write down once.
- No security mode in the workspace: it is kept in their library on this station, unencrypted (the card says where).

## Renaming one

An item whose name or about does not say what it is or how it is used (a name made of a host, a step written nowhere):
`secret_describe {item, name?, about?, reason}`. A card shows its owner the name and about as they are and as they
would be; approved in the app, the item says so. Do it as soon as you worked out what an item is, so the next agent
does not have to.

## Deleting one, and taking back a request

- An item that is wrong (a password that does not work), replaced by one you kept, or no longer needed:
  `secret_delete {item, reason}`. A card asks its owner; approved in the app, the item is gone for every chat. Do not
  rename a wrong item instead of asking to delete it.
- A request of this chat's own that is no longer needed (you got the credential another way, the person chose another
  account, you asked twice): `secret_cancel {request}`. Its card closes saying so and it leaves the person's waiting
  requests in 密钥. Telling them in the chat that a card is not needed leaves it waiting there.

## Using one

- `secret_use {item, reason, command, mode?, hosts?}` puts a card in the chat; the person picks how long the grant
  lasts (one command, an hour, this chat until it is archived). Say all you will run with it, so one grant covers it.
- `secret_run {grant, command, env?}` runs the command here: through the proxy (the placeholder in `$STILLFAIL_SECRET`
  and the item's variable, swapped on HTTPS to its hosts only), by ssh-agent, with the value in the environment, or
  with the file written out for it, its path in the variable (the output comes back with the value hidden). Never print, encode or send the value elsewhere.
  A login's account is not secret: the grant and `secret_list` say it, and every command gets it in `$STILLFAIL_USERNAME`.
- What only another station reaches (a router on its network, a tool signed in there): `secret_use {…, station}`, and
  the card says where; `secret_run` then runs each command there, in this chat's directory on that station (where
  station_task runs), the value sent there for that command only. Never copy a value to another machine yourself.
- A script that logs in keeps the session it gets (a cookie, a token) between runs, in a file only its owner reads,
  and logs in again only when that is refused: every login costs the person an approval, and a second factor sent by
  email or SMS cannot be kept.
