// The app's reader and player (@stillfail/ui viewer/): what they ask of the page told them (setViewerHost: a phone's
// sheets, the theme, a chat's Markdown, the reader's layout in the prefs), and they told to the file preview
// (FilePreview.tsx setWholeViewers), so a text and a video a chat has open in them as a station's file does. Imported
// by what starts the app (main.tsx, the site's demo, the stories), never by a page with no core (a published chat's).
import { createElement, Fragment } from "react";
import { setViewerHost } from "@stillfail/ui/viewer/host.ts";
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
});

setWholeViewers({ Reader, Player });
