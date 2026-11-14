// adb_devices (the Rust station's adb.rs): the Android phones people shared with this station's agents. The phones are the
// station process's (its adb tunnels over the mesh, not ported yet): it gives them here as `phones`; until it does,
// there are none, as with the Rust station before it registered its lister.
import type { Tool } from "../tools/mcp.ts";
import { type Display, IDLE_MS } from "./displays.ts";
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
    'Use a phone with `adb -s <serial> …` (adb is this machine\'s). adb "connected" is ready; "unpaired" means its person still has to pair it with this station, on its 共享调试 page in the still.fail app on the phone (where a link to it opens); after `adb kill-server` run `adb connect <serial>` again. A phone is its owner\'s: use it for what they asked, and it goes when they stop sharing it. ';
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
    "Ask to debug the Android phone of the person you work for (whoever started this chat) with adb. A card in your chat says your reason; they approve it in the still.fail app for this chat, for a time, or refuse it. It does not wait: you are told in this session when it is decided, and only a grant counts, not a yes written in the chat. Called again once granted, it says how the phone is reached now (its adb server and serial, this chat's alone). Skill stillfail-jobs (Devices) says more.",
  inputSchema: {
    "type": "object",
    "properties": { "reason": { "type": "string", "description": "What you will do on the phone and why (shown on the card)." }, "reask": { "type": "boolean", "description": "The existing request is still needed but its card is no longer pending: post a new card for the same request." }, "done": { "type": "boolean", "description": "Hand the phone back: end this chat's grant (or its request still pending). reason is not needed with it." } },
    "additionalProperties": false
  },
};

export const PHONE_SEND = {
  name: "phone_send",
  description:
    "Put a file of this machine on the phone granted to this chat (phone_use), much faster and surer than adb push over the phone's link: the phone fetches it the way it downloads a chat's file. Answers its path on the phone, in the app's own folder, which this chat's adb shell reads; pm cannot read there, so install an APK from a copy: adb … shell 'cp <path> /data/local/tmp/a.apk && pm install -r /data/local/tmp/a.apk'. Cut short (the link went), call it again: it goes on from what the phone has. Waits until the file is there.",
  inputSchema: {
    "type": "object",
    "properties": { "path": { "type": "string", "description": "The file: an absolute path, or one in your workspace." } },
    "required": ["path"],
    "additionalProperties": false
  },
};

/// How a granted phone is reached now: its owner's phones lent here (`phones`), each in the grant's adb server (`port`).
/// `gone`: when the phone was last offered no longer and why, if it was since the station started.
/// `display`: the chat's own screen on the phone (displays.ts), or why it could not be made; none while the phone is not
/// connected.
export function reached(serials: { serial: string; adb: string; device: string }[], port: number | null, gone?: { at: number; ended: string } | null, display?: Display | { failed: string } | null): string {
  if (serials.length === 0 || port === null) {
    const since = gone ? ` It stopped being offered ${new Date(gone.at).toISOString()} (${gone.ended === "stopped" ? "its app ended the share: its 共享调试 switch turned off, say" : `its link went: ${gone.ended}`}).` : "";
    return `Granted, but the phone is not lent to this station right now.${since} Its app lends it by itself while a grant is live and its 共享调试 switch is on (started again with the phone, kept up in the background); call phone_use again in a minute. Only if it stays away, ask its person to turn on 共享调试 in the app's settings on the phone (设置 › 共享调试), saying what this says.`;
  }
  const lines = serials.map((p) => `- ${p.device || "phone"}: adb -P ${port} -s ${p.serial} … (adb ${p.adb})`);
  return [
    "Granted. Use this chat's adb server, with -P on every adb command (the station's own adb, 5037, does not have the phone; another server is turned away; run from under this session or its own directory, others are refused):",
    ...lines,
    "To put a file on the phone, use phone_send, not adb push (much slower over the phone's link, begun again from nothing when it breaks).",
    'adb "connected" is ready; "unpaired": the phone needs pairing, and its card in your chat shows its person how (a card under it, in the still.fail app on the phone): leave it to the card, do not send them to the phone\'s settings, and you are told in this session when it connects. Never adb kill-server on it. A phone is its owner\'s: use it for what they asked.',
    ...(display ? ["", displayed(display)] : []),
  ].join("\n");
}

/// How the agent works on the chat's own screen of the phone (or why there is none).
export function displayed(display: Display | { failed: string }): string {
  if ("failed" in display)
    return `This chat's own screen on the phone could not be made (${display.failed}), so only the phone's own screen is there, which its person may be using: ask them in the chat before you operate it (installing, reading logs and other commands that touch no screen need no asking). Call phone_use again to try again.`;
  return [
    `This chat has a screen of its own on the phone: display ${display.id} (${display.width}x${display.height}, density ${display.density}), apart from the phone's own screen, which its person keeps using. Work on it, not on theirs, unless they ask:`,
    `- Start an app on it: \`adb … shell am start --display ${display.id} -n <package>/<activity>\` (or \`-a android.intent.action.MAIN -c android.intent.category.LAUNCHER <package>\`; \`cmd package resolve-activity --brief <package>\` names its activity). An app is on one screen at a time: one the person has open moves over, so prefer apps they are not using.`,
    `- Touch and type there: \`adb … shell input -d ${display.id} tap <x> <y>\`, \`swipe\`, \`text\`, \`keyevent BACK\` (it has no navigation bar and shows no keyboard: \`text\` types into the field it focused, ASCII only).`,
    `- Its picture: \`adb … exec-out screencap -d ${display.surface} -p > shot.png\` (the id screencap takes for it), then look at the file.`,
    `It closes with the apps on it when you hand the phone back (phone_use done: true, do that once finished), when the grant ends, or after ${IDLE_MS / 60_000} minutes of no adb use; phone_use makes a new one then. While it is up, the phone's notification names this chat.`,
  ].join("\n");
}

/// phone_use over the grants (`grants`), and how a granted phone is reached (`reach`).
export function phoneTools(grants: PhoneGrants, reach: (owner: string, grant: string) => Promise<string>): Tool[] {
  return [
    {
      ...PHONE_USE,
      run: async (session, args, signal) => {
        if (args.done === true) {
          const ended = grants.release(session);
          return ended.length === 0 ? "This chat holds no phone grant or request: nothing to hand back." : `Handed back: ${ended.map((r) => `${r.id} (${r.owner}'s phone)`).join(", ")}. adb no longer reaches it; ask with phone_use again if you need it later.`;
        }
        const reason = typeof args.reason === "string" ? args.reason : "";
        let r = await grants.ask(session, reason, args.reask === true, signal);
        if (r.status === "pending") {
          const pending = await grants.cardPending(r, signal);
          r = grants.get(r.id) ?? r;
          if (r.status === "pending" && pending === false) return `The phone request ${r.id} is still pending, but its card is no longer pending. If it is still needed, call phone_use again with the same reason and reask: true.`;
        }
        if (r.status === "granted") return await reach(r.owner, r.id);
        return said(r);
      },
    },
  ];
}
