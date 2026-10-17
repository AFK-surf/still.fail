// This phone's adb lent to a station's agents (docs/adb-share.md), Android's own part: the Android app's AdbShare.kt
// (Wireless debugging's ports found by DNS-SD, the foreground service with 停止, the pairing code's notification) and
// AdbCodeReader.kt, in Kotlin as they are there. What the service asks of the core goes through here: `serve` makes its
// calls and follows its topics with the app's core and gives back what came of them. None on iOS (no Wireless
// debugging there): `supported` is false and the rest does nothing.
import { requireOptionalNativeModule, type EventSubscription } from "expo-modules-core";
import { Platform } from "react-native";

interface StillfailAdbNative {
  supported(): boolean;
  start(station: string, name: string, words: Record<string, string>): void;
  developerOptions(): boolean;
  wirelessOn(): boolean;
  canSwitch(): boolean;
  switchOn(): boolean;
  onWifi(): boolean;
  openWireless(beside: boolean): void;
  reads(): boolean;
  openReader(): void;
  ready(): void;
  answer(id: number, error: string | null): void;
  value(id: number, json: string | null): void;
  addListener(event: "call", listener: (e: { id: number; name: string; params: Record<string, unknown> }) => void): EventSubscription;
  addListener(event: "follow", listener: (e: { id: number; topic: string }) => void): EventSubscription;
  addListener(event: "unfollow", listener: (e: { id: number }) => void): EventSubscription;
  addListener(event: "wireless", listener: () => void): EventSubscription;
}

const native = Platform.OS === "android" ? requireOptionalNativeModule<StillfailAdbNative>("StillfailAdb") : null;

/** The Android app's AdbShare object, as the page uses it (its `context` is the module's). */
export const AdbShare = {
  /** Wireless debugging is Android 11's. */
  get supported(): boolean { return native?.supported() ?? false; },

  /**
   * Lends the phone to `station`'s agents (`name`, for the notification); another station's in place of one before.
   * `words`: what the notifications say, by the catalog's key (`#one`: a key's words for `n` 1), as the service has no
   * catalog of its own.
   */
  start(station: string, name: string, words: Record<string, string>) { native?.start(station, name, words); },

  developerOptions(): boolean { return native?.developerOptions() ?? false; },
  wirelessOn(): boolean { return native?.wirelessOn() ?? false; },
  /** Whether the app may turn Wireless debugging on itself: the station's adb granted it (`adb.grant`). */
  canSwitch(): boolean { return native?.canSwitch() ?? false; },
  switchOn(): boolean { return native?.switchOn() ?? false; },
  /** Wireless debugging needs Wi-Fi: Android turns it off without. */
  onWifi(): boolean { return native?.onWifi() ?? false; },

  /**
   * Developer options, at Wireless debugging (its row lit up), where it is turned on and paired. `beside`: next to the
   * app when the screen is split (or splits, on large screens), so the app's own field can be used with the dialog open.
   */
  openWireless(beside = false) { native?.openWireless(beside); },

  /** Whether the person turned on AdbCodeReader (Accessibility), which fills the pairing code in by itself. */
  reads(): boolean { return native?.reads() ?? false; },
  /** Accessibility's settings, at AdbCodeReader's row where Settings lights it up. */
  openReader() { native?.openReader(); },

  /**
   * `changed` each time Wireless debugging is switched (by the app, or by Android as the Wi-Fi goes): the Kotlin page's
   * ContentObserver on `wirelessUri()`. Returns how to stop.
   */
  watchWireless(changed: () => void): () => void {
    const sub = native?.addListener("wireless", changed);
    return () => sub?.remove();
  },
};

/** The core as `serve` uses it: web/src/core/client.ts's CoreClient. */
interface ServedCore {
  call(name: string, params?: unknown): Promise<unknown>;
  subscribe(topic: { topic: string }, onValue: (value: unknown) => void, onError: (error: Error) => void): () => void;
}

let served = false;

/**
 * Makes what the service asks of the core (AdbShare.kt's Core: `adb.share`, `adb.pair`, `adb.stop`, the `adbShare`
 * topic) with `core`, for the app's life; `errorText`: a failure in words, as the Android app's errorText. Once, as the
 * app's JavaScript starts (again, after a reload: the service asks again for what it follows).
 */
export function serve(core: () => ServedCore, errorText: (e: unknown) => string) {
  if (native == null || served) return;
  served = true;
  const follows = new Map<number, () => void>();
  native.addListener("call", ({ id, name, params }) => {
    core().call(name, params).then(() => native.answer(id, null), (e: unknown) => native.answer(id, errorText(e)));
  });
  native.addListener("follow", ({ id, topic }) => {
    follows.get(id)?.();
    follows.set(id, core().subscribe({ topic }, (value) => native.value(id, value == null ? null : JSON.stringify(value)), () => undefined));
  });
  native.addListener("unfollow", ({ id }) => {
    follows.get(id)?.();
    follows.delete(id);
  });
  native.ready();
}
