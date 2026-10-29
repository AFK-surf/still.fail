# The app on iOS

`APP=stillfail scripts/ios.sh build | run` builds still.fail for the iOS simulator and runs it on a simulator of
its own (`MBUI_IOS_DEVICE`, default ios-mbui-sf): the same pages as Android and macOS, the core in Hermes (the same
`core.hbc`, src/host/apple_core.mm built for aarch64-apple-ios-sim with the Rust shell built for that target, Hermes's
xcframework slice in the app's Frameworks; core/README.md, "iOS"). mbui's scripts/ios.sh takes an app of this module
(MBUI_APP_MOD, a hook as Android's: scripts/ios-core.sh) and its host (ios_app.m) does what still.fail asks of it:

The app on iOS is Android's, as on an Android phone (2026-10-23):

- Edge to edge (ios/Info.plist's MBUIEdge, as Android's manifest dev.mbui.edge): the view from the screen's top to its
  foot, the status bar's and the home indicator's room said as the system's `bars`, each page padded where Android's
  is (src/sfapp/bars.mbt); round it, and at launch, the page's paper (MBUIGround; the launch screen's Paper colour),
  the status bar's words to match (`@hostapi.set_dark`).
- Its layout chosen by what the system says of the window, as on Android (src/hostapi/system.mbt `size_class`,
  `fold`; @sf.layout): regular in width said as medium under 840 points and expanded from there, the web's wide frame
  in the phone's theme, Medium on its tape, Large its sidebar ending on a fold that stands upright; the hinge
  (UIHingeInteraction) and where its fold
  divides the view (the view's division regions), iOS 27.1 on and built with its SDK (mbui.yml's ios job, on Xcode
  27.1): half open with the fold across the view, a chat's page across it, its messages over the fold, its composer
  and the latest chats under it (src/sfapp/tabletop.mbt).
- From side to side too: the safe area's sides said as `bars` (an iPhone Duo's outer screen has its status bar down
  its right side), the pages beside them on the page's paper (src/sfapp/sides.mbt).
- The keyboard as Android's: the view keeps its size, the keyboard's top followed frame by frame as the system moves
  it (UIKeyboardLayoutGuide's motion read off a mark's presentation layer), the app laid out above it; the keyboard
  asked for plain text, no capitals or curly quotes of its own, its return key a new line (a search field's its search
  key); put away by the person (not the app), the field lets go of the focus.
- Its touches and fields feel as Android's (@sfapp.host_setup: `@ui.feel_as(2)`): lists fling and give at their edges
  as Compose's and show no scroll bar (a finger's: src/ui/scroll_bar.mbt), a field takes a tap as it
  lifts, draws Compose's caret and handles, picks words by a long press or a double tap, with the system's floating
  edit menu over them (UIEditMenuInteraction: 剪切, 拷贝, 粘贴, 全选, as Android's ActionMode).
- Back: the left edge's swipe is the app's own (src/ui/nav.mbt), as on every host; iOS has no system back of its own.
- `secure.*` in the Keychain; the sign-in through ASWebAuthenticationSession (`stillfail` scheme), as on macOS. A
  login card's page in Safari's view over the app (SFSafariViewController, Android's Custom Tab): the app stays in front
  under it, the core's loopback listener answering the page.
- Pictures and files picked (PHPickerViewController, JPEG for the library's HEIC as Android's; UIDocumentPickerViewController),
  a photo taken (UIImagePickerController's camera), ＋'s recent photos (Photos: all of the library, or the photos
  chosen, its picker of more as Android 14's), the share sheet (UIActivityViewController), the app in front or not
  (`@hostapi.set_app_state`), its time off the screen (`shown`), the network changed (`network`), its links (`link`:
  a universal link, a URL of its scheme), a film sideways (the status bar and home indicator out of its way).
- Notifications the system's (UNUserNotificationCenter; no pushes: APNs wants a signed app, as Android's FCM is not
  done either). The build's number (CFBundleVersion: main's commits, as Android's versionCode) in 设置's version row
  and told to the core, which names the device still.fail mbui iOS · <its model> and says messages came from `ios`.
- Scripted runs (src/ui/drive.mbt): the keyboard's calls on the view, the paste, the app's picture, notifications
  tapped; the log on stderr (`simctl launch --stderr`).

- Sharing in (the person's choice, 2026-10-23: an iOS share extension cannot open its app): the share sheet's still.fail
  mbui (ios/Share-Info.plist; mbui's src/host/ios_share.m, PlugIns/Share.appex) keeps what is shared in the app group
  the two share and says to open the app; the app takes it as it next comes to the front (`@hostapi.shared_in`) and
  shows the same 发到 sheet as Android's, over itself (not over the app it came from).

Not yet, against Android: a signed build for a device and TestFlight (they need the Apple developer account, its
profiles the app group too), updates (the App Store's, not the app's).

