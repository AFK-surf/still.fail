import "./hermes-globals.ts";
import { Effect, Fiber } from "effect";
import { Bridge, BridgeHost, bridgeIroh, type Native } from "./bridge-transport.ts";
import { readWidget, type WidgetScope } from "../widget-reader.ts";

const g = globalThis as any;
const native = g.__native;
const shell: Native = {
  call: (id, op, json, bytes) => native.call(id, op, json, bytes === null ? null : Array.from(bytes)),
  callSync: (op, json) => native.callSync(op, json),
  emit: (client, json) => native.emit(client, json),
  emitBytes: (client, json, bytes) => native.emit(client, JSON.stringify({ ...JSON.parse(json), bytes: Array.from(bytes) })),
  now: () => native.now(), monotonic: () => native.monotonic(), utcOffset: (at) => native.utcOffset(at),
  random: (buf) => buf.set(native.random(buf.length)),
};
const bridge = new Bridge(shell);
let host: BridgeHost;
let running: Fiber.Fiber<void, never> | null = null;
g.__stillfail = {
  start(origin: string, beta: boolean) { host = new BridgeHost(bridge, origin, beta); },
  connect: () => 1,
  receive(client: number, json: string) {
    const message = JSON.parse(json);
    if (message.call !== "widget.read") return;
    const scope = message.params as WidgetScope;
    if (typeof scope.account !== "string" || typeof scope.workspace !== "string") return;
    running = Effect.runFork(readWidget(host, bridgeIroh(bridge), scope).pipe(
      Effect.match({
        onFailure: (error) => ({ error: { code: (error as { code?: string })?.code ?? "widget_sync_failed" } }),
        onSuccess: (value) => ({ ok: value }),
      }),
      Effect.map((reply) => native.emit(client, JSON.stringify({ id: message.id, ...reply }))),
    ));
  },
  disconnect() { if (running) void Effect.runFork(Fiber.interrupt(running)); running = null; },
  complete: (id: number, json: string | null, error: string | null, bytes: number[] | null) =>
    bridge.complete(id, json, error, bytes === null ? null : new Uint8Array(bytes)),
};
