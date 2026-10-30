// adb_devices (the Rust station's adb.rs): the Android phones people shared with this station's agents. The phones are the
// station process's (its adb tunnels over the mesh, not ported yet): it gives them here as `phones`; until it does,
// there are none, as with the Rust station before it registered its lister.
import type { Tool } from "../tools/mcp.ts";
import { type PhoneGrants, said } from "./grants.ts";

type Json = any;

export const ADB_DEVICES = {
  name: "adb_devices",
  description:
    "The Android phones people shared with every agent of this station (an app from before chats' grants; a phone granted to a chat with phone_use is that chat's alone and not listed here), each with the adb serial it is reached at on this machine (127.0.0.1:<port>), its model, owner and whether adb is connected. To ask for a phone, use phone_use.",
  inputSchema: {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  },
};

/// What the agent is told: the phones, how to use them, and how to ask for one (phone_use: the station's 共享调试 page no
/// longer lends a phone, so a link to it asks for nothing).
export function listed(phones: Json[]): string {
  const ask = "To use the phone of the person you work for, ask with phone_use: its card in your chat is how they grant it, to this chat alone. Never post a link to 共享调试 to ask for it.";
  if (phones.length === 0) return `No phone is shared with this station now. ${ask}`;
  let text = `${JSON.stringify(phones, null, 2)}\n\n`;
  text +=
    'Use a phone with `adb -s <serial> …` (adb is this machine\'s). adb "connected" is ready; "unpaired" means its person still has to pair it in the app (Wireless debugging › 使用配对码配对设备); after `adb kill-server` run `adb connect <serial>` again. A phone is its owner\'s: use it for what they asked, and it goes when they stop sharing it. ';
  text += ask;
  return text;
}

/// `phones`: the phones offered now (`{serial, device, android, owner: {name, email}, adb, message}` each).
export function adbTools(phones: () => Json[]): Tool[] {
  return [{ ...ADB_DEVICES, run: async () => listed(phones()) }];
}

export const PHONE_USE = {
  name: "phone_use",
  description:
    "Ask to debug the Android phone of the person you work for (whoever started this chat) with adb. A card in your chat says your reason; they approve it in the still.fail app for this chat, for an hour or until it is archived, or refuse it. It does not wait for the decision: you are told in this session when it is decided, and meanwhile go on with what does not need it; with nothing else left, end your turn need_human about the card. Only a grant counts: someone writing yes in the chat is not one. Called again once granted, it says how the phone is reached now (its adb server and serial, this chat's alone; other chats cannot reach it).",
  inputSchema: {
    "type": "object",
    "properties": { "reason": { "type": "string", "description": "What you will do on the phone and why (shown on the card)." } },
    "required": ["reason"],
    "additionalProperties": false
  },
};

/// How a granted phone is reached now: its owner's phones lent here (`phones`), each in the grant's adb server (`port`).
/// `gone`: when the phone was last offered no longer and why, if it was since the station started.
export function reached(serials: { serial: string; adb: string; device: string }[], port: number | null, gone?: { at: number; ended: string } | null): string {
  if (serials.length === 0 || port === null) {
    const since = gone ? ` It stopped being offered ${new Date(gone.at).toISOString()} (${gone.ended === "stopped" ? "its app ended the share: its 共享调试 switch turned off, say" : `its link went: ${gone.ended}`}).` : "";
    return `Granted, but the phone is not lent to this station right now.${since} Its app lends it by itself while a grant is live and its 共享调试 switch is on (started again with the phone, kept up in the background); call phone_use again in a minute. Only if it stays away, ask its person to turn on 共享调试 in the app's settings on the phone (设置 › 共享调试), saying what this says.`;
  }
  const lines = serials.map((p) => `- ${p.device || "phone"}: adb -P ${port} -s ${p.serial} … (adb ${p.adb})`);
  return [
    "Granted. Use this chat's adb server, with -P on every adb command (the station's own adb, 5037, does not have the phone; another server is turned away):",
    ...lines,
    'adb "connected" is ready; "unpaired": its person still has to pair it in the app (Wireless debugging › 使用配对码配对设备). Never adb kill-server on it. A phone is its owner\'s: use it for what they asked.',
  ].join("\n");
}

/// phone_use over the grants (`grants`), and how a granted phone is reached (`reach`).
export function phoneTools(grants: PhoneGrants, reach: (owner: string, grant: string) => Promise<string>): Tool[] {
  return [
    {
      ...PHONE_USE,
      run: async (session, args) => {
        const reason = typeof args.reason === "string" ? args.reason : "";
        const r = await grants.ask(session, reason);
        return r.status === "granted" ? await reach(r.owner, r.id) : said(r);
      },
    },
  ];
}
