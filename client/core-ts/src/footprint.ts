// A station's footprint page (footprint.rs, shapes `FootprintView`), from what `GET /footprint` answers: how much of
// the disk the station takes and for what, its chats' directories, its agents' memory, and the clean-ups the viewer
// may do (each a choice: the questions to ask in turn, then the call).
import * as brand from "./brand.ts";
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import type { Clock } from "./present.ts";
import { arr as arrU, get as getU } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const DAY = 86_400_000;

function part(id: string): [string, string, string] {
  const known: Record<string, string> = { chats: "chart-1", transcripts: "chart-2", homes: "chart-3", archive: "chart-4", repos: "chart-5" };
  const key = id in known ? id : "other";
  const tone = known[id] ?? "chart-6";
  return [t(`core-logic.footprint.part.${key}`), t(`core-logic.footprint.part.${key}.note`), tone];
}

function elsewhere(id: string): string {
  return ["claude", "codex", "playwright", "pnpm", "npm", "cargo"].includes(id) ? t(`core-logic.footprint.elsewhere.${id}`) : t("core-logic.footprint.part.other");
}

const n = (v: J, key: string): number => (typeof get(v, key) === "number" ? v[key] : 0);
const size = (bytes: number) => format.bytes(bytes);
const keys = (rows: J[]): J[] => rows.filter((r) => get(r, "key") !== undefined).map((r) => r.key);
const confirm = (title: string, text: string, action: string, danger: boolean) => ({ title, text, action, danger });
const choice = (label: string, call: string, ks: J[], confirms: J[], done: string) => ({ label, call, keys: ks, confirms, done });

function deleteConfirms(what: string, count: number, bytes: number): J[] {
  return [
    confirm(t("core-logic.footprint.delete.title", { what }), t("core-logic.footprint.delete.text", { n: count, size: size(bytes) }), t("core-logic.footprint.continue"), true),
    confirm(t("core-logic.footprint.confirm_again"), t("core-logic.footprint.delete.again", { n: count }), t("core-logic.footprint.delete.action", { n: count }), true),
  ];
}

/// The line that opens the page: how much it takes, or that it is being measured.
export function brief(u: J): void {
  u.text = typeof get(u, "bytes") === "number" ? size(u.bytes) : t("core-logic.footprint.measuring");
}

