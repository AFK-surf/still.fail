// A chat relayed to a channel (docs/relay.md): from its title bar, ⌘K or its row's menu, a dialog lists the channels
// and groups the station's connects' bots are in, by connect (Slack, Feishu, Lark), found by typing; one picked, with
// a note if wanted, 接力 has the station start the conversation there and the chat's agent go on in it too. A Slack
// message's link typed (pasted) into the search offers that message's thread instead.
import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
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
  const shown = useSyncExternalStore((l) => { listeners.add(l); return () => { listeners.delete(l); }; }, () => asked);
  if (shown === null) return null;
  return <RelayDialog key={`${shown.station}/${shown.thread}`} station={shown.station} thread={shown.thread} onClose={() => { asked = null; tell(); }} />;
}

/** Read as the dialog opens: being read, read, or why not. */
type Read = { reading: true } | { ok: RelayConnect[] } | { error: string };

/** How a place says what relaying there does: a new thread, a new topic, or the group's conversation taken over. */
const kindNote = (p: RelayPlace) => t(p.kind === "channel" ? "web-main.relay.kind.channel" : p.kind === "topics" ? "web-main.relay.kind.topics" : "web-main.relay.kind.group");

/** Whether what was typed is a link to a Slack message (the station finds its workspace among its connects'). */
const slackLink = (typed: string) => /^https?:\/\/[^/\s]+\/archives\/[A-Z0-9]+\/p\d{16}/.test(typed.trim());

const platform = (c: RelayConnect) => (c.kind === "slack" ? "Slack" : c.kind === "lark" ? "Lark" : t("web-pages.connect.feishu.name"));

function RelayDialog({ station, thread, onClose }: { station: string; thread: number; onClose(): void }) {
  const call = useStationCall(station);
  const api = stationApi(call);
  const toast = useToast();
  const [read, setRead] = useState<Read>({ reading: true });
  const [query, setQuery] = useState("");
  const [picked, setPicked] = useState<{ connect: string; place: RelayPlace } | null>(null);
  const link = slackLink(query) ? query.trim() : null;
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let gone = false;
    stationApi(call).relayPlaces(thread).then((r) => { if (!gone) setRead({ ok: r.connects }); }, (e: unknown) => { if (!gone) setRead({ error: failure(e) }); });
    return () => { gone = true; };
  }, [call, thread]);
  const connects = "ok" in read ? read.ok : [];
  const q = query.trim().toLowerCase();
  const shown = useMemo(() => connects.map((c) => ({ ...c, places: q === "" ? c.places : c.places.filter((p) => p.name.toLowerCase().includes(q)) })), [connects, q]);
  const go = () => {
    const to = link !== null ? { link } : picked !== null ? { connect: picked.connect, channel: picked.place.id } : null;
    if (to === null) return;
    setBusy(true);
    api.relay(thread, to, note).then(
      (done) => { toast(t("web-main.relay.done", { place: done.place })); onClose(); },
      (e: unknown) => { setBusy(false); toast(t("web-main.act.failed", { what: t("web-main.relay.verb"), error: failure(e) })); },
    );
  };
  let list;
  if (link !== null) {
    list = (
      <div className={css.list} role="listbox" aria-label={t("web-main.relay.places")}>
        <button type="button" role="option" aria-selected className={css.place} data-on>
          <span className={css.placeName}>{t("web-main.relay.thread")}</span>
          <span className={css.placeNote}>{t("web-main.relay.kind.thread")}</span>
        </button>
      </div>
    );
  } else if ("reading" in read) list = <WaitLine text={t("web-main.relay.reading")} />;
  else if ("error" in read) list = <p className={controlsCss.fieldError} role="alert">{read.error}</p>;
  else if (connects.length === 0) list = <p className={css.empty}>{t("web-main.relay.noConnects")}</p>;
  else {
    list = (
      <div className={css.list} role="listbox" aria-label={t("web-main.relay.places")}>
        {shown.map((c) => (
          <div key={c.id} className={css.group}>
            <div className={css.groupHead}><ElsewhereLogo kind={c.kind === "slack" ? "slack" : "feishu"} size={13} />{platform(c)} · {c.team ?? c.name}</div>
            {c.error && <p className={controlsCss.fieldError}>{t("web-main.relay.unread", { error: c.error })}</p>}
            {!c.error && c.places.length === 0 && <p className={css.empty}>{q === "" ? t("web-main.relay.noPlaces") : t("web-main.relay.noMatch")}</p>}
            {c.places.map((p) => {
              const on = picked?.connect === c.id && picked.place.id === p.id;
              return (
                <button key={p.id} type="button" role="option" aria-selected={on} className={css.place} data-on={on || undefined} onClick={() => setPicked({ connect: c.id, place: p })}>
                  <span className={css.placeName}>{p.kind === "channel" ? `${p.private ? "🔒 " : ""}#${p.name}` : p.name}</span>
                  <span className={css.placeNote} title={p.kind === "group" ? t("web-main.relay.kind.groupNote") : undefined}>{kindNote(p)}</span>
                </button>
              );
            })}
          </div>
        ))}
      </div>
    );
  }
  return (
    <Dialog open onClose={onClose} title={t("web-main.relay.title")} description={t("web-main.relay.lead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={busy} disabled={picked === null && link === null} onClick={go}>{t("web-main.relay.go")}</Button>
      </>}>
      <div className={css.body}>
        <input className={controlsCss.input} type="search" autoFocus value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t("web-main.relay.searchOrLink")} aria-label={t("web-main.relay.search")} />
        {list}
        <label className={css.noteField}>
          <span className={css.noteLabel}>{t("web-main.relay.note")}</span>
          <input className={controlsCss.input} value={note} maxLength={2000} onChange={(e) => setNote(e.target.value)} placeholder={t("web-main.relay.notePlaceholder")} />
        </label>
      </div>
    </Dialog>
  );
}
