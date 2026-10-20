/** Large pastes are real UTF-8 attachments; restoring is bounded so the editor stays responsive. */
export const PASTE_THRESHOLD = 5_000;
export const PASTE_RESTORE_LIMIT = 25_000;
export interface PastedInfo { preview: string; characters: number; text?: string }

export function pastedInfo(text: string): PastedInfo {
  return { preview: text.slice(0, 200).trim().split(/\r?\n/)[0] ?? "", characters: text.length,
    ...(text.length <= PASTE_RESTORE_LIMIT ? { text } : {}) };
}

export function makePastedFile(text: string): File {
  return new File([text], `pasted-text-${crypto.randomUUID()}.txt`, { type: "text/plain;charset=utf-8" });
}
