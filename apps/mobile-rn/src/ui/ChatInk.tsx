// The chats' own colours and a station's name, as the chat draws them and the pages beside it say them; here so
// that those pages need not depend on the chat (2026-10-17). (The Android app's ui/ChatInk.kt.)
//
// What Compose reads of the palette (`C.dark`) is given here: these take the palette in use (`useC()`).
import { createContext } from "react";
import type { WorkspaceView } from "../data/Accounts";
import { Topics, rememberTopic } from "../data/Topics";
import type { StillFailColors } from "./Theme";

/** The station part of an address ("ws/studio" → "studio"). */
export function stationName(address: string): string {
  const at = address.indexOf("/");
  return at < 0 ? address : address.substring(at + 1);
}

/** A station's name in its workspace. */
export function rememberStationName(station: string): string {
  const at = station.indexOf("/");
  const ws = rememberTopic<WorkspaceView>(Topics.workspace(at < 0 ? station : station.substring(0, at)));
  return ws.value?.stations?.find((s) => s.id === stationName(station))?.name ?? stationName(station);
}

/**
 * The chat's own colours, as web mobile draws its messages: with the wide screen's tokens (web/src/styles/global.css.ts,
 * inside mobile/styles/root.css.ts → wide), over the phone's paper; neutral is the phone's bubble (--m-bubble, Theme.kt bubble).
 */
export interface ChatInk {
  text: string; muted: string; subtle: string; neutral: string; name: string; card: string;
  accent: string; amber: string; canvas: string;
}
const LightInk: ChatInk = {
  text: "#24272B", muted: "#646970", subtle: "#73787D", neutral: "#E8E4DC", name: "#A23203",
  card: "#F6F6F7", accent: "#EF6A3C", amber: "#7F5306", canvas: "#FFFFFF",
};
const DarkInk: ChatInk = {
  text: "#E9E9EA", muted: "#A3A5A9", subtle: "#8C8F94", neutral: "#313237", name: "#FC9B6F",
  card: "#27282B", accent: "#F57E4D", amber: "#E6B55D", canvas: "#1F2023",
};

export function chatInk(C: StillFailColors): ChatInk { return C.dark ? DarkInk : LightInk; }
export function chatMuted(C: StillFailColors): string { return chatInk(C).muted; }
export function chatSubtle(C: StillFailColors): string { return chatInk(C).subtle; }
/** A quote's card: the ink faint over the canvas. */
export function quoteGround(C: StillFailColors): string { return chatInk(C).card; }

/** Whether the screen is wide (App.kt Pages): Home leaves its new-chat button to WideCorners then, the composer room for Recent. */
export const LocalWide = createContext(false);
