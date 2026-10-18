# still.fail's Android app, mapped (2026-10-19)

What `ember/apps/android` is made of, for building still.fail again in mbui
(the user, 2026-10-19: rebuild the native still.fail, run both side by side,
switch when it is ready). Read from ember main 8271d2511; sizes are Kotlin
lines. The plan built on it is docs/stillfail-port.md.

I mapped the native Android app at `ember-src/apps/android` using 23 read-only tasks on the station; nothing was modified or compiled. It is about 51k lines of Kotlin in main code, plus about 12k of tests. Line counts below are `wc -l`. The station RPC dropped once (refused connection, then "roster not current"); the retry with the same key worked.

Path prefixes used below:
- `chat/` = `chat/src/main/kotlin/fail/still/android/screens/`
- `settings/` = `settings/src/main/kotlin/fail/still/android/screens/`
- `app/` = `app/src/main/kotlin/fail/still/android/`
- `drive/` = `drive/src/main/kotlin/fail/still/android/drive/`
- `shared/` = `shared/src/main/kotlin/fail/still/android/`

## 1. Navigation map

**How navigation works.**
- There is no navigation library. `shared/AppState.kt` (708) holds `sealed interface Screen` with 45 routes. Each route has a string `id` and is kept in a `stack: List<Screen>`.
- `AppState` provides `push`, `open`, `replace` and back. `openLink(url)` turns still.fail links into screens. `openItem` and `openNew` open a chat or a new chat.
- `app/App.kt` (549) decides the top level: Splash, then `SignInScreen` when there is no account, then `Landing`/`Blocked` when there is no workspace, then `Pages`.
- `Pages` is an AnimatedContent with slide transitions and predictive back-swipe. Each page keeps its own saved state and its own followed topics.
- **Bottom bar** (`shared/Places.kt` 195, `ui/Bar.kt`):
  - Places are chats, decisions, files, stations, profiles, connects, usage, archive. A bar holds at most 4 (`BAR_SIZE`).
  - Default bars are `[chats, files, profiles, stations]` and `[decisions, usage, connects, archive]`.
  - A place's top page shows the bar; pushed pages hide it.
- **Wide screens** (`chat/Wide.kt` 179) have no bar; a bottom-left button raises the latest chats instead.

**Chats and their overlays**

| Screen | File (lines) | Shows | Reached from |
|---|---|---|---|
| Home (place "chats") | `chat/Home.kt` 775, plus Search 384, ListMotion 210, OpenJobs 104, RowPicture 90 | Workspace's chats, newest first, grouped; pinning/archiving; search field at the top; long-running jobs banner; frosted top bar (gear → Settings, station glyph → Stations) | Root; wrapped in `LockGate` (workspace lock) |
| Chat / NewChat | `chat/ChatHost.kt` 693 hosts both; `chat/Chat.kt` 1603; `chat/NewChat.kt` 560 | NewChat: pick station, model and effort, then the first message. It *becomes* the Chat in place, keeping the composer and focus. Chat: messages (Markdown, files, tool steps, decisions, jobs), frosted top bar, composer | Home row, bar notch "令" (new chat), notifications, deep links, many cross-links |
| Composer (part of ChatHost, not a route) | `chat/Composer.kt` 1173, Attach 247, StationFiles 315, PastedText 22, MessagePick 327 | Draft per chat (kept on device), quotes, files, `@` mentions; "+" sheet with recent photos, camera, photo/file pickers, station files; long pastes go as a .txt file | Inside Chat and NewChat |
| Chat sheets | `chat/ChatInfo.kt` 273, AgentSheet 238, Jobs 300, Publish 226, ChatLink 83 | Chat's own sheet ("…"), an agent's card, jobs/services, publish links, copy link | From the chat's bar, avatars and rows |
| History | `chat/History.kt` 747 (also `RunSettingsScreen`) | An agent's execution history, full screen: what it received and sent, tool steps | AgentSheet, inside History |
| RunSettings | `chat/History.kt` | Model/account/effort of a run | AgentSheet, History |
| Decisions (place) | `chat/Decisions.kt` 650 | Open decisions across chats: options as full-width buttons, reply, defer, dismiss | Bar, Home |
| FilePreview (overlay, not a route) | `chat/FilePreview.kt` 1152, ImageMarks 919, VideoViewer 405, ChatFiles 576, Viz/VizFiles 135 | Full-screen file viewer: image zoom/pan/gallery with marking, video (frame stepping), audio, PDF (PdfRenderer), Markdown, CSV table, HTML in a WebView | Tap a file in a chat; also `Elsewhere.preview` from Drive/Search |
| Preview (web service) | `chat/Preview.kt` 1005, PreviewWeb 693, PreviewLoad 77 | An agent's dev server in a WebView, proxied through the core | Jobs, OpenJobs, Search |
| PreviewFile | `chat/Preview.kt` | An HTML file served the same way | VizFiles |
| Archive (place) | `settings/Archive.kt` 173 | Archived chats grouped by day | Bar, Home |

