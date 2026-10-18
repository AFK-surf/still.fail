// The core in the Android app's Hermes (apps/android/core: the engine in C++, its IO in the Rust shell, client/shell):
// what Hermes has not put in first (hermes-globals.ts), then the core as any engine starts it (engine.ts). Bundled into
// one script the engine runs (scripts/hermes-bundle.ts), its entry hermes.ts or an app's own giving its modules.
import "./hermes-globals.ts";
import type { CoreModule } from "../module.ts";
import { startEngine } from "./engine.ts";

/// The core with `modules` in Hermes: it says it runs on Android unless the engine says otherwise.
export function startHermes(modules: readonly CoreModule[]): void {
  startEngine(modules, "android");
}
