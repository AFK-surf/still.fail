# A phone's adb, shared with a station's agents

> **Being changed (2026-10-29, user: 「不再需要全局开关，而是改成全局配置和 chat 授权」「跟密钥授权一样」).** What
> follows below is how it works until then. The target, as vault grants work (docs/vault.md 申请和授权):
>
> - **An agent asks** with a tool (`phone_use {reason}`, as `secret_use`): a card in its chat asks the phone's owner
>   (the chat's starter by default: `card.assignee`) whether this chat's agent may debug their phone, with the reason;
>   pushed. The tool does not wait for the decision (2026-10-30: a call held holds the agent's turn and everything said
>   in the chat meanwhile): the agent is told in its session when it is decided, and called again once approved it
>   answers how to use the phone (its serial, `ANDROID_ADB_SERVER_PORT`); with nothing else to do meanwhile it ends its
>   turn need_human about the card. Someone
>   writing yes in the chat is not a grant.
> - **Approved for a scope**, as a vault grant's: 本对话 1 小时内 (`hour`) or 本对话直到归档 (`chat`, 30 days at most),
>   up to the owner's 默认最长授权 (a setting of theirs, default `chat`); the card offers what that allows and
>   recommends the longest. Answered on the phone itself while it lacks something to be lent (Developer options, Wi-Fi,
  Wireless debugging the app cannot turn on), the card says what first and 查看步骤 (the 共享调试 page) takes 允许's
  place; Wireless debugging the app may turn on, it turns on as it is allowed. A grant ends as its scope does, when the chat is archived or deleted, or when the owner
>   takes it back (the card, the phone's notification, settings).
> - **Only that chat's agent reaches the phone.** The station runs an adb server of the grant's own
>   (`adb -P <port> server`), the phone connected in it alone, and gives its port to that session's commands only
>   (`ANDROID_ADB_SERVER_PORT`); the phone's tunnel listener takes connections from that server's process alone (the
>   peer of a loopback TCP connection, found by its ports in the processes' sockets). Another chat's agent, knowing the
>   port, is not let in.
> - **The phone lends while a grant is live**, to the station of that chat (one offer per station, its grants listed):
>   its foreground service and notification say which chats it is lent to, each with 停止. No per-station switch.
> - **Lent with no one at it** (2026-10-30: granted once, the phone is the chat's without its person at it): the grants the phone is lent for are
>   kept on the device (the core's `adb-grants`, `adbShare` `known` once read), so a core started anew lends for them at
>   once and the app's service does not take 「none read yet」 for 「none granted」; a process started by the phone
>   starting again or the app updating (`AdbBoot`) starts the core and the service while one is live (`grantsUntil`);
>   and each time the station's adb comes to hold the phone it lets the app turn Wireless debugging on itself
>   (`pm grant … WRITE_SECURE_SETTINGS`) and keeps Android's idling off its connection (`deviceidle whitelist`), no one
>   asked. phone_use says when and why a granted phone was last offered no longer.
> - **The phone's switch** (2026-10-30, user: 「还是要有一个全局的 adb 开关，默认关闭，开启后永远开启，不会因为更新或者重启关掉」):
>   共享调试 on the phone itself (`adb.on`, the core's `adbShare` `on`, kept on the device: the core's `adb-on`, the
>   app's `adb-share` `on`). Off at first: the phone is lent to no chat, whatever is granted, and a request's card
>   answered on it says 打开共享调试 first. On, until turned off there or with the notification's 关闭共享调试: the
>   app's service is up whether or not a grant is live (its notification 共享调试已开启 · 暂无对话在使用, or how many chats
>   use it), started with the phone and the app updated (`AdbBoot`), and turns Wireless debugging on again each time it
>   goes (the phone started again, the Wi-Fi changed) where the app may. Which chats reach it is still their grants'.
>   A device from before the switch takes it on where a grant lent the phone then.
> - **Settings, 共享调试** (one page, not a station's): on a phone its switch first, 默认最长授权, the phone's settings (本机设置: what it lacks, the
>   switches it can turn on), the stations it is paired with, and the grants live now (each with 收回).
> - **Recorded** in the chat as a system message each: asked, approved, refused, taken back, ended.
> - **Approved is not reached** (2026-10-30, user: 「Station 以为跟当前设备已经连了，但其实还没有，而且还没有什么入口」): a
>   phone is paired once with each station, and one granted to a chat on a station it was never paired with was lent
>   there, its station's adb `unpaired`, while the card said 已允许 and nothing showed where to pair. Now:
>   - The station tells a grant how its adb holds the phone (link.ts `Shares` `stated` → grants.ts `linked`): the card's
>     outcome carries it (`adb.outcome.link`: connected, unpaired, off, unauthorized, missing, failed, gone), its dot
>     green only once connected, and the agent is told in its session as it comes to need pairing and as it connects
>     (phone_use's answer says to leave pairing to the card).
>   - Unpaired, the card says so, with a card under it on the phone (a login card's look, the whole card the way to the station's own 共享调试 page, where it is paired), and on a
>     computer that it is paired in the app on the phone. Its 查看步骤 opens that station's page too (settings' page
>     while the switch is off: it is turned on there).
>   - A phone lent to several stations: the core's `adbShare` says at its top the lending a person has something to do
>     for (one waiting to be paired, else the first), so the pairing dialog's notification and its code reader (which
>     name no station) pair that one; a station's page reads its own lending from `lends`, and its pairing names it.
>   - Settings' 共享调试 lists the stations the grants lend it to, each as its adb holds the phone, its page a tap away.
>   - A link to a station's 共享调试 opens the page it shows as a card whatever host it was written with, a path alone
>     included (`linkTarget` takes `/w/…` as the cloud's own).
A person can lend their Android phone to the agents of one station: the phone's
own adbd (Wireless debugging, Android 11 and later) is reached from the station
at `127.0.0.1:<port>`, so an agent there runs `adb -s 127.0.0.1:<port> …` as if
the phone were on its desk. Nothing goes over the LAN or the internet but the
phone's existing mesh link to the station; adb's own TLS runs end to end, the
link only carries its bytes.

```
agent ─ adb ─ 127.0.0.1:<port> on the station ─ stream on the phone's link ─ the phone's core ─ 127.0.0.1:<adbd>
```

## On the phone

- **Wireless debugging** has to be on, the first time by the person (Developer
  options; it needs Wi-Fi). Once the station's adb holds the phone, it can grant
  the app `WRITE_SECURE_SETTINGS` (`adb.grant`, the person asks for it); then the
  app turns Wireless debugging on itself (`Settings.Global adb_wifi_enabled`).
- **Its ports** are random: the app finds them by DNS-SD on the device
  (`_adb-tls-connect._tcp`, `_adb-tls-pairing._tcp` while the pairing dialog is
  open) and gives them to the core (`adb.share`). A tunnel that finds nothing at
  the connect port is said in `adbShare` (`refusedPort`), and the app looks for the
  ports anew (some phones go on announcing an old one).
- **Pairing**, once per station: the person opens 使用配对码配对设备 and the
  app reads the six digits off the dialog itself (`AdbCodeReader`, an
  accessibility service the person turns on from 自动填配对码 on the 共享调试
  page). Settings closes the dialog as soon as it is paused, a field over it
  (the notification's) hides the code under the keyboard, and Settings hides
  other apps' windows over it (`HIDE_NON_SYSTEM_OVERLAY_WINDOWS`), so reading
  it is what is left. The service hears only Settings, looks only while a
  pairing port is announced for this app's share, takes six digits only from
  the window that also shows that port (`IP:port`), and tries once per dialog;
  the code goes nowhere but `adb.pair`. Without it the code is typed into the
  notification that pops up over the dialog (heads-up, channel `adb-pair`;
  some phones don't pop it up, and it hides the code), or into the app with
  the screen split. On Android 13 and later an app installed outside a store
  can't have an accessibility service turned on until 允许受限设置 in its app
  info. The station runs `adb pair` through the pairing port (`adb.pair`).
- **While it is shared** a foreground service holds the app up and says so in a
  notification, with 停止. Sharing ends after an hour or when it is stopped. An
  app whose process goes while it is shared (updated, killed by Android, a
  crash) lends it again to the same station as it next starts, for what is left
  of the hour (mbui's AdbShare.java `resume`: what it is lent to and until when
  kept on the device from the tap on, let go as the share ends).

The core (`client/core-ts/src/adb.ts`) holds the offer: the `adbShare` topic and the
calls `adb.share`, `adb.stop`, `adb.pair`, `adb.grant`. Only a phone lends: a
native core on a device that said it is Android (`client.device` `app`); a Mac's
or a PC's core has sockets but no adbd, and the web has neither. Elsewhere a
chat's card of a station's 共享调试 says so (`adbCard` `lendable: false`) and
does nothing, and the station page's row goes nowhere.

In a chat, an agent's link to it alone in a paragraph is a card that asks (as
a vault request's does): whether that station's agents may debug this device.
Once the phone has Developer options and Wi-Fi, and Wireless debugging on (or
the app may turn it on itself), 共享 lends it from the card; before that the
card says the first thing the phone lacks and 查看步骤 opens the page, which
says how. While it is lent there the card says how that stands, with 详情 and
停止共享. On a wide frame the page opens beside the chat, as the station's own
page does (a tab, `adb:["<station>"]`).

## On the wire

Over the member link (ALPN `stillfail/admin/1`; station/src/mesh/serve.ts):

1. **The offer**, a stream the phone opens: the head line
   `{"method":"POST","path":"/admin/api/adb","headers":{},"adb":{"op":"share","phone":"<its device key, hex>","device":"Pixel 8","android":"14","package":"fail.still.android","adbd":true,"pair":false,"connect":37123}}`,
   its send side finished at once. The station answers
   `{"status":200,"headers":{"content-type":"application/x-ndjson"}}`, then a
   line each time how its adb holds the phone changes:
   `{"serial":"127.0.0.1:37123","adb":"connecting|connected|unpaired|unauthorized|off|missing|failed","message":"…"}`
   (`off`: the phone said Wireless debugging is off, `"adbd":false`). `connect` is adbd's
   port on the phone: as it changes (Wireless debugging turned off and on) the station's adb
   connects anew.
   The offer lasts while the stream does: the phone stops reading it (dropping it
   sends STOP_SENDING) to stop sharing, and it ends with the connection. A newer
   offer from the same device takes its place (another link, another pairing
   port). A phone is its person's (the credential's) and its device key's: a
   link on one of its other keys (one per relay) is the same phone. A station
   from before answers 404 (the admin API has no such route).
2. **Asks**, one stream each, with `"adb":{"op":"pair","code":"123456","phone":…}` or
   `"adb":{"op":"grant","phone":…}`: answered with a status and `{"message":"…"}`. Only the
   device whose offer it is.
3. **Tunnels**, streams the station opens on the offer's connection, one per TCP
   connection to its port: the head line `{"tunnel":"connect"}` (or `"pair"`, for
   `adb pair`); the phone answers `{"ok":true}` once it reached adbd (or
   `{"error":"…"}`), then bytes both ways until either side finishes. A pairing's tunnel is not
   reset as `adb pair` ends: adb's last bytes (its key) may still be on the way, and the phone
   keeps the key only once it has them. The phone
   takes tunnels on every link an offer of it went on until that link closes:
   the station hears of the offer on a new link only once it comes, and opens
   its tunnels on the old one meanwhile.

## On the station

`station/src/adb/link.ts`: a listener on `127.0.0.1` for each phone offered (the
same port for the same phone when it is free, 37000–37999), `adb connect` to it
as the offer comes, `adb disconnect` as it goes. Failing to get in, it tries again
after 2 s, then twice as long each time (up to a minute), while the offer lasts. adb is the station machine's
(`PATH`, `$ANDROID_HOME`, the SDK's usual places); without it the offer says
`missing`. Agents see the phones shared with them with the `adb_devices` tool
(station/src/adb/tool.ts): each one's serial, model, owner and state, and the link
to ask a person for theirs: `<cloud>/w/<workspace>/s/<station>/adb` opens the
station's 共享调试 in the Android app (an App Link; in a chat the app opens it
itself, `link.parse` → `adbShare`). Sharing starts only once its person taps
开始共享 there; the web shows where to open it.

Every agent on the station can use a phone shared with it, as with anything on
that machine: that is what the person agrees to as they share it.