**Drive**

| Screen | File (lines) | Shows | Reached from |
|---|---|---|---|
| Files (place) | `drive/Files.kt` 123 | Every station's lent folders by station; "+" lends another | Bar |
| Drive | `drive/DriveScreen.kt` 958 | One folder per page: list/grid, upload, rename, delete, zip, share out, view sheets | Files, Stations, Search |
| Reader (DriveRead) | `drive/Reader.kt` 646, TextModel 585, ReaderMarkdown 305, Novel 139 | Text/novel reader: reflow, chapters, GB18030 decoding, tap toggles frosted bars | Drive, Search, Wide |
| Player (DrivePlay) | `drive/Player.kt` 561, DriveSource 148, Playlist 73 | ExoPlayer streaming through ranged `drive.read` calls; playlist and subtitles; landscape | Drive, Search |

**Settings and account**

| Screen | File (lines) | Shows | Reached from |
|---|---|---|---|
| Settings home | `app/screens/SettingsHome.kt` 230 (also Appearance) | Account card, then workspace rows, then this device's rows | Gear on place pages (PlacePage) |
| Me | `settings/Me.kt` 89 | Account, accounts on the device, sign-in sessions | Settings |
| Appearance | `SettingsHome.kt` | Theme | Settings |
| BarSettings | `settings/BarSettings.kt` 243 | Edit the bottom bars | Settings |
| Workspace | `settings/Settings.kt` 780 | Name, people, invites, roles, leave/delete, relays | Settings, Search |
| Workspaces switcher / Landing | `settings/Workspaces.kt` 451 | Workspaces, invitations | Splash/Landing, switcher |
| Stations (place) / Station | `settings/Stations.kt` 587, StationPermissions 122, Versions 184, `shared/StationUpdate.kt` 109 | Stations with state and load rings; one station's page: machine, network, screens, drive, memory, macOS grants, software updates | Bar, Settings, Home glyph |
| AdbShare | `app/screens/AdbShare.kt` 253, plus `app/AdbShare.kt` 441 | Lend the phone's adb (Wireless debugging) to a station | Station page, `/adb` link |
| Profiles (place) / Profile / ProfileAccount / NewProfile | `settings/Profiles.kt` 1147 | Model accounts per station, quotas, logins, sharing | Bar, Settings, NewChat, Chat, Vault |
| Connects (place) / Connect / ConnectRun / NewConnect | `settings/Connects.kt` 835, ConnectFlow 37 | Slack-style connects: run settings, session binding | Bar, Settings, Stations |
| SlackApp | `settings/SlackApp.kt` 552 | Edit a Slack app's manifest: name, colour, icon, scopes | Connect page |
| Vault / VaultItem | `settings/Vault.kt` 1009 | Workspace library: items, uses, lock/recovery sheets | Settings/Security |
| Security / SecurityOpen | `settings/Security.kt` 439 | Workspace lock mode, confirming devices | Settings, Vault |
| Usage (place) / UsagePrices | `settings/Usage.kt` 269 | Spending over 7 or 30 days, bars per day | Bar, Settings |
| Memories / Memory / MemoryDoc | `settings/Memory.kt` 282 | Agents' global and per-skill memory per station | Settings, Stations |
| AutomaticDecisions (+ Completion, Policy) | `settings/AutomaticDecisions.kt` 264 | Auto-decision policy per station | Settings |
| KeptFiles / KeptChat | `settings/KeptFiles.kt` 191 | On-device cache per chat, clear it | Settings |
| Changelog | `settings/Changelog.kt` 137 | What changed, by day | Settings, PageParts |
| Connection | `settings/Connection.kt` 43 | Retry for a dropped connection | — |

