// iOS runs the shared core in JavaScriptCore; its native bridge supplies the same
// shell operations as Android, with storage.* routed to the application's Keychain.
import "./hermes-globals.ts";
import { startBridged, type Native } from "./bridge.ts";

const g = globalThis as any;
const native = g.__native;
const shell: Native = {
  call: (id, op, json, bytes) => native.call(id, op, json, bytes === null ? null : Array.from(bytes)),
  callSync: (op, json) => native.callSync(op, json),
  emit: (client, json) => native.emit(client, json),
  now: () => native.now(),
  monotonic: () => native.monotonic(),
  utcOffset: (at) => native.utcOffset(at),
  random: (buf) => buf.set(native.random(buf.length)),
};
let core: ReturnType<typeof startBridged> | null = null;
g.__stillfail = {
  start(cloudOrigin: string, beta: boolean) {
    core = startBridged(shell, cloudOrigin, beta, "ios", (reason) => native.fatal(reason));
  },
  connect: () => core!.connect(),
  receive: (client: number, json: string) => core!.receive(client, json),
  disconnect: (client: number) => core!.disconnect(client),
  complete: (id: number, json: string | null, error: string | null, bytes: number[] | null) =>
    core!.bridge.complete(id, json, error, bytes === null ? null : new Uint8Array(bytes)),
};
