// Project only runtime-bearing metadata declared by the client schema. User content and unknown extension fields
// are preserved. Shared by HTTP responses and the reader's digest calculation so unchanged rows stay unchanged.
import { SHAPES } from "../../../client/core-ts/src/shapes/schema.ts";
import type { Ty } from "../../../client/core-ts/src/shapes/dsl.ts";
export const OMIT = Symbol("runtime unavailable to this client");
const object = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);
// Unsupported required metadata removes its containing list item; optional metadata becomes null. A runtime
// is never relabelled as Claude/Codex, which would offer the wrong controls and silently change configuration.
export function runtimeView(type: Ty, value: unknown, supported: Set<string>): unknown | typeof OMIT {
  if (value === null || value === undefined) return value;
  if (type === "RuntimeKind") return typeof value === "string" && !supported.has(value) ? OMIT : value;
  if (typeof type === "object") {
    if ("opt" in type) { const v = runtimeView(type.opt, value, supported); return v === OMIT ? null : v; }
    if ("vec" in type && Array.isArray(value)) return value.map(v => runtimeView(type.vec, v, supported)).filter(v => v !== OMIT);
    if ("map" in type && object(value)) return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,runtimeView(type.map,v,supported)]).filter(([,v]) => v !== OMIT));
    if ("tuple" in type && Array.isArray(value)) {
      const out = value.map((v,i) => type.tuple[i] ? runtimeView(type.tuple[i],v,supported) : v);
      return out.includes(OMIT) ? OMIT : out;
    }
    return value;
  }
  const shape = SHAPES[type];
  if (!object(value)) return value;
  if (shape?.kind === "tagged") {
    const variant = shape.variants[String(value[shape.tag])];
    if (!variant) return value;
    const content = runtimeView(variant,value[shape.content],supported);
    return content === OMIT ? OMIT : {...value,[shape.content]:content};
  }
  if (shape?.kind !== "struct") return value;
  const out = { ...value };
  if (type === "Message" && typeof out.authorRuntime === "string" && !supported.has(out.authorRuntime)) delete out.authorRuntime;
  for (const field of shape.fields) {
    if (!(field.name in out)) continue;
    const v = runtimeView(field.ty, value[field.name], supported);
    if (v === OMIT) return OMIT;
    out[field.name] = v;
  }
  return out;
}

export function runtimeList(op: string, value: unknown, runtimes?: string[]): unknown {
  if (!runtimes) return value;
  const types: Record<string,string> = {sessions:"Session",chats:"ChatItem",threads:"ChatThread"};
  const type = types[op];
  return type ? runtimeView({vec:type},value,new Set(runtimes)) : value;
}
