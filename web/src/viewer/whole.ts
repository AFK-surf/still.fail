// The app's reader and player (@stillfail/ui viewer/): what they ask of the page told them (setViewerHost: a phone's
// sheets, the theme, a chat's Markdown, the reader's layout in the prefs, the core reading a text for the reader), and
// they told to the file preview (FilePreview.tsx setWholeViewers), so a text and a sound a chat has open in them as a
// station's file does. Imported by what starts the app (main.tsx, the site's demo, the stories), never by a page with
// no core (a published chat's).
import { createElement, Fragment } from "react";
import { setViewerHost, type ReadBook } from "@stillfail/ui/viewer/host.ts";
import { Reader } from "@stillfail/ui/viewer/Reader.tsx";
import { Player } from "@stillfail/ui/viewer/Player.tsx";
import { setWholeViewers } from "../FilePreview.tsx";
import { Prose } from "../Prose.tsx";
import { useDark } from "../theme.ts";
import { useNarrow } from "../mobile/narrow.ts";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "../mobile/app.tsx";
import { Seg } from "../mobile/parts.tsx";
import { setReaderStyle, useReaderStyle } from "../drive/readerStyle.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import { core } from "../core/react.ts";

/** The phone app, where there is one (a viewer is drawn on a phone's page or a desktop's). */
function useAppSafe(): MobileApp | null {
  try { return useApp(); } catch { return null; }
}

setViewerHost({
  useNarrow,
  useDark,
  Markdown: Prose,
  markdownClass: conversationCss.markdown,
  useSheets: () => {
    const app = useAppSafe();
    return app && ((sheet) => app.sheet({
      height: sheet.height, ...(sheet.draggable ? { draggable: true } : {}),
      content: () => createElement(Fragment, null,
        createElement(SheetGrab),
        createElement(SheetHead, { title: sheet.title, trailing: sheet.trailing?.() }),
        sheet.body(() => app.sheet(null))),
    }));
  },
  Choice: ({ options, selected, onSelect }) => createElement(Seg, { options, selected, onSelect, fill: true }),
  useReaderStyle,
  setReaderStyle,
  // a text as the reader shows it, and words found in it: the core's (client/core-ts/src/reader.ts)
  readBook: async (text, markdown) => {
    const read = (await core().call("reader.book", { text, markdown, withText: true })) as Omit<ReadBook, "text"> & { text?: string };
    return { ...read, text: read.text ?? text };
  },
  searchBook: async (id, query) => ((await core().call("reader.search", { id, query })) as { at: number[] }).at,
});

setWholeViewers({ Reader, Player });
