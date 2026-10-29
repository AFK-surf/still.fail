// What the share page has of web/src/fonts.ts (in its place: web/vite.share.config.ts), for Viz.tsx: its frames are
// set in the stylesheet's own faces, none chosen there.
export const faceSheets = (): string[] => [];

export function onFaces(_f: () => void): () => void {
  return () => {};
}
