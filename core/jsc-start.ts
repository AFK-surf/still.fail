// The still.fail core in JavaScriptCore (src/host/apple_core.m): what JavaScriptCore has not (ember's
// hosts/hermes-globals.ts, but for case conversion, which JSC does right), then the core as any engine starts it
// (ember's hosts/engine.ts). `@core/` is ember's client/core-ts/src. An app's entry calls startJsc with its modules;
// still.fail's alone is core/jsc.ts.
//
// The engine puts `__native` on the global object before this runs: hermes-globals' HermesNative (bytes as
// ArrayBuffers both ways) and `os` ("macos", "ios"). It then calls `__stillfail.start(cloudOrigin, beta)`,
// `.connect()`, `.receive(client, json)` / `.receiveBytes(client, json, bytes)`, `.disconnect(client)` and
// `.complete(id, json, error, bytes?)` with the shell's answers; timers come back as `__stillfail_timer(id)`.
import "./jsc-pre.ts";
import "@core/hosts/hermes-globals.ts";
import type { HermesNative } from "@core/hosts/hermes-globals.ts";
import type { CoreModule } from "@core/module.ts";
import { startEngine } from "@core/hosts/engine.ts";

/// What apple_core.m puts on the global object.
interface JscNative extends HermesNative {
  os: string;
}

// deno-lint-ignore no-explicit-any
const g = globalThis as any;
const native = g.__native as JscNative;

// JavaScriptCore's case conversion back (jsc-pre.ts): it has ICU, hermes-globals' Latin-1-only one is Hermes's need.
String.prototype.toLowerCase = g.__mbui_case.lower;
String.prototype.toUpperCase = g.__mbui_case.upper;
delete g.__mbui_case;

// The console to the engine's log: a JSContext has its own (so hermes-globals leaves it), which goes only to the Web
// Inspector.
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

/// Puts `__stillfail` where the engine finds it, the core with `modules` (an app's own; none for still.fail's).
export function startJsc(modules: readonly CoreModule[]): void {
  startEngine(modules, native.os);
}
