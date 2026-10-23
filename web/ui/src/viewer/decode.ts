// A file's bytes as text, decoded here (the browser's own tables: a novel in GB18030): by their byte order mark, else
// UTF-8 when they are, else GB18030. What a reader does with the text (joining a hard-wrapped novel, its chapters,
// finding words in it) is the core's (client/core-ts/src/reader.ts), asked through the page (host.ts readBook).

/** Bytes as text: by their byte order mark, else UTF-8 when they are, else GB18030. `cut`: these are a file's front
 *  only, so a character cut at their end is no sign they are not UTF-8. */
export function decodeText(bytes: Uint8Array, cut = false): { text: string; encoding: string } {
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) return { text: new TextDecoder("utf-8").decode(bytes.subarray(3)), encoding: "UTF-8" };
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) return { text: new TextDecoder("utf-16le").decode(bytes.subarray(2)), encoding: "UTF-16LE" };
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) return { text: new TextDecoder("utf-16be").decode(bytes.subarray(2)), encoding: "UTF-16BE" };
  const strict = new TextDecoder("utf-8", { fatal: true });
  try {
    return { text: strict.decode(bytes, { stream: cut }), encoding: "UTF-8" };
  } catch {
    // A file whose own last character is cut short (half copied) is still UTF-8.
    try {
      return { text: strict.decode(bytes.subarray(0, tailStart(bytes))), encoding: "UTF-8" };
    } catch {
      // not UTF-8
    }
  }
  try {
    return { text: new TextDecoder("gb18030").decode(bytes), encoding: "GB18030" };
  } catch {
    return { text: new TextDecoder("latin1").decode(bytes), encoding: "ISO-8859-1" };
  }
}

/** Where a UTF-8 character cut at the end of `bytes` starts (its length when none is). */
function tailStart(bytes: Uint8Array): number {
  for (let i = bytes.length - 1, n = 0; i >= 0 && n < 4; i--, n++) {
    const b = bytes[i]!;
    if ((b & 0xc0) === 0x80) continue;
    const need = b >= 0xf0 ? 4 : b >= 0xe0 ? 3 : b >= 0xc0 ? 2 : 1;
    return n + 1 < need ? i : bytes.length;
  }
  return bytes.length;
}
