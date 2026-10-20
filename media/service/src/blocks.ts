// A chapter's text as the readers get it (docs/media-service.md): blocks, and how a place in a chapter is counted.
//
// Offsets: a chapter is read as the concatenation of its blocks with nothing between them. A `p` counts the UTF-16
// length of its text (a run's `text` only: a ruby's reading is not counted, its base is); an `h` its text; an `img` and
// an `hr` count 1 each (as if they were one U+FFFC), so every block starts at an offset of its own. `chars` of a
// chapter is the sum; a place's `offset`, a note's `start` and `end` are offsets in that.

/// A piece of a paragraph with a style: bold, italic, a link (as the book had it), a ruby's reading over `text`.
export type Run = { text: string; b?: true; i?: true; href?: string; ruby?: string };

export type Block =
  | { t: "p"; text: string }
  | { t: "p"; runs: Run[] }
  | { t: "h"; level: number; text: string }
  | { t: "img"; ref: string; w?: number; h?: number }
  | { t: "hr" };

/// A chapter as an import makes it, before it is stored.
export type Chapter = { title: string; level: number; blocks: Block[] };

/// An image of a book: its bytes, and its type as stored and served.
export type Image = { type: string; bytes: Uint8Array };

/// A book as an import makes it: `cover` names one of `images` (by ref).
export type Parsed = { title: string; author: string; format: "epub" | "txt"; cover: string | null; chapters: Chapter[]; images: Map<string, Image> };

/// An entry of a book's table of contents: one per chapter.
export type TocEntry = { index: number; title: string; level: number; chars: number };

/// How many offsets a block takes (above).
export function blockChars(b: Block): number {
  switch (b.t) {
    case "p":
      return "text" in b ? b.text.length : b.runs.reduce((n, r) => n + r.text.length, 0);
    case "h":
      return b.text.length;
    case "img":
    case "hr":
      return 1;
  }
}

export function chapterChars(blocks: Block[]): number {
  return blocks.reduce((n, b) => n + blockChars(b), 0);
}
