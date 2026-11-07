// Made-up data for what a page shows while it is read the first time, drawn in its bones by the parts that draw the
// real one (@stillfail/ui waiting.tsx Bones; docs/ui-panels.md 等待): only how long its words are is seen, as a bar.
import { sampleWords } from "@stillfail/ui/waiting.tsx";
import type { Stamp } from "./core/shapes.ts";

export { sampleWords };

/** A time said in `n` letters. */
export const sampleStamp = (n = 3): Stamp => ({ at: 0, ago: sampleWords(n), full: sampleWords(n), until: sampleWords(n), past: true });
