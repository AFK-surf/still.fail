// What the clients show of the stations and their links (looks.rs): the stations' glyph and its line, what a list
// with no rows says instead, how a chat's link is when it is not as it should be, a station's face, a station update.
import { t } from "./i18n.ts";
import { bytes as size } from "./format.ts";
import { arr as arrU, get as getU, utf8 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const strOf = (v: J, k: string): string => (typeof get(v, k) === "string" ? v[k] : "");

export function glyph(stations: J[], days: J[]): J {
  const state = (s: J) => strOf(s, "state");
  const running = days
    .flatMap((d) => arr(get(d, "items")))
    .filter((i) => get(i, "state") === "run")
    .map((i) => get(i, "station"))
    .filter((s) => typeof s === "string");
  const online = stations.filter((s) => state(s) === "online");
  const dim = stations.filter((s) => state(s) === "offline" || state(s) === "connecting").length;
  const connecting = stations.filter((s) => state(s) === "connecting").length;
  const failing = stations.filter((s) => state(s) === "error").length;
  const working = online.filter((s) => typeof get(s, "station") === "string" && running.includes(s.station)).length;
  // Asleep only while the device reaches none of them as its own network is down: still.fail cloud not reached alone
  // (its events socket dropping as the network changes) says nothing of the stations, reached without it.
  const asleep = stations.length > 0 && stations.every((s) => state(s) === "offline" && strOf(s, "cause") === "network");
  const n = online.length + dim + failing;
  let summary: string;
  if (n === 1) {
    const name = strOf(stations[0], "name");
    const one = name !== "" ? name : t("core-logic.looks.stations", { n: 1 });
    summary = working > 0 ? t("core-logic.looks.one_working", { name: one }) : one;
  } else summary = working > 0 ? t("core-logic.looks.stations_working", { n, working }) : t("core-logic.looks.stations", { n });
  const label = [t("core-logic.looks.stations", { n }), t("core-logic.looks.online", { n: online.length })];
  if (working > 0) label.push(t("core-logic.looks.working", { n: working }));
  if (connecting > 0) label.push(t("core-logic.looks.connecting", { n: connecting }));
  if (dim > connecting) label.push(t("core-logic.looks.offline", { n: dim - connecting }));
  if (failing > 0) label.push(t("core-logic.looks.failing", { n: failing }));
  // the agents at work on them all, as each station counts its own (`doing`'s `running`)
  const agents = stations.reduce((n, s) => n + (typeof get(s, "running") === "number" ? s.running : 0), 0);
  const now = agents > 0 ? t("core-views.station.running_agents", { n: agents }) : t("core-logic.looks.none_running");
  return { online: online.length, dim, connecting, asleep, failing, working, summary, label: label.join(t("core-logic.looks.sep")), running: agents, now, unit: t("core-logic.looks.running_unit", { n: agents }) };
}

/// What a station is doing, as the stations' card says it under the line of all of them (8 个 agent 正在运行): up,
/// how many of its agents are at work as it counts them (its overview's `counts.running`; 0 while down) or idle, or
/// still connecting until its overview is read; on its way; down, as its link says why.
export function doing(state: string, cause: unknown, overview: J): { running: number; doing: string } {
  if (state === "online") {
    if (overview === undefined || overview === null) return { running: 0, doing: t("core-views.station.connecting") };
    const n = get(get(overview, "counts"), "running");
    const running = typeof n === "number" && n > 0 ? Math.floor(n) : 0;
    return { running, doing: running > 0 ? t("core-logic.looks.station_running", { n: running }) : t("core-views.station.idle") };
  }
  if (state === "connecting") return { running: 0, doing: t("core-views.station.connecting") };
  if (state === "error" || cause === "unreached") return { running: 0, doing: t("core-views.station.unreachable_short") };
  if (cause === "updating") return { running: 0, doing: t("core-views.station.updating_short") };
  if (cause === "network") return { running: 0, doing: t("core-views.station.network") };
  if (cause === "lock") return { running: 0, doing: t("core-views.station.lock_short") };
  return { running: 0, doing: t("core-views.station.offline_short") };
}

export function listNote(stations: J[], days: J[], loading: boolean, unread: string[]): J {
  const is = (s: J, w: string) => get(s, "state") === w;
  if (days.length > 0) return { reading: false, failing: [], empty: false };
  const connecting = stations.some((s) => is(s, "connecting"));
  const failing = loading
    ? []
    : stations
        .filter((s) => is(s, "error") || (is(s, "offline") && typeof get(s, "station") === "string" && unread.includes(s.station)))
        .map((s) => {
          const name = strOf(s, "name");
          const cause = get(s, "cause");
          const text = is(s, "error") || cause === "unreached" ? t("core-logic.looks.failing.retrying", { name }) : cause === "network" ? t("core-logic.looks.failing.network")
            : cause === "lock" ? t("core-logic.looks.failing.lock", { name }) : cause === "updating" ? t("core-logic.looks.failing.updating", { name })
            : t("core-logic.looks.failing.offline", { name });
          return { station: get(s, "station") ?? null, text, message: get(s, "message") ?? null };
        });
  const empty = !loading && !connecting && failing.length === 0;
  const onWay = stations.filter((s) => is(s, "connecting")).map((s) => strOf(s, "name"));
  const text =
    onWay.length === 0 ? t("core-logic.looks.reading") : onWay.length === 1 ? t("core-logic.looks.reading.connecting_one", { name: onWay[0] }) : t("core-logic.looks.reading.connecting", { n: onWay.length });
  return { reading: loading || connecting, text, failing, empty };
}

/// What a view gathered from a workspace's stations still waits on (a ListNote, drawn as every list's first read is:
/// web/ui waiting.tsx, Android ui/Waiting.kt): the stations up whose part is not read yet (`waiting`, by name), those
/// whose part could not be read (`failing`, with why), and whether, all read, there is nothing (`empty`). `waiting` null:
/// the stations themselves are not known yet.
export function waitNote(waiting: string[] | null, failing: { station: string; name: string; message: string }[] = [], empty = false): J {
  if (waiting === null) return { reading: true, text: t("core-logic.looks.wait.stations"), failing: [], empty: false };
  const text =
    waiting.length === 0 ? null : waiting.length === 1 ? t("core-logic.looks.wait.from", { name: waiting[0] }) : t("core-logic.looks.wait.from_many", { n: waiting.length });
  return {
    reading: waiting.length > 0,
    text,
    failing: failing.map((f) => ({ station: f.station, text: t("core-logic.looks.wait.failing", { name: f.name }), message: f.message })),
    empty: waiting.length === 0 && failing.length === 0 && empty,
  };
}

export function linkShown(link: J, name: string): J {
  const said = (key: string, named: string) => (name === "" ? t(key) : t(named, { name }));
  const state = get(link, "state");
  if (state === "offline" || state === "error") {
    const m = strOf(link, "message");
    let why: string | null = null;
    if (m !== "") {
      const cut = (sep: string): [string, string] | null => {
        const i = m.indexOf(sep);
        return i < 0 ? null : [m.slice(0, i), m.slice(i + sep.length)];
      };
      const down = (s: string) => s.includes("连不上") || s.includes("无法连接") || s.startsWith("Can't reach") || s.startsWith("Couldn't reach");
      const split = cut("：") ?? cut(": ");
      // 无法连接此 station alone says no more than the line does.
      why = split && down(split[0]) ? split[1] : down(m) ? null : m;
    }
    return { tone: "trouble", text: said("core-logic.looks.link.down", "core-logic.looks.link.down.named"), detail: why };
  }
  if (state === "reconnecting" || get(link, "retrying") === true) return { tone: "busy", text: said("core-logic.looks.link.reconnecting", "core-logic.looks.link.reconnecting.named") };
  return null;
}

export function face(online: boolean, overview: J): string {
  const running = get(get(overview, "counts"), "running");
  return !online ? "offline" : typeof running === "number" && running > 0 ? "working" : "idle";
}

export function stationLine(online: boolean, host: J): string {
  const m = strOf(host, "cpuModel");
  return m !== "" ? m : t(online ? "core-logic.looks.station.online" : "core-logic.looks.station.offline");
}

/// A station's answer as the clients show it: the agents' memory with each skill's text as people read it, what kind it
/// is, when it is read and its pages, the global memory in its parts, and how long each is.
export function answer(method: string, path: string, value: J): void {
  if (method !== "GET" || path !== "/memory") return;
  const global = get(value, "global");
  if (global !== null && typeof global === "object") {
    const text = strOf(global, "text");
    global.sections = memorySections(text);
    global.size = size(utf8(text).length);
  }
  for (const skill of arr(get(value, "skills"))) {
    const text = strOf(skill, "text");
    let body = text;
    if (text.startsWith("---\n")) {
      const rest = text.slice(4);
      const at = rest.indexOf("\n---");
      if (at >= 0) {
        const after = rest.slice(at + 4);
        body = after.startsWith("\n") ? after.slice(1) : after;
      }
    }
    const description = strOf(skill, "description");
    const project = get(skill, "project") === true;
    skill.body = body.trim();
    skill.about = project && description.startsWith("项目记忆：") ? description.slice("项目记忆：".length) : description;
    const brief = skill.about.replace(/（[^（）]*）/g, "").replace(/\s*\([^()]*\)/g, "").replace(/\s+/g, " ").trim();
    skill.brief = brief !== "" ? brief : skill.about;
    const files = arr(get(skill, "files")).filter((f) => typeof get(f, "name") === "string");
    let bytes = utf8(skill.body).length;
    for (const f of files) {
      const n = utf8(strOf(f, "text")).length;
      bytes += n;
      f.label = f.name.endsWith(".md") ? f.name.slice(0, -3) : f.name;
      f.size = size(n);
    }
    skill.files = files;
    skill.size = size(bytes);
    // Which part of the list it is under, and what its page and its row say: what kind it is, when it is read (its row's line), its pages to pick between (its
    // SKILL.md, 总览, then each other file).
    skill.group = project ? "project" : get(skill, "builtin") === true ? "builtin" : "skill";
    skill.kindText = t(skill.group === "project" ? "core-logic.memory.kind.project" : skill.group === "builtin" ? "core-logic.memory.kind.builtin" : "core-logic.memory.kind.skill");
    skill.whenText = skill.about !== "" ? skill.about : t("core-logic.memory.no_when");
    skill.line = skill.brief !== "" ? skill.brief : t("core-logic.memory.no_when");
    // Its sharing as its host has it: why a station does not have it, why it is not being shared now, in words.
    const share = get(skill, "share");
    if (share !== null && typeof share === "object") {
      for (const m of arr(get(share, "missing"))) {
        const why = strOf(m, "why");
        m.whyText = t(why === "name" ? "core-logic.memory.share.missing.name" : why === "same-name" ? "core-logic.memory.share.missing.same_name" : "core-logic.memory.share.missing.refused");
      }
      const unread = strOf(share, "unread");
      if (unread !== "") share.unreadText = t(unread === "too-large" ? "core-logic.memory.share.too_large" : "core-logic.memory.share.unreadable");
    }
    skill.pages = [
      { key: "", label: t("core-logic.memory.overview"), text: skill.body !== "" ? skill.body : t("core-logic.memory.empty") },
      ...files.map((f) => ({ key: f.name, label: f.label, size: f.size, text: strOf(f, "text") !== "" ? strOf(f, "text") : t("core-logic.memory.empty") })),
    ];
  }
}

/// The global memory by its `##` headings (none inside a fenced block): what is before the first, without the page's
/// own `#` title, is 开头 (the whole of it, 全文, when there are none); each says how many points it has.
export function memorySections(text: string): J[] {
  const parts: { title: string; lines: string[] }[] = [];
  let lead: string[] = [];
  let title: string | null = null;
  let fenced = false;
  for (const line of text.split("\n")) {
    if (/^\s*(```|~~~)/.test(line)) fenced = !fenced;
    if (!fenced && /^## /.test(line)) {
      parts.push({ title: line.slice(3).trim(), lines: [] });
      continue;
    }
    if (parts.length > 0) parts[parts.length - 1]!.lines.push(line);
    else if (!fenced && title === null && /^# /.test(line) && lead.every((l) => l.trim() === "")) title = line.slice(2).trim();
    else lead.push(line);
  }
  const before = lead.join("\n").trim();
  if (before !== "") parts.unshift({ title: t(parts.length > 0 ? "core-logic.memory.lead" : "core-logic.memory.whole"), lines: lead });
  return parts.map((p) => {
    const body = p.lines.join("\n").trim();
    let points = 0;
    let inFence = false;
    for (const line of p.lines) {
      if (/^\s*(```|~~~)/.test(line)) inFence = !inFence;
      else if (!inFence && /^([-*+]|\d+[.)]) /.test(line)) points += 1;
    }
    return { title: p.title, text: body, note: points > 0 ? t("core-logic.memory.points", { n: points }) : size(utf8(body).length) };
  });
}

