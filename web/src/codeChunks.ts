import { runsOf } from "../../client/core-ts/src/highlight.ts";

export type CodeChunk = { text: string; runs: [text: string, scope: string][] };

/** Keep the entire source in the DOM, but make its coloured spans in small groups as they approach the screen.
 * Split by UTF-16 offsets as ink does; preserve every space and newline, including a final newline. */
export function codeChunks(text: string, ink: string): CodeChunk[] {
  const chunks: CodeChunk[] = [];
  let chunk: CodeChunk = { text: "", runs: [] };
  let lines = 0;
  for (const [words, scope] of runsOf(text, ink)) {
    let from = 0;
    while (from < words.length) {
      const newline = words.indexOf("\n", from);
      let end = Math.min(newline < 0 ? words.length : newline + 1, from + 4000 - chunk.text.length);
      if (end < words.length && /[\uD800-\uDBFF]/.test(words[end - 1]!) && /[\uDC00-\uDFFF]/.test(words[end]!)) end++;
      const part = words.slice(from, end);
      chunk.text += part;
      const previous = chunk.runs.at(-1);
      if (previous?.[1] === scope) previous[0] += part;
      else chunk.runs.push([part, scope]);
      if (part.endsWith("\n")) lines++;
      from = end;
      if (lines >= 40 || chunk.text.length >= 4000) {
        chunks.push(chunk);
        chunk = { text: "", runs: [] };
        lines = 0;
      }
    }
  }
  if (chunk.text) chunks.push(chunk);
  return chunks;
}
