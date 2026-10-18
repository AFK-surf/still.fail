// The agents' tools for the plugins of the person they work for (docs/client-plugins.md): plugin_list, plugin_save,
// plugin_delete. Whose plugins they are is the chat's starter's, never the agent's choice; a plugin's chat is one of
// this station's the same person started.
import { type Plugin, type PluginStore, MOST, pluginOf } from "../plugins/store.ts";
import type { Tool } from "./mcp.ts";

export type PluginToolsDeps = {
  plugins: PluginStore;
  /// The person session `key`'s chat is for (their email, lowercased) and its workspace; null when it has none.
  starter(key: string): { owner: string; ws: string } | null;
  /// Whether session `key` is there on this station.
  exists(key: string): boolean;
  /// Tell the owner's apps of a plugin as it is now, or that it is gone.
  told(ws: string, owner: string, p: Plugin | { id: string; gone: true }): void;
  now(): number;
};

export const PLUGIN_SAVE_DESCRIPTION =
  "Save a plugin for the person who started this chat: an entry their still.fail apps grow and what it does, made and changed by you, seen by nobody else. A share entry shows when they share something from another app (Android: the share list's \"still.fail 快捷\" entry; one plugin matching what is shared runs at once). Its action sends the whole shared text into a chat of this station as their message (send \"auto\", default) or puts it in that chat's composer (\"composer\"); that chat's agent then does the work (e.g. downloads the video with a skill). The chat is this one unless you name another session this person started here. Saving an existing id changes it. It reaches their devices within seconds; no app update is needed.";

export function pluginTools(d: PluginToolsDeps): Tool[] {
  const whose = (key: string) => {
    const s = d.starter(key);
    if (s === null) throw new Error("this chat was started by nobody the station knows (no email): it has no one to keep plugins for");
    return s;
  };
  const shown = (p: Plugin) => ({ id: p.id, name: p.name, entries: p.entries, action: p.action });
  return [
    {
      name: "plugin_list",
      description: "The plugins of the person who started this chat that this station keeps (docs: plugin_save).",
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
      run: async (key) => {
        const { owner, ws } = whose(key);
        const all = d.plugins.list(ws, owner);
        return all.length === 0 ? "No plugins here for whoever started this chat." : JSON.stringify(all.map(shown), null, 2);
      },
    },
    {
      name: "plugin_save",
      description: PLUGIN_SAVE_DESCRIPTION,
      inputSchema: {
        type: "object",
        properties: {
          id: { type: "string", description: "lowercase letters, digits and -, starting with a letter (e.g. douyin)" },
          name: { type: "string", description: "What the person sees, in their language, at most 40 characters (e.g. 抖音下载)." },
          entries: {
            type: "array",
            description: "Where it shows. So far only share entries: {kind: \"share\", match}: match is a JavaScript regular expression (case-insensitive) tested on the whole shared text; without it, anything shared matches.",
            items: { type: "object", properties: { kind: { type: "string", enum: ["share"] }, match: { type: "string" } }, required: ["kind"], additionalProperties: false },
          },
          action: {
            type: "object",
            description: "What a use does: the shared text sent into a chat of this station. Default: into this chat, sent at once.",
            properties: {
              kind: { type: "string", enum: ["chat"] },
              session: { type: "string", description: "Another session key on this station whose chat it goes to (one this person started); default this one." },
              send: { type: "string", enum: ["auto", "composer"], description: "auto: sent as their message at once (default); composer: put in the chat's composer for them to send." },
            },
            additionalProperties: false,
          },
        },
        required: ["id", "name", "entries"],
        additionalProperties: false,
      },
      run: async (key, args) => {
        const { owner, ws } = whose(key);
        const action = args.action !== null && typeof args.action === "object" ? (args.action as Record<string, unknown>) : {};
        const session = typeof action.session === "string" && action.session.trim() !== "" ? action.session.trim() : key;
        if (session !== key) {
          const other = d.exists(session) ? d.starter(session) : null;
          if (other === null || other.owner !== owner || other.ws !== ws) throw new Error(`no chat of this person's on this station is session ${session}`);
        }
        const p = pluginOf(args, session, Math.floor(d.now() / 1000));
        if (typeof p === "string") throw new Error(p);
        const known = d.plugins.get(ws, owner, p.id) !== null;
        if (!d.plugins.put(ws, owner, p)) throw new Error(`this person keeps ${MOST} plugins here already: delete one first`);
        d.told(ws, owner, p);
        return `${known ? "Changed" : "Saved"} plugin ${p.id} for ${owner}; their apps have it within seconds.\n${JSON.stringify(shown(p), null, 2)}`;
      },
    },
    {
      name: "plugin_delete",
      description: "Delete one of the plugins of the person who started this chat; their apps lose its entries.",
      inputSchema: { type: "object", properties: { id: { type: "string" } }, required: ["id"], additionalProperties: false },
      run: async (key, args) => {
        const { owner, ws } = whose(key);
        const id = typeof args.id === "string" ? args.id.trim() : "";
        if (!d.plugins.delete(ws, owner, id)) throw new Error(`no plugin ${id} of this person's here`);
        d.told(ws, owner, { id, gone: true });
        return `Deleted plugin ${id}.`;
      },
    },
  ];
}
