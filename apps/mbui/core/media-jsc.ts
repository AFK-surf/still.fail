// The media app's core in JavaScriptCore: still.fail's core with the media module (ember media/core), bundled by
// `ENTRY=core/media-jsc.ts scripts/core.sh bundle`. `@ember/` is the ember checkout.
import { startJsc } from "./jsc-start.ts";
import { media } from "@ember/media/core/media.ts";

startJsc([media]);
