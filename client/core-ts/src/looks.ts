// What the clients show of the stations and their links (looks.rs): the stations' glyph and its line, what a list
// with no rows says instead, how a chat's link is when it is not as it should be, a station's face, a station update.
import { t } from "./i18n.ts";
import { arr as arrU, get as getU } from "./util.ts";

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
  return { online: online.length, dim, connecting, failing, working, summary, label: label.join(t("core-logic.looks.sep")) };
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
          const text = is(s, "error") ? t("core-logic.looks.failing.retrying", { name }) : t("core-logic.looks.failing.offline", { name });
          return { station: get(s, "station") ?? null, text, message: get(s, "message") ?? null };
        });
  const empty = !loading && !connecting && failing.length === 0;
  const onWay = stations.filter((s) => is(s, "connecting")).map((s) => strOf(s, "name"));
  const text =
    onWay.length === 0 ? t("core-logic.looks.reading") : onWay.length === 1 ? t("core-logic.looks.reading.connecting_one", { name: onWay[0] }) : t("core-logic.looks.reading.connecting", { n: onWay.length });
  return { reading: loading || connecting, text, failing, empty };
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
      const split = cut("：") ?? cut(": ");
      why = split && (split[0].includes("连不上") || split[0].startsWith("Can't reach")) ? split[1] : m;
    }
    return { tone: "trouble", text: said("core-logic.looks.link.down", "core-logic.looks.link.down.named"), detail: why };
  }
  if (state === "reconnecting") return { tone: "busy", text: said("core-logic.looks.link.reconnecting", "core-logic.looks.link.reconnecting.named") };
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

/// A station's answer as the clients show it: the agents' memory with each skill's text as people read it.
export function answer(method: string, path: string, value: J): void {
  if (method !== "GET" || path !== "/memory") return;
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
  }
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
