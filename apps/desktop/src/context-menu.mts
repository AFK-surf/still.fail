// What a right-click in a window of the app offers (main.ts, showContextMenu), with nothing of Electron in it
// (test/desktop-context-menu.test.ts runs it). An .mts, as moves.mts is. Electron shows no menu of its own on a
// right-click, as a browser does: without this one an image, a link or the words selected could not be copied with the
// mouse. A page with a menu of its own there (a chat's row in the sidebar, a message in the phone's layout) cancels the
// right-click, and none is asked for.

/** What was right-clicked: the part of Electron's ContextMenuParams the menu reads. */
export interface Clicked {
  linkURL: string;
  srcURL: string;
  mediaType: string;
  hasImageContents: boolean;
  selectionText: string;
  isEditable: boolean;
  editFlags: { canCut: boolean; canCopy: boolean; canPaste: boolean; canSelectAll: boolean };
}

/** What an item does: an edit of the page's, the image under the pointer copied, words to the clipboard, a page in the system browser. */
export type Action =
  | { do: "edit"; command: "cut" | "copy" | "paste" | "selectAll" }
  | { do: "copyImage" }
  | { do: "copyText"; text: string }
  | { do: "open"; url: string };

/** An item: its words (a key of client/i18n/catalog/<lang>/desktop.json), what it does and whether it can now; null is a line between groups. */
export type Item = { key: string; action: Action; enabled: boolean } | null;

const item = (key: string, action: Action, enabled = true): Exclude<Item, null> => ({ key, action, enabled });
const edit = (command: "cut" | "copy" | "paste" | "selectAll"): Action => ({ do: "edit", command });
/** A page on the web, which the system browser opens and others can open too. */
const web = (url: string) => /^https?:\/\//i.test(url);

/**
 * The menu for what was right-clicked: the link's items, the image's, then the words' (a field's editing; elsewhere
 * copying what is selected), a line between them. None for nothing of these (the page's background): no menu then.
 * `app` is the origin the page is served from and `cloud` still.fail cloud's: a link to a page of the app is copied as
 * that page on the web (the cloud serves the same pages at the same paths), and is not one for the system browser.
 */
export function contextMenu(clicked: Clicked, { app, cloud }: { app: string; cloud: string }): Item[] {
  const groups: Exclude<Item, null>[][] = [];
  const link = clicked.linkURL;
  if (link.startsWith(`${app}/`)) groups.push([item("desktop.contextMenu.copyLink", { do: "copyText", text: cloud + link.slice(app.length) })]);
  else if (web(link)) groups.push([item("desktop.contextMenu.openLink", { do: "open", url: link }), item("desktop.contextMenu.copyLink", { do: "copyText", text: link })]);
  if (clicked.mediaType === "image") {
    groups.push([
      // One that has not loaded (or failed to) has nothing to copy yet.
      item("desktop.contextMenu.copyImage", { do: "copyImage" }, clicked.hasImageContents),
      // A chat's images are the page's own (blob:), an address nothing outside it can read.
      ...(web(clicked.srcURL) ? [item("desktop.contextMenu.copyImageAddress", { do: "copyText", text: clicked.srcURL })] : []),
    ]);
  }
  const { canCut, canCopy, canPaste, canSelectAll } = clicked.editFlags;
  if (clicked.isEditable) {
    groups.push([
      item("desktop.contextMenu.cut", edit("cut"), canCut),
      item("desktop.contextMenu.copy", edit("copy"), canCopy),
      item("desktop.contextMenu.paste", edit("paste"), canPaste),
      item("desktop.contextMenu.selectAll", edit("selectAll"), canSelectAll),
    ]);
  } else if (clicked.selectionText.trim()) {
    groups.push([item("desktop.contextMenu.copy", edit("copy"))]);
  }
  return groups.flatMap((group, i) => (i === 0 ? group : [null, ...group]));
}
