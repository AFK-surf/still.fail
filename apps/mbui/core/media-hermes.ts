// The media app's core in Hermes: still.fail's core with the media module (ember media/core), for
// `ENTRY=core/media-hermes.ts scripts/core.sh hermes`. `@ember/` is the ember checkout.
import { startHermes } from "@core/hosts/hermes-start.ts";
import { media } from "@ember/media/core/media.ts";

startHermes([media]);