**Outside the main stack**
- `SignInScreen` (`app/screens/SignIn.kt` 92) is gated by the `accounts` topic.
- `ScreenViewer` is a separate activity. Files: `app/remote/ScreenActivity.kt` 133, ScreenViewer 1044, ScreenSession 269, Decoders 234, Input 254, Avc 94, ScreenClips 133, ScreenDrops 147. It shows and drives a station's desktop or browser and opens from `/screen/<id>` links or the station page.
- `ShareSheet` is a separate activity. Files: `app/share/ShareActivity.kt` 105 and ShareSheet 202. It catches `ACTION_SEND text/plain` and offers a chat to send it to.
- Shared page parts live in `shared/screens/`: PageParts 524, SettingParts 488, LoginCards 309, PlacePage 144, PlaceRows 117, Notes 150, FileKinds 181, Elsewhere 35 (cross-module hooks), Action 43.

## 2. Shared UI kit (`shared/ui/`)

- **Theme.kt (100)**: warm paper look; Material 3 is used only for text fields and ripples.
  - Light: bg `#F5F3EF`, surface `#FFFFFF`, surface2 `#FBFAF7`, ink `#24272B`, muted `#7A7D83`, subtle `#A6A8AC`, line `#E7E3DC`, lineStrong `#C1C4C9`.
  - Light accents: accent `#E5704A`, accentBg `#FBE6DC`, accentInk `#B9471F`, green `#2F8F5B`, red `#C9412E`, warn `#D9962B`, blue `#1559C4`, chip `#EFECE6`, bubble `#E8E4DC`.
  - Dark: bg `#1B1C1F`, surface `#26272B`, surface2 `#2C2D31`, ink `#ECECED`, muted `#9A9DA3`, subtle `#6E7177`, line `#34353A`, lineStrong `#3D3F44`.
  - Dark accents: accent `#EF7A55`, accentBg `#4A2F25`, accentInk `#F6A383`, green `#5CC08A`, red `#EB6B58`, warn `#D9962B`, blue `#81AEFA`, chip and bubble `#313237`.
  - Type: line-height 1.4em, letter spacing 0. Code font is bundled JetBrains Mono (variable), 12sp on 18sp lines.
- **Corners.kt (164)**: `Smooth(r)` superellipse corners (n = 2^1.5, radius ×1.25) to match the web. Used everywhere instead of plain rounded rectangles.
- **Glass.kt (115)**: frosted glass via Haze.
  - Tint is bg at 70% with CSS `blur(24px)`; `cssBlur(px) = (px-0.5)/0.57735 dp`.
  - Top bars get a 0.5dp hairline underneath.
  - Floating capsules use raised colour at 72% with a 20px blur.
  - Composer: corner 26dp, inset 8dp, files inset 10dp.
  - Real blur needs Android 12+; older devices get the tint only.
- **Bar.kt (1197)**: the bottom bar.
  - A floating frosted capsule, track 56, inset 6, with a frosted "ball" (68) that springs to the selected place and stretches with speed (max stretch 36).
  - The page's primary action sits in a notch cut into the top of the bar (gap 6, fillet 8, lift 4).
  - Dragging up opens a panel of the other bars (rows of 56; opens at 24px, closes at 16px; touch slop 8).
  - All of it runs on springs stepped once per frame by `BarModel`.
