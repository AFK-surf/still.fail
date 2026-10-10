// Distributed tracing (trace.rs; docs/telemetry.md): one trace per user action, spans for what it asks of stations and
// still.fail cloud, exported as OTLP JSON to still.fail cloud's `/v1/telemetry/traces`. JavaScript has no way to carry
// a context across awaits on every host (the Rust core sets it around each poll), so here the context is current
// around synchronous calls (`enter`) and is handed on explicitly to what runs later (`ctx` parameters).
import { Effect } from "effect";
import type { Host } from "./host.ts";
import type { Runner } from "./runtime.ts";
import { hex, toJsonBytes } from "./util.ts";

/// The share of traces recorded.
export const SAMPLE = 1.0;
/// Spans wait this long to go out together.
export const EXPORT_MS = 3_000;
/// A call that asked nothing of the network and answered well within this is not recorded (`Span.quiet`): a scroll
/// position kept, the focus moving, a draft saved were 41% of a phone's spans, each sent up every few seconds.
export const QUIET_MS = 100;
const MAX_BUFFER = 1_000;

type Anchor = { wallMs: number; monoMs: number };

/// Where a span sits: its trace, itself, and whether the trace is recorded.
export class SpanContext {
  readonly trace: Uint8Array;
  readonly span: Uint8Array;
  readonly sampled: boolean;
  readonly anchor: Anchor;
  /// How many spans were started under its trace's root, the trace over (a quiet root asked nothing when none).
  readonly under: { spans: number };
  constructor(trace: Uint8Array, span: Uint8Array, sampled: boolean, anchor: Anchor, under: { spans: number } = { spans: 0 }) {
    this.trace = trace;
    this.span = span;
    this.sampled = sampled;
    this.anchor = anchor;
    this.under = under;
  }

  /// The W3C `traceparent` header for requests made under this span.
  traceparent(): string {
    return `00-${hex(this.trace)}-${hex(this.span)}-${this.sampled ? "01" : "00"}`;
  }
}

export const Kind = { Internal: 1, Client: 3 } as const;
export type Kind = (typeof Kind)[keyof typeof Kind];

export type Export = (body: Uint8Array) => Effect.Effect<void>;

/// What a host is, for Axiom's `service.name` and `os.type` (set by the host's entry).
export const service = { name: "stillfail-native", os: "macos" };

export class Tracer {
  readonly #host: Host;
  readonly #runner: Runner;
  readonly #sample: number;
  #current: SpanContext | null = null;
  #buffer: unknown[] = [];
  #scheduled = false;
  #export: Export | null = null;
  /// The app's build, once its UI has said it (`client.device`): Axiom's `service.version`, which tells what an
  /// update changed from what older builds still running do.
  #version = "";

  constructor(host: Host, runner: Runner, sample: number) {
    this.#host = host;
    this.#runner = runner;
    this.#sample = sample;
  }

  setExport(e: Export): void {
    this.#export = e;
  }

  setVersion(version: string): void {
    this.#version = version;
  }

  current(): SpanContext | null {
    return this.#current;
  }

  /// Runs `f` with `context` current: what it starts synchronously belongs to that trace.
  enter<T>(context: SpanContext | null, f: () => T): T {
    const before = this.#current;
    this.#current = context;
    try {
      return f();
    } finally {
      this.#current = before;
    }
  }

  /// A span under `parent` (or the current context), or the root of a new trace if there is none.
  span(name: string, kind: Kind, parent?: SpanContext | null): Span {
    const p = parent === undefined ? this.#current : parent;
    return p ? this.#start(name, kind, p) : this.root(name, kind);
  }

  /// A span under `parent` (or the current context); none outside a trace.
  child(name: string, kind: Kind, parent?: SpanContext | null): Span | null {
    const p = parent === undefined ? this.#current : parent;
    return p ? this.#start(name, kind, p) : null;
  }

  root(name: string, kind: Kind): Span {
    return this.#start(name, kind, null);
  }

  /// The root of a new trace that is always recorded.
  always(name: string, kind: Kind): Span {
    const span = this.#start(name, kind, null);
    span.context = new SpanContext(span.context.trace, span.context.span, true, span.context.anchor, span.context.under);
    return span;
  }