export function shown(raw: J, c: Clock): J {
  const name = brand.name();
  const checked = typeof get(raw, "checkedAt") === "number" ? (raw.checkedAt as number) : null;
  const scanning = get(raw, "scanning") === true;
  const manage = get(raw, "manage") === true;
  const checkedText =
    checked === null
      ? t("core-logic.footprint.measuring_first")
      : scanning
        ? t("core-logic.footprint.measuring_again")
        : t("core-logic.footprint.measured", { when: format.relativeTime(checked, c.now, c.offsetMin) });
  const parts = arr(get(raw, "parts"));
  const total = parts.reduce((s, p) => s + n(p, "bytes"), 0);
  const disk = get(raw, "disk") ?? null;
  const diskTotal = n(disk, "totalBytes");
  const diskFree = n(disk, "freeBytes");
  const percent = (bytes: number) => (diskTotal > 0 ? format.round((bytes / diskTotal) * 1000) / 10 : 0);
  const rest = Math.max(diskTotal - diskFree - total, 0);
  const bar: J[] = parts.filter((p) => n(p, "bytes") > 0).map((p) => {
    const id = get(p, "id") ?? "";
    return { id, percent: percent(n(p, "bytes")), tone: part(id)[2] };
  });
  bar.push({ id: "rest", percent: percent(rest), tone: "rest" });
  bar.push({ id: "free", percent: percent(diskFree), tone: "free" });
  const freeShare = diskTotal > 0 ? diskFree / diskTotal : 1;
  const freeLevel = freeShare < 0.1 ? "red" : freeShare < 0.2 ? "amber" : "ok";
  const legend = [
    { text: `${name} ${size(total)}`, tone: "chart-1", level: "ok" },
    { text: t("core-logic.footprint.legend.rest", { size: size(rest) }), tone: "rest", level: "ok" },
    { text: t("core-logic.footprint.legend.free", { free: size(diskFree), total: size(diskTotal) }), tone: "", level: freeLevel },
  ];
  const chats = arr(get(raw, "chats"));
  const chatPart = parts.find((p) => get(p, "id") === "chats");
  const chatBytes = chatPart ? n(chatPart, "bytes") : 0;
  const partsShown = parts.filter((p) => n(p, "bytes") > 0).map((p) => {
    const id = typeof get(p, "id") === "string" ? p.id : "";
    const [label, note0, tone] = part(id);
    const note = id === "chats" ? t("core-logic.footprint.part.chats.count", { n: chats.length, note: note0 }) : note0;
    return { id, label, note, text: size(n(p, "bytes")), tone, opens: id === "chats" && chats.length > 0 };
  });
  const elsewhereShown = arr(get(raw, "elsewhere")).map((e) => {
    const id = typeof get(e, "id") === "string" ? e.id : "";
    return { id, label: elsewhere(id), note: get(e, "path") ?? "", text: size(n(e, "bytes")), tone: "", opens: false };
  });

  const idle = (r: J) => get(r, "state") !== "running";
  const rebuildable = chats.filter((r) => n(r, "rebuildBytes") > 0).filter(idle);
  const rebuildBytes = rebuildable.reduce((s, r) => s + n(r, "rebuildBytes"), 0);
  const archived = chats.filter((r) => get(r, "archived") === true);
  const processes = arr(get(raw, "processes"));
  const warm = processes.filter((p) => get(p, "state") === "warm");
  const warmBytes = warm.reduce((s, p) => s + n(p, "rssBytes"), 0);
  const actions: J[] = [];
  if (manage && checked !== null) {
    if (rebuildBytes > 0) {
      const text = t("core-logic.footprint.rebuild.text", { n: rebuildable.length, size: size(rebuildBytes) });
      const clean = t("core-logic.footprint.clean");
      actions.push({
        id: "rebuild",
        title: t("core-logic.footprint.rebuild.title", { size: size(rebuildBytes) }),
        note: t("core-logic.footprint.rebuild.note"),
        action: clean,
        danger: false,
        pick: null,
        choices: [choice(t("core-logic.footprint.all"), "footprint.rebuild", keys(rebuildable), [confirm(t("core-logic.footprint.rebuild.confirm"), text, clean, false)], t("core-logic.footprint.cleaned"))],
      });
    }
    if (archived.length > 0) {
      const choices: J[] = [];
      const counts: number[] = [];
      for (const days of [0, 7, 30]) {
        const old = archived.filter((r) => days === 0 || c.now - n(r, "lastActiveAt") > days * DAY);
        if (old.length === 0 || counts.includes(old.length)) continue;
        counts.push(old.length);
        const bytes = old.reduce((s, r) => s + n(r, "bytes"), 0);
        const [label, what] =
          days === 0
            ? [t("core-logic.footprint.archived.all", { n: old.length, size: size(bytes) }), t("core-logic.footprint.archived.all.what")]
            : [t("core-logic.footprint.archived.unused", { days, n: old.length, size: size(bytes) }), t("core-logic.footprint.archived.unused.what", { days })];
        choices.push(choice(label, "footprint.delete", keys(old), deleteConfirms(what, old.length, bytes), t("core-logic.footprint.deleted")));
      }
      const bytes = archived.reduce((s, r) => s + n(r, "bytes"), 0);
      actions.push({
        id: "archived",
        title: t("core-logic.footprint.archived.title", { n: archived.length, size: size(bytes) }),
        note: t("core-logic.footprint.archived.note"),
        action: t("core-logic.footprint.archived.action"),
        danger: true,
        pick: t("core-logic.footprint.archived.pick"),
        choices,
      });
    }
    if (warm.length > 0) {
      const text = t("core-logic.footprint.idle.text", { size: size(warmBytes) });
      const end = t("core-logic.footprint.end");
      actions.push({
        id: "idle",
        title: t("core-logic.footprint.idle.title", { n: warm.length, size: size(warmBytes) }),
        note: t("core-logic.footprint.idle.note"),
        action: end,
        danger: false,
        pick: null,
        choices: [choice(t("core-logic.footprint.all"), "footprint.evict", keys(warm), [confirm(t("core-logic.footprint.idle.confirm", { n: warm.length }), text, end, false)], t("core-logic.footprint.idle.ended"))],
      });
    }
  }
  const actionsNote = checked === null ? null : !manage ? t("core-logic.footprint.actions.not_allowed") : actions.length === 0 ? t("core-logic.footprint.actions.none") : null;

  const chatsShown = chats.map((r) => {
    const chat = get(r, "chat") ?? null;
    const title = (typeof get(chat, "title") === "string" && chat.title !== "" ? chat.title : null) ?? t("core-logic.footprint.untitled");
    const isArchived = get(r, "archived") === true;
    const running = get(r, "state") === "running";
    const rebuild = n(r, "rebuildBytes");
    const last = n(r, "lastActiveAt");
    const note: string[] = [];
    if (running) note.push(t("core-logic.footprint.working"));
    else if (last > 0) note.push(t("core-logic.footprint.used", { when: format.relativeTime(last, c.now, c.offsetMin) }));
    if (rebuild > 0) note.push(t("core-logic.footprint.chat.rebuildable", { size: size(rebuild) }));
    const key = get(r, "key") ?? null;
    const choices: J[] = [];
    if (manage && rebuild > 0 && !running) {
      choices.push(
        choice(
          t("core-logic.footprint.chat.rebuild", { size: size(rebuild) }),
          "footprint.rebuild",
          [key],
          [confirm(t("core-logic.footprint.chat.rebuild.confirm", { title }), t("core-logic.footprint.chat.rebuild.text", { size: size(rebuild) }), t("core-logic.footprint.clean"), false)],
          t("core-logic.footprint.cleaned"),
        ),
      );
    }
    if (manage && isArchived) {
      const del = t("core-logic.footprint.chat.delete");
      choices.push(
        choice(
          del,
          "footprint.delete",
          [key],
          [
            confirm(t("core-logic.footprint.chat.delete.confirm", { title }), t("core-logic.footprint.chat.delete.text", { size: size(n(r, "bytes")) }), t("core-logic.footprint.continue"), true),
            confirm(t("core-logic.footprint.confirm_again"), t("core-logic.footprint.chat.delete.again"), del, true),
          ],
          t("core-logic.footprint.deleted"),
        ),
      );
    }
    return { key, chat: get(chat, "id") ?? null, title, archived: isArchived, text: size(n(r, "bytes")), note: note.join(" · "), choices };
  });
  const unseen = get(raw, "unseen") ?? null;
  const unseenText = n(unseen, "count") > 0 ? t("core-logic.footprint.unseen", { n: n(unseen, "count"), size: size(n(unseen, "bytes")) }) : null;

  const memory = get(raw, "memory") ?? null;
  const agents = processes.reduce((s, p) => s + n(p, "rssBytes"), 0);
  const rows: J[] = [
    { label: t("core-logic.footprint.memory.station"), text: size(n(memory, "stationBytes")), nested: false },
    { label: t("core-logic.footprint.memory.agents", { n: processes.length }), text: size(agents), nested: false },
  ];
  const sortedProcesses = [...processes].sort((a, b) => n(b, "rssBytes") - n(a, "rssBytes"));
  for (const p of sortedProcesses) {
    const chat = get(p, "chat");
    const chatObj = chat !== null && typeof chat === "object" && !Array.isArray(chat) ? chat : null;
    const title = typeof get(chatObj, "title") === "string" && chatObj.title !== "" ? chatObj.title : null;
    const label = title ?? (get(p, "runtime") === "codex" ? t("core-logic.footprint.memory.codex") : t("core-logic.footprint.untitled"));
    const state = get(p, "state");
    const note =
      state === "running"
        ? t("core-logic.footprint.working")
        : state === "warm" && typeof get(p, "lastActiveAt") === "number"
          ? t("core-logic.footprint.memory.idle", { when: format.relativeTime(p.lastActiveAt, c.now, c.offsetMin) })
          : null;
    const end =
      manage && state === "warm"
        ? choice(
            t("core-logic.footprint.memory.end"),
            "footprint.evict",
            [get(p, "key") ?? null],
            [confirm(t("core-logic.footprint.memory.end.confirm", { label }), t("core-logic.footprint.memory.end.text", { size: size(n(p, "rssBytes")) }), t("core-logic.footprint.end"), false)],
            t("core-logic.footprint.ended"),
          )
        : null;
    rows.push({
      label,
      text: typeof get(p, "rssBytes") === "number" ? size(p.rssBytes) : "—",
      note,
      nested: true,
      chat: chatObj ? (get(chatObj, "id") ?? null) : null,
      choice: end,
    });
  }
  return {
    measured: checked !== null,
    scanning,
    manage,
    checkedText,
    lead: t("core-logic.footprint.lead", { name }),
    totalText: checked !== null ? size(total) : "—",
    bar: checked !== null ? bar : [],
    legend: checked !== null ? legend : [],
    parts: partsShown,
    elsewhere: elsewhereShown,
    elsewhereNote: t("core-logic.footprint.elsewhere.note"),
    actions,
    actionsNote,
    chats: chatsShown,
    chatsText: t("core-logic.footprint.chats", { n: chats.length, size: size(chatBytes) }),
    unseenText,
    memoryTitle: t("core-logic.footprint.memory.title", { total: size(n(memory, "totalBytes")), used: size(n(memory, "usedBytes")) }),
    memory: rows,
  };
}
