// Words pasted into what is written: this many characters or more go as a file of their own (its card says what they
// begin with and how many there are); up to a bound, they can be put back as words. Read alike by every client.

/// Pasted at once, this many characters or more go as a file.
export const PASTE_THRESHOLD = 5_000;
/// A file of pasted words this long at most keeps its words, to be put back.
export const PASTE_RESTORE_LIMIT = 25_000;

export interface PastedInfo { preview: string; characters: number; text?: string }

/// What a file of pasted words says of them: the first line of what they begin with, how many characters, and the words
/// themselves while they are short enough to be put back.
export function pastedInfo(text: string): PastedInfo {
  return { preview: text.slice(0, 200).trim().split(/\r?\n/)[0] ?? "", characters: text.length,
    ...(text.length <= PASTE_RESTORE_LIMIT ? { text } : {}) };
}

/// Whether what is pasted goes as a file, and what that file says of it.
export function pasted(text: string): { file: boolean; info: PastedInfo | null } {
  return text.length >= PASTE_THRESHOLD ? { file: true, info: pastedInfo(text) } : { file: false, info: null };
}
