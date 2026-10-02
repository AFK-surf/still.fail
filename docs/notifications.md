# Notifications

A person hears about a chat they take part in when something there wants them:
an agent finished a turn with something new to read, an agent is blocked on
them, an agent failed, or another person said something. Two ways carry it:

- **Local**, while a client runs: the client core notices it from the chat
  rows it keeps in sync anyway (`notices` topic) and the client shows it. The
  desktop app shows them from its main process (so also with no window open),
  the web page from the page, Android from its app process while the app is in
  front.
- **Push**, while no client runs: the station tells still.fail cloud, which
  pushes to the person's registered devices — Web Push (VAPID) for browsers,
  Firebase Cloud Messaging for Android. The desktop app has no push; it keeps
  running in the background on macOS and hears them locally.

A notice is never shown for the chat the person is looking at, and one chat
has one notification at a time (its `tag`: a newer one replaces the older).
Both ways use the same tag, so a push and a local notice for the same chat do
not pile up; besides, a web page that is open (it shows local ones) makes the
service worker drop pushes, and Android shows pushes only while the app is not
in front.

Only chats of still.fail's own page are noticed (a Slack thread has Slack's
notifications), and only for people who take part in them (the sidebar's
`mine`: they made the chat, spoke in it, or started it).

## What is noticed

| kind | when | body |
| --- | --- | --- |
| `done` | an agent's turn ended (not blocked, not failed) and it said something in the chat during the turn that the person has not read | `<agent>: <its last message>` |
| `block` | an agent's turn ended blocked (`chat_post kind:"block"` / `chat_state block`) | `需要处理 · <its last message>` |
| `failed` | something went wrong: the station says so in the chat, `⚠️` first (a turn that failed, an agent that could not start) | `出错了 · <what it says>` |
| `message` | another person said something in the chat, while no agent there is at work | `<name>: <text>` |

The title is the chat's title as the sidebar shows it. Texts are one line
(whitespace collapsed), cut to 140 characters. A notification opens the chat:
`/o/<workspace>/<station>/<session>` (the link every client already opens).

## Client core: the `notices` topic

`notices` (`workspace?`) is kept by the core (`notices.rs`, fed by what `sync.rs`
keeps: every station's `chatRows`), each workspace's apart: with a `workspace`,
that workspace's (the last 20), with none every workspace's. Its value:

```jsonc
{ "items": [{
  "id": "n7",                      // unique while the core runs; new ones have ids not seen before
  "kind": "done",                  // done | block | failed | message
  "station": "ws/st", "workspace": "ws", "stationId": "st",
  "session": "<row id>", "thread": 7,
  "title": "部署挂了", "body": "Claude: 修好了",
  "tag": "ws/st/<row id>",
  "url": "/o/ws/st/<row id, URI-encoded>",
  "at": 1790000000000
}] }                               // oldest first, the last 20
```

A client takes the items it has not seen; the ones in the first value it gets
are old news (shown by nobody). From a row's changes, `notices` adds one when a
row that is `mine`:

- becomes `block` (its state was not `block`);
- gets a new last message from the station starting with `⚠️` (`failed`);
- is `unread` with a last message it had not noticed yet (a higher `last.seq`)
  that is not the viewer's own, and no agent of it is at work (`run`): `done`
  when the last message is an agent's, `message` when it is a person's.

The first rows of a station are where it starts from (nothing is noticed for
them); a row seen again after its station's link came back is compared with
how it was.

Calls:

| Call | Params | Result |
| --- | --- | --- |
| `push.key` | — | `{ vapid }`: still.fail cloud's VAPID public key (base64url), to subscribe a browser |
| `push.register` | `{ kind: "web", endpoint, keys: { p256dh, auth } }` or `{ kind: "fcm", token }` | — ; registers this device with every signed-in account, and again with each account signed in later (kept in storage) |
| `push.unregister` | — | — ; takes this device's registration off every account |
| `notify.set` | `on?`, `asked?` | the `notify` value; kept on the device. Off also takes this device's registration off every account, and `push.register` does nothing while off |
| `client.focus` | `visible?`, `focused?`, `chat?` (`{ station, thread?, session?, end? }` or null), `left?` (a chat), `workspace?` | — ; where this UI's attention is (each field given changes; `left`: that chat is not shown any more, if it is the one; `workspace`: the one it is in, else its chat's) |
| `notice.claim` | `id` | `{ show }`: true for the first page that takes a notice of `notify.show` |
| `notice.pushed` | `workspace?` | `{ show }`: whether a push that came is shown (on, no page in view, and of the workspace the viewer is in) |

