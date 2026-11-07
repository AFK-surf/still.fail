import { BackgroundIndexBuilder } from "../store/background-index-builder.ts";
import { chatShareIndexReady, chatShareIndexStep, hasChatShareIndex, installChatShareIndex, refreshChatShareIndex, SHARE_MANY } from "../store/chat-share-index.ts";
import type { Store } from "../store/store.ts";

/// Sharing continues to answer the old way while the preceding station is up or a worker prepares its old grants.
export class ChatShareIndexBuilder extends BackgroundIndexBuilder {
  constructor(store: Store, previous: Promise<void>, workerFile?: URL) {
    super(store, previous, {
      scope: "xshare", name: "share", previousName: "shares", kind: "chat-share",
      install: () => installChatShareIndex(store.db), ready: () => chatShareIndexReady(store.db),
      step: () => chatShareIndexStep(store.db), refresh: () => refreshChatShareIndex(store.db),
    }, workerFile);
  }

  request(): void {
    this.buildIf(() => {
      if (chatShareIndexReady(this.store.db)) return false;
      // A few shares are cheaper to read directly. Do not install anything until the table grows past this probe.
      return hasChatShareIndex(this.store.db) || this.store.db.prepare(SHARE_MANY).get() !== undefined;
    });
  }
}
