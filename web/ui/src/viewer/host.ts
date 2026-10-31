// What a viewer (Reader.tsx, Player.tsx) asks of the page it is drawn on, told once as the page starts (setViewerHost):
// whether it is a phone's (narrow) and dark, how Markdown is drawn, a phone's sheets, where the reader's layout is
// kept, and the page's core reading a text for the reader. The app tells its own (web/src/viewer/whole.ts); with none told, a wide page's, light, its Markdown as text.
import { createElement, Fragment, type ComponentType, type ReactNode } from "react";
import type { ReaderStyle } from "./readerStyle.ts";

/** A chapter heading: its words and where it starts in the text. */
export interface Chapter { title: string; offset: number }

/** A text as the core reads it for a reader (client/core-ts/src/reader.ts `reader.book`): its id (to find words in it
 *  with), the text as joined (a hard-wrapped novel's lines joined into paragraphs), the column it was wrapped at (0:
 *  none), its chapters and where its heading lines start. */
export interface ReadBook { id: number; text: string; wrapped: number; chapters: Chapter[]; heads: number[] }

/** A phone's sheet over the page: how much of it it takes, whether its grabber drags it, its head, and what is in it. */
export interface ViewerSheet {
  height: number;
  draggable?: boolean;
  title: string;
  trailing?: (() => ReactNode) | undefined;
  body: (close: () => void) => ReactNode;
}

export interface ViewerHost {
  useNarrow(): boolean;
  useDark(): boolean;
  /** Markdown drawn (a chat's way), in an element of `markdownClass`. */
  Markdown: ComponentType<{ children: string }>;
  markdownClass: string;
  /** Opens a phone's sheet (null where there are none: the panels are drawn beside the text). A hook. */
  useSheets(): ((sheet: ViewerSheet) => void) | null;
  /** A phone's choice of a few, side by side. */
  Choice: ComponentType<{ options: string[]; selected: number; onSelect: (i: number) => void }>;
  /** How the reader lays text out on this device: read (a hook), and changed a setting or a few at a time. */
  useReaderStyle(): ReaderStyle;
  setReaderStyle(change: Partial<ReaderStyle>): void;
  /** A text (a file decoded) as a reader shows it, read by the page's core (`reader.book`); `markdown`: a Markdown file's. */
  readBook(text: string, markdown: boolean): Promise<ReadBook>;
  /** Where `query` is in a book the core read (`reader.search`). */
  searchBook(id: number, query: string): Promise<number[]>;
}

// The core's defaults (client/core-ts/src/prefs.ts readerOf).
let style: ReaderStyle = { size: 16, line: 1.7, margin: 22, face: "sans", indent: true, paper: "follow" };

let host: ViewerHost = {
  useNarrow: () => false,
  useDark: () => false,
  Markdown: ({ children }) => createElement(Fragment, null, children),
  markdownClass: "",
  useSheets: () => null,
  Choice: () => null,
  useReaderStyle: () => style,
  setReaderStyle: (change) => { style = { ...style, ...change }; },
  // (no core: the text as it is, nothing found in it)
  readBook: (text) => Promise.resolve({ id: 0, text, wrapped: 0, chapters: [], heads: [] }),
  searchBook: () => Promise.resolve([]),
};

export function setViewerHost(given: ViewerHost): void {
  host = given;
}

export function viewerHost(): ViewerHost {
  return host;
}
