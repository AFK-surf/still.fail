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
  Firebase Cloud Messaging for Android, APNs for iOS. The desktop app has no
  push; it keeps running in the background on macOS and hears them locally.

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
| `block` | an agent's turn ended blocked (`chat_post kind:"block"` / `chat_state block`) on something new that waits for the person: its card still pending, else the message its need asks with, which no earlier blocked turn of it told (a turn blocked on what was told before, or on nothing waiting, is noticed as `done`) | `需要处理 · <its last message>` |
| `failed` | something went wrong: the station says so in the chat, `⚠️` first (a turn that failed, an agent that could not start) | `出错了 · <what it says>` |
| `message` | another person said something in the chat, while no agent there is at work | `<name>: <text>` |

The title is the chat's title as the sidebar shows it. Texts are one line
(whitespace collapsed), cut to 140 characters. A notification opens the chat at
the message it is about: `/o/<workspace>/<station>/<session>?message=<seq>` (the
link every client already opens; the chat's list goes to that message and flashes
it, as when a row's state line is pressed, and the link loses `message`). Without
a `seq` (an older station) it is the chat's link alone.

## Client core: the `notices` topic

`notices` (`workspace?`) is kept by the core (`notices.ts`, fed by what the sync (`station/sync.ts`)
keeps: every station's `chatRows`), each workspace's apart: with a `workspace`,
that workspace's (the last 20), with none every workspace's. Its value:

```jsonc
{ "items": [{
  "id": "n7",                      // unique while the core runs; new ones have ids not seen before
  "kind": "done",                  // done | block | failed | message
  "station": "ws/st", "workspace": "ws", "stationId": "st",
  "session": "<row id>", "thread": 7,
  "seq": 12,                       // the message it is about: the card for `wait`, else the chat's last
  "title": "部署挂了", "body": "Claude: 修好了",
  "tag": "ws/st/<row id>",
  "url": "/o/ws/st/<row id, URI-encoded>?message=12",
  "at": 1790000000000
}] }                               // oldest first, the last 20
```

A client takes the items it has not seen; the ones in the first value it gets
are old news (shown by nobody). From a row's changes, `notices` adds one when a
row that is `mine`:

- is `block` asking something that waits for the person and was not told yet
  (its `need`, the message 待处理 shows: an agent woken by a job that ends blocked
  on the same ask again, or blocked on one a person has answered since, is not
  noticed as `block`);
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
| `push.register` | `{ kind: "web", endpoint, keys: { p256dh, auth } }`, `{ kind: "fcm", token }` or `{ kind: "apns", token, sandbox? }` (the APNs token in hex; `sandbox`: a development build's) | — ; registers this device with every signed-in account, and again with each account signed in later (kept in storage). The core adds what the device shows (`lang`, `kinds`, `preview`, as `notify.set` keeps them) and registers it again with every account whenever they change |
| `push.unregister` | — | — ; takes this device's registration off every account |
| `notify.set` | `on?`, `asked?`, `kinds?`, `preview?`, `workspaces?` | the `notify` value; kept on the device. `workspaces` (a workspace's id → heard of, each given one changing) turns a workspace's notices off or on again: one turned off has none shown and none pushed (its registration says `muted`, the cloud sends nothing of it), and adds nothing to the app's badge (`workspaceMarks` `badge`; its own mark stays); every other one, those joined later too, is heard of. `kinds` (`{ wait, failed, done, message }`, each given one changing) says which notices are shown: `wait` covers `wait` and `block`; `done` is `off`, `away` (only while no page of the app is in front: shown and focused; the default) or `always`. `preview` off: a notice's body says only what kind of thing happened (待你决定, 出错, 已完成, 有新消息), not what was said; a push's too, as the cloud makes it for the device (its registration says `preview`), so what was said does not leave for the push service. Off also takes this device's registration off every account, and `push.register` does nothing while off |
| `notify.permission` | `state` | — ; what the system lets this device show, as its app finds it: `granted`, `denied`, `default` (not asked yet) or `unknown`. Not kept: each app says it as it starts and again as it comes back to the front (a browser also as its site permission changes: web/src/notify.ts; the desktop app from its main process: apps/desktop/src/notify-permission.ts; Android from its activity) |
| `client.focus` | `visible?`, `focused?`, `chat?` (`{ station, thread?, session?, end?, seen? }` or null: `end` its end shows, `seen` the seq of the newest message shown whole), `left?` (a chat), `workspace?`, `newChat?` (a workspace) | — ; where this UI's attention is (each field given changes; `left`: that chat is not shown any more, if it is the one; `workspace`: the one it is in, else its chat's; `newChat`: that workspace's new chat shows, so it is what the workspace goes back to, not the chat last shown) |
| `notice.claim` | `id` | `{ show }`: true for the first page that takes a notice of `notify.show` |
| `notice.pushed` | `workspace?`, `kind?`, `title?` | `{ show, title? }`: whether a push that came is shown (on, its kind on, its workspace not turned off, no page in view); with `title` and `workspace`, the title to show (as `show`'s titles are) |
| `notice.bring` | `station`, `session`, `seq?` | — once what a shown push is about is on the device: the chat's messages after what is held (none when `seq` is held already), its chat found in the station's chats if the device holds none; nothing for a station it does not reach |

`notify` (no params, attend.ts) is what the clients show from: `{ on, asked, push, kinds, preview, muted, workspaces, permission, show }`
(`muted`: the workspaces turned off; `workspaces`: those the accounts are in, `{ id, name, emoji?, icon?, on }`, the
notifications page's switches where there is more than one); every client's notifications page shows `permission` the same way (a refused one on the banner tile, with the way to the system's settings where the app can open them). `on` and `asked` (the
system asked to allow them, once) are kept on the device, on by default. `push`: this device should hold a push
registration. `show`: the notices to show now, decided as they come: none while off; none for a chat a UI is looking at
(`client.focus`: `visible`, `focused`, that chat); none while this device has pushes and no page is in view (the push
says it); only while some UI subscribes (what came before is old news); none of a workspace turned off. One of a
workspace the viewer is not in has that workspace's name before its title (`核心 · 部署挂了`). The workspace the viewer
is in is that of the UIs in view (as each said with `client.focus {workspace}`, else its chat's), or with none in view
of every UI (a phone's app in the background is still in its workspace); with no UI saying, every one. A page takes each
with `notice.claim`, so it is shown once however many pages are open; one not taken goes after 30 s.

## still.fail cloud

- `GET /v1/push/key` → `{ vapid }` (no auth).
- `POST /v1/push` (bearer access token) `{ kind: "web", endpoint, keys: { p256dh, auth } }`, `{ kind: "fcm", token }` or `{ kind: "apns", token, sandbox? }`, with `lang?` and what the device shows: `kinds?` (as `notify.set`), `preview?` → 204. One row per account and endpoint/token: a device signed in with several accounts has one for each (registered again with the same account, it moves to this session, with what it says now). A device that two of a notice's people are signed in with gets it once. A device that said what it shows is sent only those kinds (`block` is `wait`; `done` unless `off`, as no page of it is in front when a push is shown), with its `preview` off a body of only what happened (`cloud.notice.hidden.*`); one that said nothing (an older app) gets every kind in full.
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
    "seq": 12,                     // the message it is about (its number in the chat); optional
    "title": "部署挂了", "by": "Claude", "text": "修好了", "at": 1790000000000
  }] }
  ```

  → `{ "sent": n }`. The cloud makes the body as the table above says, and
  pushes to each mstill.fail's registrations. A device its push service answers
  404/410 (gone) for is dropped, with every account it was registered with.

Push payload (Web Push: the encrypted body, `aes128gcm`; FCM: a data message,
high priority, every value a string; APNs: an alert, its `aps` the title and
body, `thread-id` the tag, `apns-collapse-id` a hash of the tag so a chat's
newer push replaces the one shown, beside `aps` the same keys):

```jsonc
{ "type": "notice", "kind": "done", "title": "…", "body": "…",
  "tag": "ws/st/<session>", "url": "/o/ws/st/<session>?message=12",
  "workspace": "ws", "station": "st", "session": "<key>", "at": "1790000000000",
  "seq": "12" }                    // when the station gave one
```

Secrets: `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` (P-256, base64url raw
public point / private scalar `d`), `VAPID_SUBJECT` (a `mailto:`);
`FCM_SERVICE_ACCOUNT` (the Firebase service account's JSON); `APNS_KEY` (the
team's APNs key: `{ keyId, teamId, key: the .p8's PEM, topic? }`, the topic the
app's bundle id, `fail.still.iphone` by default; the deploy directory's
`apns.json`, GitHub's `APNS_JSON`). Without VAPID keys `/v1/push/key` answers
404 and web registrations are refused; without the service account FCM pushes
are skipped, without the APNs key APNs pushes. APNs is spoken to straight from
the worker (its HTTP/2 API, an ES256 provider token kept 40 minutes).

## Station

The station notices at the two moments that matter (station/src/cloud/notify.ts):
an agent's turn ending, and a message in one of
its own chats: a person's, or the station's own ⚠️. It posts them to still.fail cloud, batched over a second;
one that cannot be sent is dropped. A station not enrolled with still.fail
cloud sends nothing. An older cloud answers 404, and nothing more comes of it.

## Clients

- Web: a service worker (`/sw.js`) shows pushes when no page of the app is
  open, and opens (or focuses) the app on the notification's `url`. The page
  shows the local notices the core's `notify` says to show (it tells the core
  which chat it shows and whether it is in view and has focus). 设置 → 通知
  turns them on (asking the browser's permission) and off, kept by the core.
- Desktop (macOS, Windows, Linux): the app (apps/mbui, src/sfbase/notices.mbt) holds the core's `notify` while it
  goes on, a window shown or not (in the notification area, minimized), claiming each as a page would, and shows the
  system's notifications (UNUserNotificationCenter, Windows' toasts); clicking one opens the chat as a
  `stillfail://o/…` link would. The setting is the same page.
- Android: `POST_NOTIFICATIONS` is asked for; one channel (消息); local notices
  while the app is in front (not for the open chat; the core's `notify`), FCM
  pushes while it is not (`notice.pushed`). A push shown also brings its
  chat's new messages onto the phone while FCM lets the app run
  (`notice.bring`, after `client.wake` for how long the app was away), so
  tapping it opens on them instead of waiting for the station to be reached
  again. The token is registered with `push.register`. Tapping either kind opens its chat at the message it is
  about (`seq`: the card for `wait`, else the message noticed), with Back
  returning to its chat list; without a `seq` (an older station or cloud) the
  chat opens where it would. 我 → 通知 turns them off, kept by the core.
- iOS: the app asks for its APNs token each start (an app signed with the
  `aps-environment` entitlement: TestFlight's and the App Store's) and
  registers it with `push.register` (`sandbox` when its profile says
  development). The system shows a push itself; while the app is in front it
  shows none (the app shows its local notices there). Tapping one opens its
  chat at the message it is about, as on Android. A push does not wake the app,
  so it neither brings the chat's messages nor puts another workspace's name
  before the title.
