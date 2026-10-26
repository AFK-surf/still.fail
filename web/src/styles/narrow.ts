// For styles of what stands right in a narrow page (pages.css.ts pageNarrow): beside them, a style file exports no functions.
import { boneBody, wait } from "@stillfail/ui/waiting.css.ts";
import { pageNarrow } from "./pages.css.ts";

/** What stands right in a narrow page, `what`: and what a wait there holds in its bones, which stands where it will
 * (@stillfail/ui waiting.tsx Bones). */
export const inNarrow = (what: string): string => `${pageNarrow} > ${what}, ${pageNarrow} > ${wait} ${boneBody} > ${what}`;
