// Case conversion without Java: Hermes on Android converts all but ASCII through Java (its platform unicode), which
// the app does not carry, and a call there aborts the whole app (2026-10-05: a search's words lowercased over a Chinese
// title). hermes-globals.ts puts these in place of String.prototype.toLowerCase/toUpperCase: ASCII and Latin-1 letters
// converted, everything else (CJK has no case) as it is; a string keeps its length, so ranges found in the converted
// one are the original's.

const ASCII = /^[\x00-\x7f]*$/;

export function lowerCase(s: string, ascii: (s: string) => string): string {
  if (ASCII.test(s)) return ascii(s);
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    out += (c >= 65 && c <= 90) || (c >= 0xc0 && c <= 0xde && c !== 0xd7) ? String.fromCharCode(c + 32) : s[i];
  }
  return out;
}

export function upperCase(s: string, ascii: (s: string) => string): string {
  if (ASCII.test(s)) return ascii(s);
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    out += (c >= 97 && c <= 122) || (c >= 0xe0 && c <= 0xfe && c !== 0xf7) ? String.fromCharCode(c - 32) : s[i];
  }
  return out;
}
