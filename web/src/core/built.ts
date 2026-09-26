// Which build of the web core this is: the later of the page's build and the wasm's (client/wasm/build.sh writes
// pkg/built.js). The worker is named by it, so a page on a newer build starts its own worker, and the older retires
// (worker.ts); in development, where the page's build stays as the server started, a rebuilt core still takes over.
import { BUILT_AT as CORE_BUILT_AT } from "./pkg/built.js";

declare const __BUILT_AT__: number;

export const BUILT_AT = Math.max(__BUILT_AT__, CORE_BUILT_AT);
