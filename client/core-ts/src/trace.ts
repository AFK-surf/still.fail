// Distributed tracing: one trace per user action, spans for what it asks of stations and
// still.fail cloud, exported as OTLP JSON to still.fail cloud's `/v1/telemetry/traces`. JavaScript has no way to carry
// a context across awaits on every host (the Rust core sets it around each poll), so here the context is current
// around synchronous calls (`enter`) and is handed on explicitly to what runs later (`ctx` parameters).
import { Effect } from "effect";
import type { BaseHost } from "./host-of.ts";
import { laterSleep, type Runner } from "./runtime.ts";
import { hex, toJsonBytes } from "./util.ts";

/// The share of traces recorded.
export const SAMPLE = 1.0;
/// Spans wait this long to go out together.
export const EXPORT_MS = 3_000;
/// A call that asked nothing of the network and answered well within this is not recorded (`Span.quiet`): a scroll
/// position kept, the focus moving, a draft saved were 41% of a phone's spans, each sent up every few seconds.
export const QUIET_MS = 100;
const MAX_BUFFER = 1_000;
/// The longest a batch that did not go out waits to be sent again.
export const RETRY_MAX_MS = 60_000;

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

/// Sends a batch; failing, it is kept to be sent again (one the cloud will never take is to succeed instead).
export type Export = (body: Uint8Array) => Effect.Effect<void, unknown>;

/// What a host is, for the traces' `service.name` and `os.type`: set by the host's entry, each empty until one says
/// it (then what the tracer's names say, `TraceNames.service`).
export const service = { name: "", os: "" };

/// What a program's traces are named by: `scope`, what its spans are said to be made by; `own`, what the name of an
/// attribute the base sets for it begins with (`Span.own`: the dial's `station` is `<own>station`); and `service`,
/// what its host is called where no entry said (a core made with no host's entry before it: a bench, a test). The
/// still.fail core's are route.ts `TRACES`. A program that names none is `unknown_service`, as OpenTelemetry calls
/// one, with no `os.type`: never an empty name.
export type TraceNames = { scope: string; own: string; service?: { name: string; os: string } };

export class Tracer {
  readonly names: TraceNames;
  readonly #host: BaseHost;
  readonly #runner: Runner;
  readonly #sample: number;
  #current: SpanContext | null = null;
  #buffer: unknown[] = [];
  #scheduled = false;
  /// Batches in a row that did not go out.
  #failed = 0;
  #export: Export | null = null;
  /// The app's build, once its UI has said it (`client.device`): the traces' `service.version`, which tells what an
  /// update changed from what older builds still running do.
  #version = "";

  constructor(host: BaseHost, runner: Runner, sample: number, names: TraceNames = { scope: "", own: "" }) {
    this.names = names;
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
    this.#schedule();
  }

  #schedule(): void {
    if (this.#scheduled) return;
    this.#scheduled = true;
    const wait = this.#failed === 0 ? EXPORT_MS : Math.min(EXPORT_MS * 2 ** this.#failed, RETRY_MAX_MS);
    this.#runner.fork(laterSleep(wait).pipe(Effect.andThen(Effect.sync(() => this.flush()))));
  }

  /// A batch that did not go out waits for the next, ahead of what came since. 2026-11-07: a phone whose network
  /// went every few minutes had 40% of its failed reconnects never reach the traces, nor anything else that ended as they
  /// did: each was sent as the network was down, and let go.
  #unsent(spans: unknown[]): void {
    this.#failed++;
    this.#buffer = spans.concat(this.#buffer).slice(0, MAX_BUFFER);
    this.#schedule();
  }

  /// Sends what waits now, if there is somewhere to send it.
  flush(): void {
    this.#scheduled = false;
    const e = this.#export;
    if (!e) return;
    const spans = this.#buffer;
    this.#buffer = [];
    if (spans.length === 0) return;
    const name = service.name || this.names.service?.name || "unknown_service";
    const os = service.os || this.names.service?.os || "";
    const body = {
      resourceSpans: [
        {
          resource: { attributes: [attribute("service.name", name), ...(os !== "" ? [attribute("os.type", os)] : []), ...(this.#version ? [attribute("service.version", this.#version)] : [])] },
          scopeSpans: [{ scope: { name: this.names.scope }, spans }],
        },
      ],
    };
    this.#runner.fork(
      Effect.match(e(toJsonBytes(body)), {
        onSuccess: () => {
          this.#failed = 0;
        },
        onFailure: () => this.#unsent(spans),
      }),
    );
  }
}

/// A span being timed. `end` records it; one given up before that (`cancel`) is recorded as cancelled.
export class Span {
  context: SpanContext;
  readonly #tracer: Tracer;
  readonly host: BaseHost;
  readonly #parent: Uint8Array | null;
  readonly #name: string;
  readonly #kind: Kind;
  readonly #startMs: number;
  #attributes: unknown[] = [];
  #error = false;
  #ended = false;
  #quiet = false;

  constructor(tracer: Tracer, host: BaseHost, context: SpanContext, parent: Uint8Array | null, name: string, kind: Kind, startMs: number) {
    this.#tracer = tracer;
    this.host = host;
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

  /// An attribute the base sets, named as the program's own (`TraceNames.own` before `key`).
  own(key: string, value: string | number | boolean): void {
    this.set(this.#tracer.names.own + key, value);
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
    const endMs = this.host.monotonicMs();
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
    this.own("cancelled", true);
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

/// A request path as a span shows it: no query, and ids as `:id`: what follows one of `collections` (the names an
/// API's paths give what they list: `/stations/<id>`), and whatever is no plain word.
export function routeBy(collections: readonly string[]): (path: string) => string {
  return (path) => {
    const p = path.split(/[?#]/)[0]!;
    let afterCollection = false;
    return p
      .split("/")
      .map((segment) => {
        const word = segment !== "" && segment.length <= 24 && /^[a-z0-9\-_.]+$/.test(segment) && /[a-z]/.test(segment);
        const id = segment !== "" && (afterCollection || !word);
        afterCollection = !id && collections.includes(segment);
        return id ? ":id" : segment;
      })
      .join("/");
  };
}