- **Sheet.kt (349)**: one bottom sheet at a time.
  - Rests at 55% or 94% height, or fits its content up to 90%. Closes below 30% or after an 80dp drag-down; minimum 120dp.
  - Grabber 38×5dp; top corners Smooth 26dp with a 24dp shadow; scrim black at 28%; glass is surface at 80%.
  - Also hosts the long-press menu (180dp wide, its own spring), the toast host and `ReaderHost`.
- **Parts.kt (595)**:
  - Marks: `ModelMark` (36dp, Smooth 11; 6 when small), `AgentStateMark`, `StationMark`, `ProviderMark`, `MakerIcon`, `SlackMark`.
  - People: `Avatar`, `PeopleStack` (18dp, overlapping by 5dp).
  - Quotas: `QuotaChips`/`QuotaDials`/`QuotaRings`, `MeterChips` (10 cells of 7×14).
  - Controls: `Seg` (segmented control, 30dp tall, radius 10).
  - Navigation: `NavBar`, `NavBack`, `NavButton` (34dp circle), `LargeTitle`, `SectionHeader` (20dp start).
  - Lists: `Card`, `ListCard`, `ListRow`; also `Badge`, `Splash`, `Illustration`, `DownloadChip`.
- **Controls.kt (136)**: `Button`, `Field`, `PickRow`, `GroupLabel`, `DoingMark`, `kindIcon`, `fileSize`.
- **Markdown.kt (738)**: commonmark with GFM tables, strikethrough and task lists, at 15sp with 1.65 line height.
  - Handles chat/screen/adb/card links, refs and side-by-side tables.
  - Related: `Links.kt` 150 (bare URLs with an open/copy menu), `TextMark.kt` 162 (passage highlight), `Pick.kt` 174 (word selection).