/// The outbox as its station's update leaves it (`notice`, stationUpdate's): what has not reached the station waits for
/// the update to finish, said under it (`waits`) in place of 正在发送.
export function outboxWaits(outbox: J[], notice: J): J[] {
  if (get(notice, "tone") !== "busy") return outbox;
  return outbox.map((e) => (get(e, "state") === "sending" && (get(e, "seq") === undefined || get(e, "seq") === null) ? { ...e, waits: t("core-logic.looks.update.waits") } : e));
}

/// The outbox while its station is taken for down: what failed as the station was not reached (and is sent once it is:
/// calls.ts `stationBack`) waits for it, said under it (`waits`) in place of 未发送; what the station refused stays failed.
export function outboxHeld(outbox: J[]): J[] {
  return outbox.map((e) => {
    if (get(e, "state") !== "failed" || get(e, "unreached") !== true || get(e, "final") === true) return e;
    const { error: _error, ...rest } = e as Record<string, unknown>;
    return { ...rest, state: "sending", waits: t("core-logic.looks.outbox.held") };
  });
}

/// The line over a chat's composer while its station is taken for down: why, and that what is sent goes once it is
/// reached.
export function offlineNote(link: J, name: string): string {
  const cause = get(link, "cause");
  // Refused for a security mode: why, as the station's refusal says it.
  if (cause === "lock" && typeof get(link, "message") === "string") return t("core-logic.looks.offline.lock", { name: name === "" ? "station" : name, reason: get(link, "message") });
  const key = cause === "network" ? "core-logic.looks.offline.network" : cause === "unreached" ? "core-logic.looks.offline.unreached"
    : cause === "updating" ? "core-logic.looks.offline.updating" : "core-logic.looks.offline.station";
  return name === "" ? t(key, { name: "station" }) : t(key, { name });
}

