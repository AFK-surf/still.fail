// The reader's text worked out off the page's thread (text.ts): a novel of a few MB is decoded, joined back into its
// paragraphs and searched for its chapters here, while the page goes on.
import { book } from "./text.ts";

self.onmessage = (event: MessageEvent<{ bytes: ArrayBuffer; markdown: boolean; cut: boolean }>) => {
  const { bytes, markdown, cut } = event.data;
  try {
    const b = book(new Uint8Array(bytes), markdown, cut);
    (self as unknown as Worker).postMessage({ book: b }, [b.starts.buffer]);
  } catch (e) {
    (self as unknown as Worker).postMessage({ error: e instanceof Error ? e.message : String(e) });
  }
};
