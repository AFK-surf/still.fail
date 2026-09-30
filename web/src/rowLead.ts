import type { RowPictureSetting } from "./core/shapes.ts";
import { setPrefs, usePrefs } from "./prefs.ts";

/**
 * Whose pictures lead a chat's row: its agents' or its people's. 自动 by the scope: alone (a station's own page, a
 * workspace of one), the agents, the people beside them only when someone else is in the chat; with others, the people,
 * the agents beside them. Kept on this device (prefs.ts); the chats view says which leads (`leading`).
 */
export type RowPicture = RowPictureSetting;

export function useRowPicture(): [RowPicture, (value: RowPicture) => void] {
  return [usePrefs().rowPicture, (rowPicture) => setPrefs({ rowPicture })];
}
