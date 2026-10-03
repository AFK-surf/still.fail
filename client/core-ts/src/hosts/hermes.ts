// The core in the Android app's Hermes (apps/android/core: the engine in C++, its IO in the Rust shell, client/shell):
// bundled into one script (scripts/hermes-bundle.ts) the engine runs, then `__stillfail.start(cloudOrigin, beta)`.
// The engine calls `__stillfail.connect()`, `.receive(client, json)`, `.disconnect(client)` for the app, and
// `.complete(id, json, error, bytes)` with the shell's answers; what the core says goes out through `__native.emit`.
import type { HermesNative } from "./hermes-globals.ts";
import "./hermes-globals.ts";
import { startBridged, type Native } from "./bridge.ts";

// deno-lint-ignore no-explicit-any
const g = globalThis as any;
const native = g.__native as HermesNative;

const shell: Native = {
  call: (id, op, json, bytes) => native.call(id, op, json, bytes === null ? undefined : (bytes.buffer as ArrayBuffer).slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)),
  callSync: (op, json) => native.callSync(op, json),
  emit: (client, json) => native.emit(client, json),
  now: () => native.now(),
  monotonic: () => native.monotonic(),
  utcOffset: (at) => native.utcOffset(at),
  random: (buf) => buf.set(new Uint8Array(native.random(buf.length))),
};

let core: ReturnType<typeof startBridged> | null = null;

g.__stillfail = {
  start(cloudOrigin: string, beta: boolean) {
    core = startBridged(shell, cloudOrigin, beta, "android", (reason) => native.fatal(reason));
  },
  connect: (): number => core!.connect(),
  receive: (client: number, json: string) => core!.receive(client, json),
  disconnect: (client: number) => core!.disconnect(client),
  complete: (id: number, json: string | null, error: string | null, bytes: ArrayBuffer | undefined) =>
    core!.bridge.complete(id, json, error, bytes === undefined ? null : new Uint8Array(bytes)),
};