- **Highlight.kt (539)**: a light code tokenizer using Shiki's vitesse-light and vitesse-dark colours. `CodeInk.kt` 84 caches the text layout.
- **ToolStep.kt (393)**: draws tool calls by kind: a command, an edit as a diff, a file as highlighted code, a patch, a plan.
- **Viz.kt (439)**: inline HTML visualizations and ```mermaid blocks in a WebView.
- **Waiting.kt (239)**: three ways of waiting.
  - First load: `Waiting`/`WaitShapes`, placeholders shaped like the content, "breathing", no words.
  - In-progress: `Spinner`, `Progress`, `WaitLine`, `WaitPill`.
  - Docs: `docs/ui-panels.md`.
- **Motion.kt (169)**: CSS curves.
  - Out (0.2, 0.7, 0.2, 1); Arrive (0.2, 0.8, 0.2, 1); Flight (0.6, 0, 0.2, 1).
  - CssOut (0, 0, 0.58, 1); Decel (0, 0, 0.2, 1); LeaveFade (0.3, 0, 0.5, 1); Css (0.25, 0.1, 0.25, 1).
  - `MoveSpring` (0.28) and `SheetSpring` (0.32); `rememberLoop`.
- **Others**:
  - `Follow.kt` 231: list that sticks to its newest end.
  - `Zoom.kt` 240: pinch, pan and double-tap zoom.
  - `ThumbHash.kt` 133: blurred placeholder images.
  - `StationGlyph.kt` 114: circle split into one arc per station, robot in the middle.
  - `Icons.kt` 480: generated from `design/icons`, 1.75 stroke.
  - `ChatInk.kt` 214, `Keyboard.kt` 128 (IME insets), `ListKeys.kt` 93 (crash-safe lazy-list keys), `StatusText.kt` 52, `Host.kt` 21 (`LocalUi`).

## 3. Data layer

**Engine** (`core/src/main/kotlin/fail/still/core/`):
- The core is TypeScript (`client/core-ts`), compiled to Hermes bytecode (`core.hbc` in assets). It runs in Hermes (`com.facebook.react:hermes-android` 0.81.4, without React Native) through JNI `libstillfail_hermes` (`cpp/engine.cpp`). The JNI surface is `HermesNative.start/connect/receive/receiveBytes/complete/close`.
- All IO (HTTP, cloud WebSocket, SQLite, files, iroh mesh, TCP to adbd) is done by a Rust shell, `libstillfail_shell.so`. Both are built by `apps/android/build.py`. arm64 only, minSdk 29.
- The core calls back into the app for `secure.ask/get/set/delete` (`SecureStore.kt` 330: Android Keystore AES/RSA plus BiometricPrompt) and `listen.open/next/respond/close` (`Loopback.kt` 223: localhost OAuth listener).
- `Engine.kt` is 128 lines.

**Protocol** (`StillFailCore.kt` 403; spec in `docs/client-core.md` "Protocol"):
- UI to core: `{id, call, params}` (optionally with bytes alongside), `{id, subscribe:{topic,...}, keyed:true}`, `{id, unsubscribe:true}`, `{id, cancel:true}`.
- Core to UI: `{id, ok}` or `{id, error:{code,message,status}}`; progress as `{id, value}` before `ok`; topics as `{id, value}` then `{id, delta:[{path, append|set|remove}]}` (`Delta.kt` 108).
- `{fatal}` restarts the core.
- Kotlin API: `call`, `callBytes`, `stream`, `tell` (fire-and-forget), and `topic(json): Flow<TopicState>` (shared, conflated, unsubscribed 2 s after the last collector leaves).

**App side** (`shared/data/`):
- `Topics.kt` 375: `rememberTopic`, `PageTopics`, `preread`.
- `Shapes.kt` 4674: 303 generated classes from `core-ts/src/shapes/schema.ts`.
- `Operations.kt` 762: generated from `ops.ts`; `StationOperations` plus `CloudOperations`.
- `Calls.kt` 785: hand-written wrappers. Uploads go in 4 MB parts (`station.upload.part`, `drive.upload.part`, `station.file.part`); `DRIVE_PART` is 4 MB.

**Topics used, by screen:**
- App: accounts, workspaces, status, chats, chat, history, job, archive, decisions, drive, longJobs, stations, vaultItems, workspaceMarks.
- AppState: chat, doing, notify, prefs.
- Home: chats, status, workspaceMarks. Chat: chat, chatJobs, live. Composer: chatSearch. NewChat: newChat, pick.
- History: agentCard, chat, history, host, pick. Decisions: decisions. FilePreview: imageNear. Preview: job. Jobs: chatJobs, jobLog.
- Search: search, stations. StationFiles: drive, stations. Drive: drive, drivePlace, stations, workspace.
- Stations: adbShare, memberships, screens, stations. Profiles: memberships, profiles, stations. Connects: connects, pick, stations, workspace. SlackApp: slackApp.
- Vault: profiles, vaultItems, vaultUses, vaults. Security: lock, lockDraft. Usage: usage. Changelog: changelog. Settings: joinable, loginSessions, stations, workspace.
- Me: accounts. Workspaces: accounts, workspaceMarks, workspaces. ShareSheet: shareIn. Notices/Push: notify. LoginCards: machineLogin, machineLogins.
- Cards in chats: adbCard, screenCard, agentCard. Others: notices, overview, draft, doing, prefs.

**Calls, by group:**
- auth: auth.begin/complete/signOut.
- chat: chat.send/latest/older/newer/place/pin/archive/rename/retry/discard/keep/publish/unpublish/xshare/ref(s); chats.archived; draft.get/put; newChat.create/pick/migrate; history.detail/older.
- decisions: decision.answer/reply/defer/dismiss/close; automaticDecisions.*.
- jobs and sessions: job.get/log/stop/clearEnded; session.new/stop/warm/settings/delete/evict.
- files: station.file(.part)/upload.part/preview/poster; preview.socket(.send); drive.place/read/folders/mkdir/rename/remove/zip/stage/upload.part/setRoots/refresh; file.peek; link.parse/preview.
- remote screens: screen.view/input/ack/keyframe/control/clipboard; drop.
- adb: adb.share/pair/grant/stop.
- notifications: push.register/unregister; notify.set/permission; notice.claim/bring/pushed.
- profiles: profile.* (add, login, quota, share, move…).
- connects and Slack: connect.*; slack.*.
- workspace: workspace.* (invite, roles, rename, removeStation…); invitation.*; station.join.
- security and vault: lock.open/toggle/disable/shown; vault/pick: pick.set/save/borrow.
- station software: software.check/update/auto/channel.
- memory and logins: memory.get; machineLogin.*; login.*.
- misc: prefs.set; cache.usage/clear; app.update; client.wake/device; changelog.seen; search.setPersonal; shareIn.open; widget.state/setState; admin.*.

## 4. Platform features the host must provide

| Feature | Android API used | Where |
|---|---|---|
| JS core runtime and native IO | Hermes + Rust shell `.so` (HTTP, WebSocket, SQLite, iroh) | `:core` |
| Secure storage / biometrics | AndroidKeyStore (AES, RSA) + BiometricPrompt (strong biometric or device credential) | `SecureStore.kt` |
| Browser sign-in, deep links | Custom Tabs; `stillfail://auth/callback` | SignIn, LoginCards, SettingParts, MainActivity |
| App links | Verified `https://app.still.fail/o/…`, `/invite`, `/w/*/s/*/{chats,adb,screen,login}/…` | MainActivity → `link.parse` |
| Push | FCM (configured by hand from BuildConfig) → `push.register` | `app/Push.kt` 159 |
| Local notifications | One channel, one notification per chat (tagged), `POST_NOTIFICATIONS` permission | `app/Notices.kt` 133 |
| Pickers and camera | PickVisualMedia, PickMultipleVisualMedia, OpenMultipleDocuments, TakePicturePreview; MediaStore recent photos (READ_MEDIA_IMAGES / user-selected) | Attach, DriveScreen, Settings, SlackApp, ScreenViewer |
| Share out / share in | `ACTION_SEND` + chooser + FileProvider; ShareActivity for incoming | DriveScreen; `share/` |
| Save to Downloads | MediaStore | FileKinds, ChatFiles, ImageMarks |
| WebView | Preview/PreviewFile (`shouldInterceptRequest` on host `preview.stillfail.invalid`, WebMessagePort for sockets); Viz/Mermaid; HTML in FilePreview | PreviewWeb, Viz, FilePreview |
| Video / audio | ExoPlayer (media3) with a custom ranged DataSource; MediaExtractor for frame stepping; forced orientation | Player, DriveSource, VideoViewer |
| PDF rendering | PdfRenderer | FilePreview, ChatFiles |
| Remote screen | MediaCodec H.264 decoded to a Surface, JPEG via BitmapFactory, keep-screen-on, touch/key input, clipboard images | `remote/` |
| Image decoding / blur | BitmapFactory / ImageDecoder; RenderEffect blur (Haze) | many files |
| Clipboard | ClipboardManager (copy link, code, message text) | ~15 files |
| Haptics | performHapticFeedback | Home, Links, MessagePick, Preview, ScreenViewer, SettingParts |
| Background work | No WorkManager. Two foreground services: AdbShareService and LoginRelayService | AdbShare, LoginRelay |
| LAN discovery | NsdManager plus WiFi MulticastLock (mDNS) | MainActivity, AdbShare |
| Self-update | PackageInstaller (`REQUEST_INSTALL_PACKAGES`) | Updates, Install |
| Accessibility service | Reads the adb pairing code off Settings | AdbCodeReader |
| Secure settings | `WRITE_SECURE_SETTINGS` to turn Wireless debugging on | AdbShare |
| Crash reporting | PostHog `$exception`; tombstones via ApplicationExitInfo | Crashes, Tombstone |
| System UI | IME insets, predictive back, dark mode, foldable/wide layout, edge-to-edge status bar | App, Keyboard |

