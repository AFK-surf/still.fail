// A chat relayed to a channel (docs/relay.md): from its title bar, ⌘K or its row's menu, a dialog offers the channels
// and groups the station's connects' bots are in (Slack, Feishu, Lark), those relayed to before first, found by typing;
// one picked, with a note if wanted, 接力 has the station start the conversation there and the chat's agent go on in it too. A Slack
// message's link typed (pasted) into the search offers that message's thread instead. The phone's sheet
// (mobile/Chat.tsx RelaySheet) picks the same way (useRelay).
import { useEffect, useMemo, useState, useSyncExternalStore, type ReactNode } from "react";
import { stationApi, useStationCall, type RelayConnect, type RelayPlace } from "./api.ts";
import { Button, Dialog, ElsewhereLogo, WaitLine } from "./ui.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./Relay.css.ts";
import { t } from "./i18n.ts";

type Asked = { station: string; thread: number };

let asked: Asked | null = null;
const listeners = new Set<() => void>();
const tell = () => { for (const l of listeners) l(); };

/** Opens the relay dialog for a chat (its thread) of a station. */
export function openRelay(station: string, thread: number): void {
  asked = { station, thread };
  tell();
}

/** Where the relay dialog is drawn when asked for: mounted once under a scope's pages. */
export function RelayHost() {
  const shown = useSyncExternalStore((l) => { listeners.add(l); return () => { listeners.delete(l); }; }, () => asked, () => null);
  if (shown === null) return null;
  return <RelayDialog key={`${shown.station}/${shown.thread}`} station={shown.station} thread={shown.thread} onClose={() => { asked = null; tell(); }} />;
}

/** Read as the dialog opens: being read, read, or why not. */
type Read = { reading: true } | { ok: RelayConnect[] } | { error: string };

/** A place with the connect it is through. */
type Row = { connect: RelayConnect; place: RelayPlace };

/** How many places relayed to before are offered as the dialog opens, before 「显示全部」; with no more than FEW places in
 * all, all of them are. */
const RECENT = 5;
const FEW = 8;

/** How a place says what relaying there does: a new thread, a new topic, or the group's conversation taken over. */
const kindNote = (p: RelayPlace) => t(p.kind === "channel" ? "web-main.relay.kind.channel" : p.kind === "topics" ? "web-main.relay.kind.topics" : "web-main.relay.kind.group");

/** Whether what was typed is a link to a Slack message (the station finds its workspace among its connects'). */
const slackLink = (typed: string) => /^https?:\/\/[^/\s]+\/archives\/[A-Z0-9]+\/p\d{16}/.test(typed.trim());

/** A connect as people know it: its workspace (Slack) or tenant (Feishu), else its bot's name; with its bot's name too
 * when another of `connects` (several bots in one workspace) has the same workspace. */
const workspace = (c: RelayConnect, connects: RelayConnect[]) =>
  c.team !== null && connects.some((o) => o.id !== c.id && o.team === c.team) ? `${c.team} · ${c.name}` : (c.team ?? c.name);

const placeName = (p: RelayPlace) => (p.kind === "channel" ? `${p.private ? "🔒 " : ""}#${p.name}` : p.name);

/**
 * The places offered, of every connect picked by the filter as one list: those whose name has what was typed (those
 * starting with it first), else all of them; then those relayed to before (the latest first), then by name. Nothing
 * typed, more than FEW and some relayed to before, only the first RECENT of those (`recent`) unless all were asked for.
 */
export function arrange(connects: RelayConnect[], query: string, all: boolean): { rows: Row[]; recent: boolean; total: number } {
  const q = query.trim().toLowerCase();
  const rows = connects.flatMap((connect) => connect.places.map((place) => ({ connect, place })));
  const total = rows.length;
  const shown = q === "" ? rows : rows.filter((r) => r.place.name.toLowerCase().includes(q));
  const first = (r: Row) => (q !== "" && r.place.name.toLowerCase().startsWith(q) ? 0 : 1);
  shown.sort((a, b) => first(a) - first(b) || (b.place.used ?? -1) - (a.place.used ?? -1) || a.place.name.localeCompare(b.place.name));
  const used = shown.filter((r) => r.place.used !== undefined);
  if (q === "" && !all && total > FEW && used.length > 0) return { rows: used.slice(0, RECENT), recent: true, total };
  return { rows: shown, recent: false, total };
}

/**
 * The picking itself, the same on the wide screen's dialog and the phone's sheet: the search (or a Slack link), the
 * workspaces to look in when there are several, the places relayed to before as it opens (all of them asked for or
 * searched), the one picked with the note; `go` relays to what was picked, said by `say`, then `onDone`. `focus`: the
 * search is focused as it opens (not on a phone, where that brings up the keyboard over the list).
 */
