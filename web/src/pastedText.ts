/** Large pastes are real UTF-8 attachments; what they say of themselves is the core's (client/core-ts/src/pasted.ts). */
export { PASTE_RESTORE_LIMIT, PASTE_THRESHOLD, pastedInfo, type PastedInfo } from "../../client/core-ts/src/pasted.ts";

export function makePastedFile(text: string): File {
  return new File([text], `pasted-text-${crypto.randomUUID()}.txt`, { type: "text/plain;charset=utf-8" });
}
