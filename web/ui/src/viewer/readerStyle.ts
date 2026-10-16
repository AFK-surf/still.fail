// How the reader lays text out (the page keeps it: ViewerHost's useReaderStyle / setReaderStyle), and its bounds.

/** The paper under the text. "follow" (from before): the light one, the app's dark being night. */
export type Paper = "follow" | "white" | "green" | "grey" | "night";

export interface ReaderStyle {
  /** The text's size (px), 12 to 32. */
  size: number;
  /** Line height as a multiple of the size, 1.2 to 2.4. */
  line: number;
  /** Room either side (px), 8 to 44. */
  margin: number;
  face: "serif" | "sans";
  /** Paragraphs start indented two characters. */
  indent: boolean;
  paper: Paper;
}

export const SIZES = { min: 12, max: 32 } as const;
export const LINES = { min: 1.2, max: 2.4 } as const;
export const MARGINS = { min: 8, max: 44 } as const;
