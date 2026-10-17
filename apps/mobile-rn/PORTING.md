# Porting the Android app to React Native

This app is the Android app (`apps/android`, Kotlin + Compose) made again in React Native, one for Android and iOS.
The Android app is the spec: **every page, control, number, word and motion is as it is there**. Nothing is
redesigned, simplified or left out; where something cannot be done the same way, say so in a comment at the place.

## How it is put together

| | Android app | here |
|---|---|---|
| the core | `apps/android/core` (Hermes + Rust shell), Kotlin client `StillFailCore` | the same engine (`modules/stillfail-core`, its AAR), the web's client `web/src/core/client.ts` |
| topics | `rememberTopic<XView>(app.core, Topics.x(...))` | `useTopic<XView>({ topic: "x", ... })` from `web/src/core/react.ts` |
| shapes | `data/Shapes.kt` (generated) | `web/src/core/shapes.ts` (the same, generated) |
| calls | `app.core.call("name", buildJsonObject { … })`, `data/Calls.kt` | `core().call("name", { … })` (`web/src/core/react.ts`), or `app.call` |
| what is under way | `app.isDoing("call", "k" to v)`, `app.failedOf(…)` | `useDoing("call", { k: v })`, `useDoingFailed(…)` from `web/src/doing.ts` |
| prefs | `app.kept`, `app.setPrefs` | `usePrefs(p => …)`, `setPrefs(patch)` from `web/src/prefs.ts` |
| words | `t("key", "name" to value)` | `t("key", { name: value })` from `src/i18n` (the same catalog: `client/i18n/catalog`) |
| app state | `AppState.kt`, `LocalApp.current` | `src/AppState.ts`: `app` (push, pop, sheet, menu, toast, act…), `useApp(s => …)` |
| colours | `C.ink` | `const C = useC()` from `src/ui/Theme.ts`, then `C.ink` |
| icons | `Icons.ChevronDown` | `<Icon icon={Icons.ChevronDown} size={16} color={C.muted} />` from `src/ui/Icon.tsx` |
| corners | `clip(Smooth(12.dp))`, `concentric` | `<Smooth radius={12} style={{ backgroundColor }}>` from `src/ui/Smooth.tsx` (clips what it holds) |
| circles | `CircleShape` | `borderRadius: size / 2` on a plain View |
| curves, springs | `ui/Motion.kt` `Ease.*`, `motionSpring` | `src/ui/Motion.ts` (the same names), with Reanimated |
| glass | Haze (`hazeSource`, `glass`, `floating`) | `src/ui/Glass.tsx` (expo-blur's Android blur over what is behind) |

Kotlin file → TypeScript file, one for one, with the same names: `apps/android/shared/.../ui/Parts.kt` →
`src/ui/Parts.tsx`; `.../screens/Home.kt` (any module) → `src/screens/Home.tsx`; `.../drive/Reader.kt` →
`src/drive/Reader.tsx`; `.../data/X.kt` → `src/data/X.ts` only where the web's logic does not already do it. A
composable `fun Foo(a: Int, b: String = "x")` is `export function Foo({ a, b = "x" }: { a: number; b?: string })`,
with the same parameter names, so a page ported in parallel with the parts it uses finds them as Kotlin has them.

## Numbers

- `dp` is a React Native unit as it is (`16.dp` → `16`); `sp` is `fontSize` as it is (`15.sp` → `fontSize: 15`).
- Text: as `ui/Theme.kt` sets it, `lineHeight` 1.4 × the size and no letter spacing, unless the Kotlin says
  otherwise. Use `src/ui/Text.tsx` (`<T size={15} weight="600" color={C.muted}>`), which does that.
- `FontWeight.SemiBold` is "600", `Medium` "500", `Bold` "700".
- A `Row(horizontalArrangement = spacedBy(8.dp))` is `flexDirection: "row", gap: 8`; `Alignment.CenterVertically`
  is `alignItems: "center"`; `Modifier.weight(1f)` is `flex: 1` (with `minWidth: 0` for text that ellipsizes).
- `Box` with children aligned is a View with absolutely placed children (`position: "absolute"` and offsets).
- A tap target with `clickable` is `Pressable`; Compose's ripple is `android_ripple={{ color: … }}` with the same
  bounds (a `clip` before `clickable` bounds it: `borderless: false` inside the Smooth or round View).

## Motion

Every `animate*AsState`, `Animatable`, `tween(ms, easing)`, `spring` is the same timing in Reanimated
(`withTiming(v, { duration, easing: Ease.X })`, `withSpring(v, motionSpring(…))`). Gestures are
`react-native-gesture-handler`. Keep what moves where and when exactly as the Kotlin has it.

## Platforms

Android first: this is what is compared against the Android app. Write shared code; where iOS should look its own
(the system's navigation bar, tab bar, Liquid Glass), that is a `.ios.tsx` beside the file, later.

## Checking

- `npx tsc --noEmit` in `apps/mobile-rn` (on studio, through station_task; this machine does not build).
- `bash scripts/android.sh` builds the release APK; `bash scripts/emu.sh <apk>` runs it on this trial's emulator;
  `bash scripts/emu.sh shot <png>` takes a screenshot.
