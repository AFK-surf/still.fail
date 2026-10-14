// What the share page has of web/src/api.ts (in its place: web/vite.share.config.ts): no station session to read
// from. Viz.tsx's widgets keep nothing (each starts with nothing kept every time); FilePreview.tsx reads every file
// through the share page's FileSource (Share.tsx), never through a session, so asking one is a mistake.
export type { Attachment } from "../../core/shapes.ts";

/** How much of a file has come (api.ts's). */
export interface FileProgress { loaded: number; total: number | null }
/** A file above this is not fetched whole for a video's still (api.ts's). */
export const BIG_FILE = 16 * 1024 * 1024;

const noSession = () => Promise.reject(new Error("no station session on the share page"));
const none = {
  widgetState: async (_key: string, _path: string) => ({ state: null as unknown }),
  setWidgetState: async (_key: string, _path: string, _state: unknown) => ({ ok: true as const }),
  file: (_key: string, _name: string, _thumb?: boolean, _onProgress?: (got: FileProgress) => void, _size?: number): Promise<Blob> => noSession(),
  poster: (_key: string, _name: string): Promise<Blob | null> => noSession(),
};
export type Api = typeof none;

export function useApi(): Api {
  return none;
}
