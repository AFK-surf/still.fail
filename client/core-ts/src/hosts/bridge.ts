// Full application startup is separate from the transport, so extensions can
// reuse authenticated IO without loading the application core and its database.
import { Core } from "../core.ts";
import type { CoreModule } from "../module.ts";
import { t } from "../i18n.ts";
import { service } from "../trace.ts";
import { Bridge, BridgeHost, bridgeIroh, type Native } from "./bridge-transport.ts";
export * from "./bridge-transport.ts";

/// A core on a shell: the API the Rust core's Node addon had (connect / receive(json) / disconnect). A bug that ends a fiber ends it as a
/// panic ended the Rust core: `onFatal` (each UI is told `{"fatal": …}` by the shell, which starts another). `modules`:
/// what the app adds to the core (module.ts).
export function startBridged(native: Native, cloudOrigin: string, beta: boolean, os: string, onFatal: (reason: string) => void, extra: { modules?: readonly CoreModule[] } = {}) {
  service.name = "stillfail-native";
  service.os = os;
  const bridge = new Bridge(native);
  const host = new BridgeHost(bridge, cloudOrigin, beta);
  let dead = false;
  const fatal = (error: unknown) => {
    if (dead) return;
    dead = true;
    onFatal(t("core-misc.host.crashed", { reason: error instanceof Error ? error.message : String(error) }));
  };
  const ready = Core.create(host, { iroh: bridgeIroh(bridge), modules: extra.modules }).then((core) => {
    core.inner.runner.onDefect = fatal;
    core.keepTime();
    return core;
  });
  ready.catch(fatal);
  let next = 1;
  let chain: Promise<unknown> = ready;
  const later = (job: (core: Core) => void) => {
    chain = chain.then(() => ready.then((core) => !dead && job(core))).catch(fatal);
  };
  return {
    bridge,
    connect(): number {
      const id = next++;
      later((core) => core.connect());
      return id;
    },
    receive(client: number, json: string, bytes?: Uint8Array): void {
      later((core) => core.receiveJson(client, json, bytes));
    },
    disconnect(client: number): void {
      later((core) => core.disconnect(client));
    },
  };
}