  #start(name: string, kind: Kind, parent: SpanContext | null): Span {
    const span = new Uint8Array(8);
    this.#host.randomBytes(span);
    let context: SpanContext;
    if (parent) {
      parent.under.spans++;
      context = new SpanContext(parent.trace, span, parent.sampled, parent.anchor, parent.under);
    }
    else {
      const trace = new Uint8Array(16);
      this.#host.randomBytes(trace);
      const roll = new Uint8Array(4);
      this.#host.randomBytes(roll);
      const r = new DataView(roll.buffer).getUint32(0, true);
      const sampled = r < this.#sample * 2 ** 32;
      context = new SpanContext(trace, span, sampled, { wallMs: this.#host.nowMs(), monoMs: this.#host.monotonicMs() });
    }
    return new Span(this, this.#host, context, parent ? parent.span : null, name, kind, this.#host.monotonicMs());
  }

  record(span: unknown): void {
    if (this.#buffer.length >= MAX_BUFFER) return;
    this.#buffer.push(span);
    if (this.#scheduled) return;
    this.#scheduled = true;
    this.#runner.fork(Effect.sleep(EXPORT_MS).pipe(Effect.andThen(Effect.sync(() => this.flush()))));
  }

  /// Sends what waits now, if there is somewhere to send it.
  flush(): void {
    this.#scheduled = false;
    const e = this.#export;
    if (!e) return;
    const spans = this.#buffer;
    this.#buffer = [];
    if (spans.length === 0) return;
    const body = {
      resourceSpans: [
        {
          resource: { attributes: [attribute("service.name", service.name), attribute("os.type", service.os), ...(this.#version ? [attribute("service.version", this.#version)] : [])] },
          scopeSpans: [{ scope: { name: "stillfail-core" }, spans }],
        },
      ],
    };
    this.#runner.fork(e(toJsonBytes(body)));
  }
}

/// A span being timed. `end` records it; one given up before that (`cancel`) is recorded as cancelled.
export class Span {
  context: SpanContext;
  readonly #tracer: Tracer;
  readonly #host: Host;
  readonly #parent: Uint8Array | null;
  readonly #name: string;
  readonly #kind: Kind;
  readonly #startMs: number;
  #attributes: unknown[] = [];
  #error = false;
  #ended = false;
  #quiet = false;

  constructor(tracer: Tracer, host: Host, context: SpanContext, parent: Uint8Array | null, name: string, kind: Kind, startMs: number) {
    this.#tracer = tracer;
    this.#host = host;
    this.context = context;
    this.#parent = parent;
    this.#name = name;
    this.#kind = kind;
    this.#startMs = startMs;
  }

  /// An attribute: a string, number or bool. Never message content, titles or emails.
  set(key: string, value: string | number | boolean): void {
    if (this.context.sampled) this.#attributes.push(attribute(key, value));
  }

  fail(): void {
    this.#error = true;
  }

  /// Not recorded if it ends well within QUIET_MS with nothing started under it (a call that asked nothing).
  quiet(): void {
    this.#quiet = true;
  }

  end(): void {
    if (this.#ended) return;
    this.#ended = true;
    if (!this.context.sampled) return;
    const endMs = this.#host.monotonicMs();
    if (this.#quiet && !this.#error && this.context.under.spans === 0 && endMs - this.#startMs < QUIET_MS) return;
    const anchor = this.context.anchor;
    const nanos = (mono: number) => {
      const n = Math.max((anchor.wallMs + (mono - anchor.monoMs)) * 1e6, 0);
      return BigInt(Math.floor(n)).toString();
    };
    const span: Record<string, unknown> = {
      traceId: hex(this.context.trace),
      spanId: hex(this.context.span),
      name: this.#name,
      kind: this.#kind,
      startTimeUnixNano: nanos(this.#startMs),
      endTimeUnixNano: nanos(Math.max(endMs, this.#startMs)),
      attributes: this.#attributes,
      status: { code: this.#error ? 2 : 1 },
    };
    this.#attributes = [];
    if (this.#parent) span.parentSpanId = hex(this.#parent);
    this.#tracer.record(span);
  }

  /// Given up before it ended (its task stopped): recorded as cancelled.
  cancel(): void {
    if (this.#ended) return;
    this.set("stillfail.cancelled", true);
    this.end();
  }
}

function attribute(key: string, value: unknown): unknown {
  let v: unknown;
  if (typeof value === "boolean") v = { boolValue: value };
  else if (typeof value === "number") v = Number.isInteger(value) ? { intValue: String(value) } : { doubleValue: value };
  else if (typeof value === "string") v = { stringValue: value };
  else v = { stringValue: JSON.stringify(value) };
  return { key, value: v };
}

const COLLECTIONS = ["sessions", "threads", "connects", "profiles", "logins", "workspaces", "stations", "members", "enrollments", "accounts"];

/// A request path as a span shows it: no query, and ids as `:id`.
export function route(path: string): string {
  const p = path.split(/[?#]/)[0];
  let afterCollection = false;
  return p
    .split("/")
    .map((segment) => {
      const word = segment !== "" && segment.length <= 24 && /^[a-z0-9\-_.]+$/.test(segment) && /[a-z]/.test(segment);
      const id = segment !== "" && (afterCollection || !word);
      afterCollection = !id && COLLECTIONS.includes(segment);
      return id ? ":id" : segment;
    })
    .join("/");
}