## 5. Suggested build order

Sizes are Kotlin lines as a proxy; the mbui equivalents will likely differ.

0. **Host bridge (no UI)**: run `core.hbc` (or core-ts) and expose call/topic/delta, the JSON message protocol, plus host `secure.*` and `listen.*` callbacks. Reference: StillFailCore + Delta + Topics, ~900 lines. Generate the Shapes and Operations equivalents from `schema.ts` and `ops.ts` instead of hand-writing them.
1. **Design tokens and primitives**: Theme colours, Smooth corners, Motion curves and springs, Icons, Controls, Waiting. About 1.2k.
2. **Sign-in to workspace**: Splash, SignIn (browser + deep link `auth.complete`), Workspaces/Landing. About 600. Needs the deep-link and browser host APIs.
3. **Chat list**: Home rows (RowPicture, marks, PlaceRows) and a simple top bar; leave out Search, ListMotion and the glass bar. About 1.2k.
4. **Chat read-only**: Chat message list with Follow and Markdown (with Highlight added later). About 2.5k–3k.
5. **Composer**: text, draft, send; then Attach (pickers, camera) and upload parts. About 1.5k.
6. **NewChat + ChatHost**: the new chat turning into the chat. About 1.2k.
7. **Shell polish**: Sheet host, menu, toast, bottom Bar (simplify to a static capsule first), Glass. About 1.7k.
8. **Decisions + History + ToolStep + ChatInfo/AgentSheet/Jobs**. About 2.5k.
9. **Settings home + Me/Appearance/Usage/Changelog/Archive/KeptFiles** (mostly list pages on PlacePage/SettingParts). About 2k.
10. **Notifications** (local `notify` + FCM). About 300 plus host work.
11. **FilePreview**: images and zoom first, then PDF/video/HTML; ImageMarks last. About 2.5k.
12. **Drive**: Files, Drive, Reader, Player. About 3.5k; needs a media host.
13. **Stations/Profiles/Connects/Vault/Security/Workspace/Memory/SlackApp/AutomaticDecisions**: CRUD-heavy. About 6.5k.
14. **Preview (WebView proxy), ScreenViewer (H.264), AdbShare, ShareActivity, Updates**: platform-heavy, last. About 4.5k.

