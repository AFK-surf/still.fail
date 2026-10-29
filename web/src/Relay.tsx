// A chat relayed to a channel (docs/relay.md): from its title bar, ⌘K or its row's menu, a dialog offers the channels
// and groups one of the station's connects' bots is in (Slack, Feishu, Lark; the chat's own bot as it opens, another
// picked above), those relayed to before first, found by typing;
// one picked, with a note if wanted, 接力 has the station start the conversation there and the chat's agent go on in it too. A Slack
// message's link typed (pasted) into the search offers that message's thread instead. An `@` typed in the note offers
// the people of the place picked, to mention there. The phone's sheet
// (mobile/Chat.tsx RelaySheet) picks the same way (useRelay).
import { useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { mentionView, relayView, type RelayPerson, type RelayRow } from "../../client/core-ts/src/relay-pick.ts";
import { stationApi, useStationCall, type RelayConnect } from "./api.ts";
import { Button, ConnectAvatar, Dialog, ElsewhereLogo, WaitLine } from "./ui.tsx";
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

/**
 * The picking itself, the same on the wide screen's dialog and the phone's sheet: the bot to go on through when there
 * are several (the chat's own as it opens), the search (or a Slack link), its places relayed to before as it opens (all of them asked for or
 * searched), the one picked with the note; `go` relays to what was picked, said by `say`, then `onDone`. `focus`: the
 * search is focused as it opens (not on a phone, where that brings up the keyboard over the list).
 */
export function useRelay(station: string, thread: number, say: (text: string) => void, onDone: () => void, focus = true) {
  const call = useStationCall(station);
  const api = stationApi(call);
  const [read, setRead] = useState<Read>({ reading: true });
  const [query, setQuery] = useState("");
  const [chosen, setChosen] = useState<string | null>(null);
  const [all, setAll] = useState(false);
  const [picked, setPicked] = useState<RelayRow | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  // The people of the place picked, read once an `@` is typed in the note (null: not asked yet), and the note's field.
  const [people, setPeople] = useState<{ of: string; people: RelayPerson[] } | null>(null);
  const noteField = useRef<HTMLInputElement>(null);
  useEffect(() => {
    let gone = false;
    stationApi(call).relayPlaces(thread).then((r) => { if (!gone) setRead({ ok: r.connects }); }, (e: unknown) => { if (!gone) setRead({ error: failure(e) }); });
    return () => { gone = true; };
  }, [call, thread]);
  const connects = "ok" in read ? read.ok : [];
  const view = useMemo(() => relayView(connects, query, all, chosen, t), [connects, query, all, chosen]);
  const link = view.link;
  const bot = connects.find((c) => c.id === view.bot) ?? null;
  const via = (id: string) => connects.find((c) => c.id === id) ?? null;
  const to = link !== null ? { link, ...(bot !== null ? { connect: bot.id } : {}) } : picked !== null ? { connect: picked.connect, channel: picked.place.id } : null;
  const toKey = to === null ? "" : JSON.stringify(to);
  const typing = to !== null && note.includes("@");
  useEffect(() => {
    if (!typing || people?.of === toKey) return;
    let gone = false;
    setPeople({ of: toKey, people: [] });
    api.relayPeople(thread, JSON.parse(toKey)).then((r) => { if (!gone) setPeople({ of: toKey, people: r.people }); }, () => {});
    return () => { gone = true; };
  }, [typing, toKey]); // eslint-disable-line react-hooks/exhaustive-deps
  const mentions = mentionView(people?.of === toKey ? people.people : [], note).rows;
  const mention = (p: { note: string }) => { setNote(p.note); noteField.current?.focus(); };
  const go = () => {
    if (to === null) return;
    setBusy(true);
    api.relay(thread, to, note).then(
      (done) => { say(t("web-main.relay.done", { place: done.place })); onDone(); },
      (e: unknown) => { setBusy(false); say(t("web-main.act.failed", { what: t("web-main.relay.verb"), error: failure(e) })); },
    );
  };
  const row = (r: RelayRow, on: boolean, end: ReactNode, onClick: () => void) => (
    <button key={`${r.connect}/${r.place.id}`} type="button" role="option" aria-selected={on} className={css.place} data-on={on || undefined} onClick={onClick}>
      <ElsewhereLogo kind={r.kind === "slack" ? "slack" : "feishu"} size={16} />
      <span className={css.placeName}>{r.name}</span>
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
        {bot !== null && <Via connect={bot} />}
      </div>
    );
  } else if (picked !== null) {
    list = (
      <div className={css.list} role="listbox" aria-label={t("web-main.relay.places")}>
        {row(picked, true, <>{picked.note} · <span className={css.change}>{t("web-main.relay.change")}</span></>, () => setPicked(null))}
        {via(picked.connect) !== null && <Via connect={via(picked.connect)!} />}
      </div>
    );
  } else if ("reading" in read) list = <WaitLine text={t("web-main.relay.reading")} />;
  else if ("error" in read) list = <p className={controlsCss.fieldError} role="alert">{read.error}</p>;
  else if (connects.length === 0) list = <p className={css.empty}>{t("web-main.relay.noConnects")}</p>;
  else {
    list = (
      <>
        <div className={css.list} role="listbox" aria-label={t("web-main.relay.places")}>
          {view.recent && <div className={css.groupHead}>{t("web-main.relay.recent")}</div>}
          {view.rows.map((r) => row(r, false, r.aside, () => setPicked(r)))}
          {view.empty !== null && <p className={css.empty}>{t(view.empty === "noPlaces" ? "web-main.relay.noPlaces" : "web-main.relay.noMatch")}</p>}
          {view.recent && view.total > view.rows.length && <button type="button" className={css.more} onClick={() => setAll(true)}>{t("web-main.relay.showAll", { count: view.total })}</button>}
          {view.unread.map((error) => <p key={error} className={css.unread}>{t("web-main.relay.unread", { error })}</p>)}
        </div>
      </>
    );
  }
  const bots = view.bots.length > 0 && picked === null && link === null && (
    <div className={css.scopes} role="group" aria-label={t("web-main.relay.bots")}>
      {view.bots.map((b) => (
        <button key={b.id} type="button" className={css.scope} data-on={b.id === view.bot || undefined} aria-pressed={b.id === view.bot} onClick={() => { setChosen(b.id); setAll(false); }}>
          {via(b.id) !== null && <ConnectAvatar connect={via(b.id)!} size={16} />}<span className={css.scopeName}>{b.label}</span>
        </button>
      ))}
    </div>
  );
  const body = (
    <div className={css.body}>
      {bots}
      {picked === null && <input className={controlsCss.input} type="search" autoFocus={focus} value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("web-main.relay.searchOrLink")} aria-label={t("web-main.relay.search")} />}
      {list}
      {(picked !== null || link !== null) && (
        <div className={css.noteField}>
          <label className={css.noteField}>
            <span className={css.noteLabel}>{t("web-main.relay.note")}</span>
            <input ref={noteField} className={controlsCss.input} value={note} maxLength={2000} autoFocus={focus} onChange={(e) => setNote(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && mentions[0] !== undefined) { e.preventDefault(); mention(mentions[0]); } }}
              placeholder={t("web-main.relay.notePlaceholder")} />
          </label>
          {mentions.length > 0 && (
            <div className={css.list} role="listbox" aria-label={t("web-main.relay.people")}>
              {mentions.map((p) => (
                <button key={p.id} type="button" role="option" aria-selected={false} className={css.place} onClick={() => mention(p)}>
                  <Picture person={p} />
                  <span className={css.placeName}>{p.name}</span>
                  {p.aka !== undefined && <span className={css.placeNote}>{p.aka}</span>}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
  const label = picked !== null ? t("web-main.relay.goTo", { place: picked.name }) : t("web-main.relay.go");
  return { body, ready: picked !== null || link !== null, busy, go, label };
}

/** Which bot the agent speaks through there, its picture before its name (「那里由 [picture] Claude 回复」). */
function Via({ connect }: { connect: RelayConnect }) {
  const [before, after = ""] = t("web-main.relay.via", { bot: BOT }).split(BOT);
  return (
    <p className={css.via}>
      {before}<span className={css.viaBot}><ConnectAvatar connect={connect} size={16} />{connect.name}</span>{after}
    </p>
  );
}

/** A person's picture, their initial till it is here or without one. */
function Picture({ person }: { person: RelayPerson }) {
  const [failed, setFailed] = useState(false);
  return (
    <span className={css.person} aria-hidden>
      {person.picture !== undefined && !failed ? <img className={css.personImage} src={person.picture} alt="" referrerPolicy="no-referrer" onError={() => setFailed(true)} /> : ([...person.name.trim()][0] ?? "?").toUpperCase()}
    </span>
  );
}

/** Where the bot's name is in the words that say it, split there. */
const BOT = "\uE000";

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
