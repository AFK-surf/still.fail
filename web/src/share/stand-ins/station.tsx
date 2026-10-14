// What the share page has of web/src/station.tsx (in its place: web/vite.share.config.ts), for FilePreview.tsx: no
// station of a workspace, only the one the link names, read through FilePreview's FileSource (Share.tsx). Its address
// only names the files the preview keeps and the thumbnails it opens out of (viewerFlight.ts thumbId).
export interface Station { id: string; name: string; base: string; address: string; online: boolean; settings: string }

/** The address the share page's files are kept and named under. */
export const SHARE_STATION = "share";

const STATION: Station = { id: "", name: "", base: "", address: SHARE_STATION, online: true, settings: "" };

export function useStation(): Station {
  return STATION;
}
