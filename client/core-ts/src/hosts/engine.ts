// The core in a native app's JS engine, whichever it is (the Android app's Hermes: hermes-start.ts; JavaScriptCore on
// Apple's systems: an app's own entry): the engine puts `__native` on the global object (its calls go to the Rust shell,
// client/shell) and what JS has not, before this runs; the core is then started by `__stillfail.start(cloudOrigin,
// beta[, os])`. The engine calls `__stillfail.connect()`, `.receive(client, json)` (`.receiveBytes(client, json,
// bytes)` for a call with bytes beside it), `.disconnect(client)` for the app, and `.complete(id, json, error, bytes)`
// with the shell's answers; what the core says goes out through `__native.emit`.
import type { CoreModule } from "../module.ts";
import { startBridged, type Native } from "./bridge.ts";
import type { HermesNative } from "./hermes-globals.ts";

/// Puts `__stillfail` where the engine finds it, its core with `modules`; `os` is what the core says it runs on when the
/// engine's `start` does not say.
export function startEngine(modules: readonly CoreModule[], os: string): void {
  // deno-lint-ignore no-explicit-any
  const g = globalThis as any;
  const native = g.__native as HermesNative;

  const shell: Native = {
    call: (id, op, json, bytes) => native.call(id, op, json, bytes === null ? undefined : (bytes.buffer as ArrayBuffer).slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)),
    callSync: (op, json) => native.callSync(op, json),
    emit: (client, json) => native.emit(client, json),
    // The frame's own buffer when it is all of it (as the screen views make them), else its bytes copied out.
    emitBytes: (client, json, bytes) => native.emitBytes(client, json, (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength ? bytes.buffer : bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)) as ArrayBuffer),
    now: () => native.now(),
    monotonic: () => native.monotonic(),
    utcOffset: (at) => native.utcOffset(at),
    random: (buf) => buf.set(new Uint8Array(native.random(buf.length))),
    // the app's performance record, where the engine keeps one (record.ts)
    ...(typeof native.recording === "function" && typeof native.record === "function"
      ? { recording: () => native.recording!(), record: (line: string) => native.record!(line) }
      : {}),
  };

  let core: ReturnType<typeof startBridged> | null = null;

  g.__stillfail = {
    start(cloudOrigin: string, beta: boolean, said?: string) {
      core = startBridged(shell, cloudOrigin, beta, said ?? os, (reason) => native.fatal(reason), { modules });
    },
    connect: (): number => core!.connect(),
    receive: (client: number, json: string) => core!.receive(client, json),
    receiveBytes: (client: number, json: string, bytes: ArrayBuffer) => core!.receive(client, json, new Uint8Array(bytes)),
    disconnect: (client: number) => core!.disconnect(client),
    complete: (id: number, json: string | null, error: string | null, bytes: ArrayBuffer | undefined) =>
      core!.bridge.complete(id, json, error, bytes === undefined ? null : new Uint8Array(bytes)),
  };
}