/// Kept overview progress survives a handover's disconnected interval. No update is inferred from a disconnect.
/// `name` is the station's as its workspace has it, so people can tell which one it is.
export function stationUpdate(overview: J, chat: J, dismissed: string | null, open: boolean, manager: boolean, name = ""): J {
  const update = arr(get(overview, "updates")).find((v) => get(v, "id") === "station");
  if (update === undefined) return null;
  const linkState = get(get(chat, "link"), "state");
  const offline = typeof linkState === "string" && linkState !== "online";
  const station = name !== "" ? name : "station";
  const from = typeof update.version === "string" ? update.version : null;
  const to = typeof update.latest === "string" && update.latest !== from ? update.latest : null;
  const said = { station, from, to };
  if (update.state === "updating") {
    const sending = arr(get(chat, "outbox")).some((e) => get(e, "state") === "sending" && (get(e, "seq") === undefined || get(e, "seq") === null));
    const progress = offline ? t("core-logic.looks.update.reconnecting") : typeof update.progress === "string" ? update.progress : t("core-logic.looks.update.preparing");
    const detail = sending ? t("core-logic.looks.update.sending", { progress }) : progress;
    const percent = !offline && typeof update.percent === "number" ? Math.max(0, Math.min(100, update.percent)) : null;
    return { tone: "busy", label: t("core-logic.looks.update.updating"), text: t("core-logic.looks.update.updating.text", { name: station }), detail, ...said, percent, open, canUpdate: false, dismissible: false };
  }
  if (update.state === "failed") {
    const detail = typeof update.message === "string" ? update.message : t("core-logic.looks.update.retry");
    return { tone: "trouble", label: t("core-logic.looks.update.failed"), text: t("core-logic.looks.update.failed.text", { name: station }), detail, ...said, open, canUpdate: manager && !offline && update.updatable === true, dismissible: false };
  }
  if (update.newer === true && update.updatable === true) {
    const version = typeof update.latest === "string" ? `${typeof update.channel === "string" ? update.channel : ""}:${update.latest}` : null;
    if (version !== null && version === dismissed) return null;
    const detail = update.auto === true && update.idleOnly === true ? t("core-logic.looks.update.idle") : manager ? t("core-logic.looks.update.now") : t("core-logic.looks.update.admin");
    return { tone: "notice", label: t("core-logic.looks.update.newer"), text: t("core-logic.looks.update.newer.text", { name: station }), detail, ...said, version, open, canUpdate: manager && !offline, dismissible: version !== null };
  }
  return null;
}
