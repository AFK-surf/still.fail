// The media app's core in Hermes (Android): the platform with the media module (client/core-ts hosts/hermes-start.ts),
// bundled by `node client/core-ts/scripts/hermes-bundle.ts --entry media/core/hermes.ts <out.js> [<out.hbc>]`.
import { startHermes } from "../../client/core-ts/src/hosts/hermes-start.ts";
import { media } from "./media.ts";

startHermes([media]);
