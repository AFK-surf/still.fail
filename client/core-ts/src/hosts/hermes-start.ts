// The core in the Android app's Hermes (apps/android/core: the engine in C++, its IO in the Rust shell, client/shell):
// what Hermes has not put in first (hermes-globals.ts), then the core as any engine starts it (engine.ts). Bundled into
// one script the engine runs (scripts/hermes-bundle.ts), its entry hermes.ts.
import "./hermes-globals.ts";
import { startEngine } from "./engine.ts";

/// The core in Hermes: it says it runs on Android unless the engine says otherwise.
export function startHermes(): void {
  startEngine("android");
}
