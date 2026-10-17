# still.fail on React Native (trial)

A trial of the phone app as one React Native app for Android and iOS (EMBER/1792248050.339000): a fixed native shell
(Expo SDK 54, React Native 0.81, Hermes) and the UI as one JS bundle, hot-reloaded while developing and sent over the
air when released. The chats' list only, with a snapshot of real chats as its data; the core is not connected yet.

- iOS: the system's navigation bar (large title) and tab bar, Liquid Glass on iOS 26 (`src/Tabs.ios.tsx`).
- Android: still.fail's own frosted top bar and bottom bar (`src/TopBar.tsx`, `src/Bar.tsx`).
- `src/ota.ts`: checks for an update on launch, fetches it and reloads into it; `trial/ota-server.mjs` is a minimal
  expo-updates server for it (protocol 1).
- `trial/`: the scripts the trial's numbers came from (studio; builds, hot reload, OTA, recordings).

    npm install --legacy-peer-deps && npx expo prebuild && npx expo run:android   # or run:ios