`notify` (no params, attend.rs) is what the clients show from: `{ on, asked, push, show }`. `on` and `asked` (the
system asked to allow them, once) are kept on the device, on by default. `push`: this device should hold a push
registration. `show`: the notices to show now, decided as they come: none while off; none for a chat a UI is looking at
(`client.focus`: `visible`, `focused`, that chat); none while this device has pushes and no page is in view (the push
says it); only while some UI subscribes (what came before is old news); only of the workspace the viewer is in. That is
the workspace of the UIs in view (as each said with `client.focus {workspace}`, else its chat's), or with none in view
of every UI (a phone's app in the background is still in its workspace); with no UI saying (none open, or ones from
before they said), none is left out. `notify {workspace}` shows a page in a workspace only its own. A page takes each
with `notice.claim`, so it is shown once however many pages are open; one not taken goes after 30 s.

## still.fail cloud

- `GET /v1/push/key` → `{ vapid }` (no auth).
- `POST /v1/push` (bearer access token) `{ kind: "web", endpoint, keys: { p256dh, auth } }` or `{ kind: "fcm", token }` → 204. One row per account and endpoint/token: a device signed in with several accounts has one for each (registered again with the same account, it moves to this session). A device that two of a notice's people are signed in with gets it once.
- `DELETE /v1/push` (bearer) `{ endpoint }` or `{ token }` → 204; only the caller's account's row goes.
- A session signed out (`/v1/auth/logout`, revoked) takes its registrations with it.
- `POST /v1/stations/notify`, signed by the station like its traces: headers
  `x-stillfail-station`, `x-stillfail-ts`, `x-stillfail-signature` = ed25519
  over `ember-station-notify-v1:<origin>:<station>:<ts>:<sha256 of the body, hex>`.
  Body:

  ```jsonc
  { "notices": [{
    "to": ["a@b.c"],               // people's emails; only members of the station's workspace get it
    "kind": "done", "session": "<key>", "thread": 7,
    "title": "部署挂了", "by": "Claude", "text": "修好了", "at": 1790000000000
  }] }
  ```

  → `{ "sent": n }`. The cloud makes the body as the table above says, and
  pushes to each mstill.fail's registrations. A device its push service answers
  404/410 (gone) for is dropped, with every account it was registered with.

Push payload (Web Push: the encrypted body, `aes128gcm`; FCM: a data message,
high priority, every value a string):

```jsonc
{ "type": "notice", "kind": "done", "title": "…", "body": "…",
  "tag": "ws/st/<session>", "url": "/o/ws/st/<session>",
  "workspace": "ws", "station": "st", "session": "<key>", "at": "1790000000000" }
```

Secrets: `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` (P-256, base64url raw
public point / private scalar `d`), `VAPID_SUBJECT` (a `mailto:`);
`FCM_SERVICE_ACCOUNT` (the Firebase service account's JSON). Without VAPID keys
`/v1/push/key` answers 404 and web registrations are refused; without the
service account FCM pushes are skipped.

## Station

The station notices at the two moments that matter (mesh/app `notify.rs`):
an agent's turn ending (`Session::on_turn_ended`), and a message in one of
its own chats: a person's, or the station's own ⚠️. It sends the notices to the station process
(mesh/station), which posts them to still.fail cloud, batched over a second;
one that cannot be sent is dropped. A station not enrolled with still.fail
cloud sends nothing. An older cloud answers 404, and nothing more comes of it.

## Clients

- Web: a service worker (`/sw.js`) shows pushes when no page of the app is
  open, and opens (or focuses) the app on the notification's `url`. The page
  shows the local notices the core's `notify` says to show (it tells the core
  which chat it shows and whether it is in view and has focus). 设置 → 通知
  turns them on (asking the browser's permission) and off, kept by the core.
- Desktop: the main process holds the core's `notify` (claiming each, as a
  page would) and shows Electron notifications, so they are of the workspace
  its windows are in; clicking one opens the chat as a `stillfail://o/…` link would. Pages show
  none themselves. The setting is the same page.
- Android: `POST_NOTIFICATIONS` is asked for; one channel (消息); local notices
  while the app is in front (not for the open chat; the core's `notify`), FCM
  pushes while it is not (`notice.pushed`). The token is registered with
  `push.register`. Tapping either kind opens the notification’s workspace on
  the decisions page (奏), with Back returning to its chat list. Ordinary chat
  links still open their chat. 我 → 通知 turns them off, kept by the core.
