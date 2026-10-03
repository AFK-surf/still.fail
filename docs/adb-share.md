# A phone's adb, shared with a station's agents

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
  open) and gives them to the core (`adb.share`).
- **Pairing**, once per station: the person opens 使用配对码配对设备 and types
  the six digits into the app's notification (the dialog closes if Settings is
  left); the station runs `adb pair` through the pairing port (`adb.pair`).
- **While it is shared** a foreground service holds the app up and says so in a
  notification, with 停止. Sharing ends after an hour, when it is stopped, or when
  the app goes; nothing is kept for a next run.

The core (`client/core-ts/src/adb.ts`) holds the offer: the `adbShare` topic and the
calls `adb.share`, `adb.stop`, `adb.pair`, `adb.grant`. Only native cores carry
tunnels (the web has no sockets).

## On the wire

Over the member link (ALPN `stillfail/admin/1`; mesh/station/src/main.rs):

1. **The offer**, a stream the phone opens: the head line
   `{"method":"POST","path":"/admin/api/adb","headers":{},"adb":{"op":"share","phone":"<its device key, hex>","device":"Pixel 8","android":"14","package":"fail.still.android","adbd":true,"pair":false}}`,
   its send side finished at once. The station answers
   `{"status":200,"headers":{"content-type":"application/x-ndjson"}}`, then a
   line each time how its adb holds the phone changes:
   `{"serial":"127.0.0.1:37123","adb":"connecting|connected|unpaired|unauthorized|off|missing|failed","message":"…"}`
   (`off`: the phone said Wireless debugging is off, `"adbd":false`).
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
   `{"error":"…"}`), then bytes both ways until either side finishes.

## On the station

`mesh/station/src/adb.rs`: a listener on `127.0.0.1` for each phone offered (the
same port for the same phone when it is free, 37000–37999), `adb connect` to it
as the offer comes, `adb disconnect` as it goes. adb is the station machine's
(`PATH`, `$ANDROID_HOME`, the SDK's usual places); without it the offer says
`missing`. Agents see the phones shared with them with the `adb_devices` tool
(mesh/app/src/adb.rs): each one's serial, model, owner and state, and the link
to ask a person for theirs: `<cloud>/w/<workspace>/s/<station>/adb` opens the
station's 共享调试 in the Android app (an App Link; in a chat the app opens it
itself, `link.parse` → `adbShare`). Sharing starts only once its person taps
开始共享 there; the web shows where to open it.

Every agent on the station can use a phone shared with it, as with anything on
that machine: that is what the person agrees to as they share it.
