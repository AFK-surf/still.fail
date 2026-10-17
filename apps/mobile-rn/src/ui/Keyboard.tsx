// The keyboard as the pages and sheets see it: one position for all (KeyboardInsets), and a tap or drag elsewhere
// letting go of it (letsGoOfKeyboard).
import { createContext, useContext, useRef, type ReactNode } from "react";
import { Keyboard, type GestureResponderEvent } from "react-native";
import { KeyboardState, useAnimatedKeyboard, useAnimatedReaction, useSharedValue, withTiming, type SharedValue } from "react-native-reanimated";
import { Ease } from "./Motion";

const LocalKeyboard = createContext<SharedValue<number> | null>(null);

/**
 * The keyboard's height over the window's bottom, in dp, as it moves (WindowInsets.keyboard: all keyboard-aware surfaces
 * share one position, including sheets and the wide layout's corners). The navigation bar's part is in it, as the IME's
 * insets have it: what sits over the navigation bar takes that off (SheetHost does). A hook.
 */
export function keyboard(): SharedValue<number> {
  // Translucent: the navigation bar's part counted in, as Compose's WindowInsets.ime has it.
  const raw = useAnimatedKeyboard({ isNavigationBarTranslucentAndroid: true, isStatusBarTranslucentAndroid: true });
  return useContext(LocalKeyboard) ?? raw.height;
}

/**
 * In split screen, Android's WM Shell can animate the keyboard itself and dispatch only the final
 * IME insets to the app. The keyboard's place then jumps. Supply the missing motion there, using
 * DisplayImeController's show/hide durations and curve. When Android dispatches animation frames,
 * keep following those instead; full-screen insets pass through untouched.
 */
export function KeyboardInsets({ children }: { children?: ReactNode }) {
  const insets = rememberKeyboardInsets();
  return <LocalKeyboard.Provider value={insets}>{children}</LocalKeyboard.Provider>;
}

/**
 * The keyboard's height followed: the IME's own frames while it sends them (its animation under way: opening or
 * closing), and where only its end comes (split screen, where the WM Shell animates it), a glide there of the system's
 * own timing (275ms up, 340ms down, FastOutSlowIn). The Android app asks the activity whether it is in split screen
 * (isInMultiWindowMode); here a move that comes without frames is what split screen sends, so it is told by that.
 */
export function rememberKeyboardInsets(): SharedValue<number> {
  const raw = useAnimatedKeyboard({ isNavigationBarTranslucentAndroid: true, isStatusBarTranslucentAndroid: true });
  const bottom = useSharedValue(raw.height.value);
  useAnimatedReaction(
    () => [raw.height.value, raw.state.value] as const,
    ([height, state], was) => {
      const native = state === KeyboardState.OPENING || state === KeyboardState.CLOSING;
      const wasNative = was != null && (was[1] === KeyboardState.OPENING || was[1] === KeyboardState.CLOSING);
      if (native || wasNative) bottom.value = height;
      else if (height !== bottom.value) bottom.value = withTiming(height, { duration: height > bottom.value ? 275 : 340, easing: Ease.Standard });
    },
  );
  return bottom;
}

/** Android's touch slop (ViewConfiguration: 8dp) and long-press timeout (400ms since Android 12). */
const TOUCH_SLOP = 8;
const LONG_PRESS_MS = 400;

/**
 * A tap or a drag on what this is on lets go of what is being typed into, and the keyboard goes (what was typed stays).
 * It only watches: the tap or drag still goes to what is under the finger (a link, a button, the list's scroll). Going on
 * the finger lifted or moved past the slop, not as it comes down, so what is tapped does not move under it first. A long
 * press lets it be. A hook: the touch handlers to spread on the View it is on (they watch, they take no responder).
 */
export function letsGoOfKeyboard() {
  const down = useRef<{ id: string; x: number; y: number; at: number } | null>(null);
  const letGo = () => { down.current = null; Keyboard.dismiss(); };
  return {
    onTouchStart(e: GestureResponderEvent) {
      if (down.current) return;
      const { identifier, pageX, pageY, timestamp } = e.nativeEvent;
      down.current = { id: identifier, x: pageX, y: pageY, at: timestamp };
    },
    onTouchMove(e: GestureResponderEvent) {
      const d = down.current;
      if (!d) return;
      const t = e.nativeEvent.changedTouches.find((c) => c.identifier === d.id) ?? (e.nativeEvent.identifier === d.id ? e.nativeEvent : undefined);
      if (!t) return;
      if (Math.hypot(t.pageX - d.x, t.pageY - d.y) > TOUCH_SLOP) letGo();
    },
    onTouchEnd(e: GestureResponderEvent) {
      const d = down.current;
      if (!d) return;
      const t = e.nativeEvent.changedTouches.find((c) => c.identifier === d.id) ?? (e.nativeEvent.identifier === d.id ? e.nativeEvent : undefined);
      if (!t) return;
      // A long press is not a tap: it picks a passage there (MessagePick.tsx), whose quote may want the keyboard.
      if (t.timestamp - d.at >= LONG_PRESS_MS) { down.current = null; return; }
      letGo();
    },
    onTouchCancel() { down.current = null; },
  };
}
