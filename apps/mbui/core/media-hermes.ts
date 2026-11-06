// The media app's core in Hermes: still.fail's core with the media module (still.fail media/core), for
// `ENTRY=core/media-hermes.ts scripts/core.sh hermes`. `@stillfail/` is the still.fail checkout.
import { takeClock } from "./clock.ts";
import { startHermes } from "@core/hosts/hermes-start.ts";
import { media } from "@stillfail/media/core/media.ts";

startHermes([media]);
takeClock();
