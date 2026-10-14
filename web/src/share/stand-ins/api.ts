// What the share page has of web/src/api.ts (in its place: web/vite.share.config.ts), for Viz.tsx: no station to keep
// what a widget keeps; it starts with nothing kept every time.
export type { Attachment } from "../../core/shapes.ts";

const none = { widgetState: async (_key: string, _path: string) => ({ state: null as unknown }), setWidgetState: async (_key: string, _path: string, _state: unknown) => ({ ok: true as const }) };

export function useApi() {
  return none;
}