## 6. Docs relevant to the Android app's design (`ember-src/docs`)

- `mobile-parity.md`: narrow web (`web/src/mobile`) and the Android app are one UI; since 2026-09-30 the narrow web is the reference. Covers the bottom bar, touch vs mouse, and feature gaps per area. Most important for the UI.
- `client-core.md` (726): the core's Host interface, the UI↔core protocol, topics, views, calls, the "Native (Android)" section and the module layering table.
- `core-ts.md`: why and how the Rust core became TS running on Hermes for Android.
- `ui-panels.md`: rules for small floating panels and the three ways of waiting.
- `ui-package.md`: the web design system `@stillfail/ui`, where the tokens come from.
- `list-motion.md`: message-list motion rules (queued height-changing animations, follow-to-end).
- `design.md`: overall product design and constraints (Chinese).
- `notifications.md`: notification and push design, including the clients section.
- `share-in.md`: the share-into-still.fail sheet.
- `remote-screens.md`: screen view/drive protocol (H.264/JPEG, input, clipboard, files).
- `drive.md`: station drive (zdrive) operations, reader and player.
- `adb-share.md`: lending the phone's adb.
- `remote-login.md`: CLI logins with the phone's browser step and loopback relay.
- `workspace-lock.md`: security mode / lock. `vault.md`: workspace library.
- `public-share.md`: publishing a chat. `search.md`: search.
- `telemetry.md`: PostHog, including the Android section and `bar_switch` timing.
- `development.md`: Android build prerequisites (JDK 17, NDK 28.2) and the prebuilt engine/shell.
- `media-app.md`: a draft plan for a separate media app sharing the platform.
- `mesh-lan.md`: mDNS on the LAN.
- `changelog.md` and `releases/*.md`: release notes mentioning Android.