// device_list and device_use: how a chat's agent finds the workspace's devices (devices/module.ts) and asks for one.
import type { DeviceEntry } from "../services.ts";
import type { Tool } from "../tools/mcp.ts";

export const DEVICE_LIST = {
  name: "device_list",
  description:
    "List the devices of this workspace an agent can use: phones, boards, cameras, routers, printers, serial ports, anything that runs no station but is attached to one (on its USB or its network) or lent by its person's still.fail app (an Android phone with 共享调试 on). Each says its kind (adb, tcp, serial), what it is reached at there, where it is attached, whose it is, whether this chat may use it now (thisChat) and who has access. A device attached to a whole station is open to every chat; one on a station that only runs tasks, and a person's phone, need their owner's approval (device_use).",
  inputSchema: { type: "object", properties: {}, additionalProperties: false },
};

export const DEVICE_USE = {
  name: "device_use",
  description:
    "Use a device from device_list. One open to this chat is put at once on a port of 127.0.0.1 here, which only this chat's processes can connect to; one that needs its owner's approval is asked for with a card in your chat, which its owner (not necessarily the person you work for) approves for this chat for a time, or refuses. Asking does not wait: you are told in this session when it is decided, and only a grant counts, not a yes written in the chat. Once granted, call this again: it says where the device is and how it is used. Skill stillfail-jobs (Devices) says more.",
  inputSchema: {
    type: "object",
    properties: {
      device: { type: "string", description: "The device: its name from device_list (any case), or its id; a person's email for their Android phone (lent once they approve). None: the phone of the person you work for." },
      reason: { type: "string", description: "What you will do with it and why (shown on the card to its owner)." },
      timeout: {
        type: "object",
        description: "How long the grant should last (the owner may choose another): idle (ends once this chat has not used the device that long) or fixed, in whole minutes from 1 minute to 30 days. Default: idle, 1 hour.",
        properties: { kind: { enum: ["idle", "fixed"] }, seconds: { type: "integer" } },
        required: ["kind", "seconds"],
        additionalProperties: false,
      },
      done: { type: "boolean", description: "Hand it back: end this chat's grant of it (or its request still pending), and close its port here. With no device named, every one this chat holds." },
    },
    additionalProperties: false,
  },
};

export type DeviceTools = {
  list(session: string): Promise<DeviceEntry[]>;
  use(session: string, device: string, reason: string, timeout: unknown, signal?: AbortSignal): Promise<string>;
  done(session: string, device: string): Promise<string>;
};

export function deviceTools(d: DeviceTools): Tool[] {
  return [
    {
      ...DEVICE_LIST,
      run: async (session) => {
        const all = await d.list(session);
        if (all.length === 0) return "No device is attached to this workspace's stations, and no phone is lent to this station. A member adds one on a station's page in the still.fail app (添加设备); a person lends their Android phone by turning on 共享调试 in the app on it.";
        return JSON.stringify(all, null, 2);
      },
    },
    {
      ...DEVICE_USE,
      run: async (session, args, signal) => {
        const device = typeof args.device === "string" ? args.device.trim() : "";
        if (args.done === true) return d.done(session, device);
        return d.use(session, device, typeof args.reason === "string" ? args.reason : "", args.timeout, signal);
      },
    },
  ];
}

/// Where a device is reached here once forwarded (`port` on 127.0.0.1), in words for its kind.
export function reachedAt(e: { name: string; kind: string; target: string; baud?: number }, port: number): string {
  switch (e.kind) {
    case "adb":
      return `${e.name} is reached here through the adb server of the machine it is on: \`adb -P ${port} -s ${e.target} …\` (-P on every adb command; never adb kill-server on it). Only this chat's processes connect.`;
    case "serial":
      return `${e.name} (serial ${e.target}, ${e.baud ?? 115200} baud, set raw there) is at 127.0.0.1:${port}: its bytes both ways, e.g. \`socat - TCP:127.0.0.1:${port}\` or a socket in a script. Only this chat's processes connect.`;
    default:
      return `${e.name} (${e.target}) is at 127.0.0.1:${port}: connect to it there as you would to ${e.target} (http://127.0.0.1:${port}/, ssh -p ${port} …). Only this chat's processes connect.`;
  }
}
