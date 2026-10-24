// What is written, read as every client reads it, for a client that asks the core (`ref.at`, `ref.before`, `ref.marks`,
// `ref.pasted`, `paste.info`: the mbui app's composer; the web reads refLinks.ts and pasted.ts as they are).
import { markBefore, marksIn, pastedRefs, refAt } from "./refLinks.ts";
import { pasted } from "./pasted.ts";

/// What is written, read as every client reads it (`ref.*`, `paste.info`): the `@` words at the caret, the mark before
/// it, the marks in it, the chats' links in what is pasted, whether what is pasted goes as a file.
export function wordsAnswer(what: string, text: string, caret: number, here: string): unknown {
  switch (what) {
    case "ref.at": return { at: refAt(text, caret) };
    case "ref.before": return { at: markBefore(text, caret) };
    case "ref.marks": return { marks: marksIn(text) };
    case "ref.pasted": return { refs: pastedRefs(text, here) };
    default: return pasted(text);
  }
}
