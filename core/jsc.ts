// The still.fail core in JavaScriptCore (src/host/apple_core.m), bundled by scripts/core.sh bundle; `@core/` is
// ember's client/core-ts/src. Like ember's hosts/hermes.ts, with bytes as typed arrays both ways (Uint8Array views
// over memory the engine hands over without copying) and the OS named by the engine.
//
// The engine puts `__native` on the global object before this runs (JscNative), then calls
// `__stillfail.start(cloudOrigin, beta, os)`, `.connect()`, `.receive(client, json, bytes?)`, `.disconnect(client)`
// and `.complete(id, json, error, bytes?)` with the shell's answers; timers come back as `__stillfail_timer(id)`.
import "./jsc-pre.ts";
import "@core/hosts/hermes-globals.ts";
import { startBridged, type Native } from "@core/hosts/bridge.ts";

/// What apple_core.m puts on the global object (hermes-globals.ts's HermesNative, with typed arrays).
interface JscNative {
  call(id: number, op: string, json: string, bytes: Uint8Array | undefined): void;
  callSync(op: string, json: string): string;
  emit(client: number, json: string): void;
  emitBytes(client: number, json: string, bytes: Uint8Array): void;
  fatal(reason: string): void;
  now(): number;
  monotonic(): number;
  utcOffset(atMs: number): number;
  /// Fills `buf` with random bytes.
  fill(buf: Uint8Array): void;
  /// n random bytes (hermes-globals' crypto.getRandomValues).
  random(n: number): ArrayBuffer;
  setTimer(id: number, ms: number): void;
  clearTimer(id: number): void;
  log(level: number, message: string): void;
}

// deno-lint-ignore no-explicit-any
const g = globalThis as any;
const native = g.__native as JscNative;

// JavaScriptCore's case conversion back (jsc-pre.ts).
String.prototype.toLowerCase = g.__mbui_case.lower;
String.prototype.toUpperCase = g.__mbui_case.upper;
delete g.__mbui_case;

// The console to the engine's log (a JSContext's own goes only to the Web Inspector).
{
  const text = (x: unknown) => {
    if (typeof x === "string") return x;
    if (x instanceof Error) return `${x.message}\n${x.stack ?? ""}`;
    try {
      return JSON.stringify(x);
    } catch {
      return String(x);
    }
  };
  const say = (level: number) => (...a: unknown[]) => native.log(level, a.map(text).join(" "));
  g.console = { log: say(1), info: say(1), debug: say(0), warn: say(2), error: say(3), trace: say(0) };
}

const shell: Native = {
  call: (id, op, json, bytes) => native.call(id, op, json, bytes === null ? undefined : bytes),
  callSync: (op, json) => native.callSync(op, json),
  emit: (client, json) => native.emit(client, json),
  emitBytes: (client, json, bytes) => native.emitBytes(client, json, bytes),
  now: () => native.now(),
  monotonic: () => native.monotonic(),
  utcOffset: (at) => native.utcOffset(at),
  random: (buf) => native.fill(buf),
};

let core: ReturnType<typeof startBridged> | null = null;

g.__stillfail = {
  start(cloudOrigin: string, beta: boolean, os: string) {
    core = startBridged(shell, cloudOrigin, beta, os, (reason) => native.fatal(reason));
  },
  connect: (): number => core!.connect(),
  receive: (client: number, json: string, bytes?: Uint8Array) => core!.receive(client, json, bytes),
  disconnect: (client: number) => core!.disconnect(client),
  complete: (id: number, json: string | null, error: string | null, bytes?: Uint8Array) => core!.bridge.complete(id, json, error, bytes ?? null),
};
