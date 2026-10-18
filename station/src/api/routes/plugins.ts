// A person's plugins as their apps read them (docs/client-plugins.md): GET /plugins (the asker's own, in the
// workspace they ask from) and DELETE /plugins/<id> (one of theirs gone; a read-only member may too). Their agent
// writes them (tools/plugins.ts).
import type { Route } from "../admin.ts";
import type { Answer } from "../request.ts";
import { json, percentDecode } from "../request.ts";
import type { PluginStore } from "../../plugins/store.ts";

export type PluginRoutesDeps = {
  plugins: PluginStore;
  /// Tell `owner`'s apps in `ws` that their plugin `id` is gone.
  gone(ws: string, owner: string, id: string): void;
};

const refuse = (status: number, code: string, error: string): Answer => json(status, JSON.stringify({ error, code }));

export const PLUGIN_PATH = /^\/plugins\/([^/]+)$/;

export const routes = ({ plugins, gone }: PluginRoutesDeps): Route[] => [
  {
    method: "GET",
    pattern: /^\/plugins$/,
    handle: async (r) => json(200, JSON.stringify({ plugins: plugins.list(r.viewer.workspace, r.viewer.email.toLowerCase()) })),
  },
  {
    method: "DELETE",
    pattern: PLUGIN_PATH,
    handle: async (r) => {
      const id = percentDecode(PLUGIN_PATH.exec(r.path)![1]!);
      const ws = r.viewer.workspace;
      const owner = r.viewer.email.toLowerCase();
      if (!plugins.delete(ws, owner, id)) return refuse(404, "plugin_unknown", "no such plugin of yours here");
      gone(ws, owner, id);
      return json(200, JSON.stringify({ ok: true }));
    },
  },
];