export function useRelay(station: string, thread: number, say: (text: string) => void, onDone: () => void, focus = true) {
  const call = useStationCall(station);
  const api = stationApi(call);
  const [read, setRead] = useState<Read>({ reading: true });
  const [query, setQuery] = useState("");
  const [scope, setScope] = useState<string | null>(null);
  const [all, setAll] = useState(false);
  const [picked, setPicked] = useState<Row | null>(null);
  const link = slackLink(query) ? query.trim() : null;
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let gone = false;
    stationApi(call).relayPlaces(thread).then((r) => { if (!gone) setRead({ ok: r.connects }); }, (e: unknown) => { if (!gone) setRead({ error: failure(e) }); });
    return () => { gone = true; };
  }, [call, thread]);
  const connects = "ok" in read ? read.ok : [];
  const several = connects.length > 1;
  const looked = useMemo(() => connects.filter((c) => scope === null || c.id === scope), [connects, scope]);
  const { rows, recent, total } = useMemo(() => arrange(looked, query, all), [looked, query, all]);
  const go = () => {
    const to = link !== null ? { link } : picked !== null ? { connect: picked.connect.id, channel: picked.place.id } : null;
    if (to === null) return;
    setBusy(true);
    api.relay(thread, to, note).then(
      (done) => { say(t("web-main.relay.done", { place: done.place })); onDone(); },
      (e: unknown) => { setBusy(false); say(t("web-main.act.failed", { what: t("web-main.relay.verb"), error: failure(e) })); },
    );
  };
  const row = (r: Row, on: boolean, end: ReactNode, onClick: () => void) => (
    <button key={`${r.connect.id}/${r.place.id}`} type="button" role="option" aria-selected={on} className={css.place} data-on={on || undefined} onClick={onClick}>
      <ElsewhereLogo kind={r.connect.kind === "slack" ? "slack" : "feishu"} size={16} />
      <span className={css.placeName}>{placeName(r.place)}</span>
      {several && scope === null && <span className={css.placeWhere}>{workspace(r.connect, connects)}</span>}
      <span className={css.placeNote} title={r.place.kind === "group" ? t("web-main.relay.kind.groupNote") : undefined}>{end}</span>
    </button>
  );
  let list;
  if (link !== null) {
    list = (
      <div className={css.list} role="listbox" aria-label={t("web-main.relay.places")}>
        <button type="button" role="option" aria-selected className={css.place} data-on>
          <ElsewhereLogo kind="slack" size={16} />
          <span className={css.placeName}>{t("web-main.relay.thread")}</span>
          <span className={css.placeNote}>{t("web-main.relay.kind.thread")}</span>
        </button>
      </div>
    );
  } else if (picked !== null) {
    list = (
      <>
        <div className={css.list} role="listbox" aria-label={t("web-main.relay.places")}>
          {row(picked, true, <>{kindNote(picked.place)} · <span className={css.change}>{t("web-main.relay.change")}</span></>, () => setPicked(null))}
        </div>
        <p className={css.via}>{t("web-main.relay.via", { bot: picked.connect.name })}</p>
      </>
    );
  } else if ("reading" in read) list = <WaitLine text={t("web-main.relay.reading")} />;
  else if ("error" in read) list = <p className={controlsCss.fieldError} role="alert">{read.error}</p>;
  else if (connects.length === 0) list = <p className={css.empty}>{t("web-main.relay.noConnects")}</p>;
  else {
    list = (
      <>
        {several && (
          <div className={css.scopes} role="group" aria-label={t("web-main.relay.workspaces")}>
            <button type="button" className={css.scope} data-on={scope === null || undefined} aria-pressed={scope === null} onClick={() => setScope(null)}>{t("web-main.relay.allWorkspaces")}</button>
            {connects.map((c) => (
              <button key={c.id} type="button" className={css.scope} data-on={scope === c.id || undefined} aria-pressed={scope === c.id} onClick={() => setScope(c.id)}>
                <ElsewhereLogo kind={c.kind === "slack" ? "slack" : "feishu"} size={13} />{workspace(c, connects)}
              </button>
            ))}
          </div>
        )}
        <div className={css.list} role="listbox" aria-label={t("web-main.relay.places")}>
          {recent && <div className={css.groupHead}>{t("web-main.relay.recent")}</div>}
          {rows.map((r) => row(r, false, r.place.kind === "channel" ? null : kindNote(r.place), () => setPicked(r)))}
          {rows.length === 0 && <p className={css.empty}>{query.trim() === "" ? t("web-main.relay.noPlaces") : t("web-main.relay.noMatch")}</p>}
          {recent && total > rows.length && <button type="button" className={css.more} onClick={() => setAll(true)}>{t("web-main.relay.showAll", { count: total })}</button>}
          {looked.filter((c) => c.error).map((c) => <p key={c.id} className={css.unread}>{several ? `${workspace(c, connects)} · ` : ""}{t("web-main.relay.unread", { error: c.error! })}</p>)}
        </div>
      </>
    );
  }
  const body = (
    <div className={css.body}>
      {picked === null && <input className={controlsCss.input} type="search" autoFocus={focus} value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("web-main.relay.searchOrLink")} aria-label={t("web-main.relay.search")} />}
      {list}
      {(picked !== null || link !== null) && (
        <label className={css.noteField}>
          <span className={css.noteLabel}>{t("web-main.relay.note")}</span>
          <input className={controlsCss.input} value={note} maxLength={2000} autoFocus={focus} onChange={(e) => setNote(e.target.value)} placeholder={t("web-main.relay.notePlaceholder")} />
        </label>
      )}
    </div>
  );
  const label = picked !== null ? t("web-main.relay.goTo", { place: placeName(picked.place) }) : t("web-main.relay.go");
  return { body, ready: picked !== null || link !== null, busy, go, label };
}

function RelayDialog({ station, thread, onClose }: { station: string; thread: number; onClose(): void }) {
  const relay = useRelay(station, thread, useToast(), onClose);
  return (
    <Dialog open onClose={onClose} title={t("web-main.relay.title")} description={t("web-main.relay.lead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={relay.busy} disabled={!relay.ready} onClick={relay.go}>{relay.label}</Button>
      </>}>
      {relay.body}
    </Dialog>
  );
}
