// The core in its own engine beside the UI's (apps/android/core on Android: Hermes running client/core-ts, its IO in
// the Rust shell): `start` once, `post` a message as client.ts makes it, and what the core says comes as `message`.
import { requireNativeModule, type EventSubscription } from "expo-modules-core";

type Said = { json: string; bytes?: string };

interface StillfailCoreNative {
  start(cloudOrigin: string, beta: boolean): void;
  post(json: string): void;
  stop(): void;
  addListener(event: "message", listener: (said: Said) => void): EventSubscription;
}

export const StillfailCore = requireNativeModule<StillfailCoreNative>("StillfailCore");
export type { Said };
