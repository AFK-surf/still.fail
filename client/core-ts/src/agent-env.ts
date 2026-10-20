// A station's variables for its agents (docs/agent-env.md) as one page edits them: a .env file's lines, each read as it
// is typed (its name, value and comment, for the page to colour; what is wrong with it, said beside it), saved whole as
// the station takes them (`PUT /agent-env {text}`, station/src/ops/agent-env.ts `parseEnvText`, the same rules). A
// secret shows masked; left so, the station keeps it.
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import type { ClientId, Topic } from "./protocol.ts";
import { topicKey } from "./protocol.ts";
import type { Store, Watch } from "./store.ts";
import { get, isObject } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The station's limits (station/src/ops/agent-env.ts).
const ENV_NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;
const MOST_VALUE = 4096;

export type EnvPart = { kind: "name" | "value" | "comment" | "other"; text: string };
export type EnvLine = { parts: EnvPart[]; problem: string | null; error: boolean };

/// The variables as written, a line each: its parts (together, the line as it is), and what is wrong with it (an error
/// keeps it from being saved; a name given again is only said).
export function readEnv(text: string): { lines: EnvLine[]; errors: number } {
  const raw = text.split("\n");
  const lines: EnvLine[] = [];
  const last = new Map<string, number>();
  for (const line of raw) {
    const lead = line.match(/^\s*/)![0];
    const rest = line.slice(lead.length);
    if (rest === "") {
      lines.push({ parts: line ? [{ kind: "other", text: line }] : [], problem: null, error: false });
      continue;
    }
    if (rest.startsWith("#")) {
      lines.push({ parts: [...(lead ? [{ kind: "other" as const, text: lead }] : []), { kind: "comment", text: rest }], problem: null, error: false });
      continue;
    }
    const exported = rest.match(/^export\s+/)?.[0] ?? "";
    const before = lead + exported;
    const pair = rest.slice(exported.length);
    const at = pair.indexOf("=");
    const opening = before ? [{ kind: "other" as const, text: before }] : [];
    if (at <= 0 || pair.slice(0, at).trim() === "") {
      lines.push({ parts: [...opening, { kind: "other", text: pair }], problem: t("core-misc.agentEnv.notPair"), error: true });
      continue;
    }
    const name = pair.slice(0, at);
    const value = pair.slice(at + 1);
    const parts: EnvPart[] = [...opening, { kind: "name", text: name }, { kind: "other", text: "=" }, ...(value ? [{ kind: "value" as const, text: value }] : [])];
    const key = name.trim();
    let problem: string | null = null;
    if (!ENV_NAME.test(key)) problem = t("core-misc.agentEnv.badName", { name: key });
    else if (unquoted(value.trim()).length > MOST_VALUE) problem = t("core-misc.agentEnv.tooLong", { most: MOST_VALUE });
    if (problem === null) {
      const earlier = last.get(key);
      if (earlier !== undefined && !lines[earlier]!.error) lines[earlier]!.problem = t("core-misc.agentEnv.repeated");
      last.set(key, lines.length);
    }
    lines.push({ parts, problem, error: problem !== null });
  }
  return { lines, errors: lines.filter((l) => l.error).length };
}

/// A value without the quotes round it (as the station reads it).
const unquoted = (v: string) => (v.length >= 2 && (v[0] === '"' || v[0] === "'") && v.at(-1) === v[0] ? v.slice(1, -1) : v);

/// The station's variables as written (its overview's, a secret masked): `NAME=value` a line.
function savedText(store: Store, station: string): string | null {
  const v = store.value({ topic: "overview", station });
  if (v === undefined || "err" in v) return null;
  const env = get(v.ok, "agentEnv");
  return Array.isArray(env) ? env.map((e: J) => `${get(e, "key")}=${get(e, "value")}`).join("\n") : null;
}

/// `saving`: the station's text when a save began, kept till the station tells what it has now (not shown back meanwhile).
type Draft = { owner: ClientId; text: string; dirty: boolean; pending: boolean; saving: string | null; watch: Watch };

/// The drafts of the pages that edit a station's variables (`agentEnvForm`), each its UI's.
export class AgentEnvForms {
  readonly #store: Store;
  readonly #drafts = new Map<string, Draft>();

  constructor(store: Store) {
    this.#store = store;
  }

  disconnect(owner: ClientId): void {
    for (const [k, d] of [...this.#drafts]) {
      if (d.owner !== owner) continue;
      d.watch.drop();
      this.#drafts.delete(k);
    }
  }

  value(topic: Topic): J {
    const d = this.#drafts.get(topicKey(topic));
    if (!d) return null;
    // Not edited: follows the station's (changed elsewhere), once it has told what was just saved.
    if (!d.dirty && !d.pending) {
      const saved = savedText(this.#store, topic.station as string);
      if (d.saving === null || saved !== d.saving) {
        d.saving = null;
        d.text = saved ?? d.text;
      }
    }
    return { text: d.text, dirty: d.dirty, pending: d.pending, ...readEnv(d.text) };
  }

  change(topic: Topic, owner: ClientId, action: string, patch: J): J {
    const station = topic.station as string;
    const key = topicKey(topic);
    const existing = this.#drafts.get(key);
    if (existing && existing.owner !== owner) throw CoreError.invalid(t("core-misc.agentEnv.notYours"));
    if (action === "drop") {
      existing?.watch.drop();
      this.#drafts.delete(key);
      this.#store.invalidate(topic);
      return null;
    }
    let d = existing;
    if (!d) {
      const watch = this.#store.watch({ topic: "overview", station }, () => this.#store.invalidate(topic));
      d = { owner, text: savedText(this.#store, station) ?? "", dirty: false, pending: false, saving: null, watch };
      this.#drafts.set(key, d);
    }
    if (action === "edit" && isObject(patch)) {
      if (d.pending) throw CoreError.invalid(t("core-misc.agentEnv.saving"));
      if (patch.reset === true) {
        d.dirty = false;
        d.text = savedText(this.#store, station) ?? "";
      } else if (typeof patch.text === "string") {
        d.text = patch.text;
        d.dirty = d.text !== (savedText(this.#store, station) ?? "");
      }
    }
    this.#store.invalidate(topic);
    return this.value(topic);
  }

  /// What is saved: the text, once every line reads.
  begin(topic: Topic, owner: ClientId): { text: string } {
    const d = this.#drafts.get(topicKey(topic));
    if (!d || d.owner !== owner) throw CoreError.invalid(t("core-misc.agentEnv.closed"));
    if (d.pending) throw CoreError.invalid(t("core-misc.agentEnv.saving"));
    if (readEnv(d.text).errors > 0) throw CoreError.invalid(t("core-misc.agentEnv.fix"));
    d.pending = true;
    d.saving = savedText(this.#store, topic.station as string);
    this.#store.invalidate(topic);
    return { text: d.text };
  }

  finish(topic: Topic, owner: ClientId, ok: boolean): void {
    const d = this.#drafts.get(topicKey(topic));
    if (d && d.owner === owner) {
      d.pending = false;
      if (ok) d.dirty = false;
      else d.saving = null;
    }
    this.#store.invalidate(topic);
  }
}
