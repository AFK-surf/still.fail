// still.fail's core in Hermes, for the Android host (src/host/android_core.c on ember's prebuilt engine): ember's own
// hosts/hermes-start.ts, no app's modules, bundled and compiled to bytecode by `scripts/core.sh hermes`. An app's own
// entry (core/media-hermes.ts) calls startHermes with its modules. `@core/` is ember's client/core-ts/src.
import { takeClock } from "./clock.ts";
import { startHermes } from "@core/hosts/hermes-start.ts";

startHermes([]);
takeClock();
