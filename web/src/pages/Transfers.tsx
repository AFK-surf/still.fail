// What the files' page shows of copies between folders and stations (docs/drive.md "Copying between stations"): the
// transfers' button on its bar (how many go, how far), its list (each copy's way, how it stands, stopped, tried again,
// its folder shown once done), and the dialog that asks about a name already where files go (drive/transfer.ts).
import { useEffect, useState } from "react";
import { Popover } from "radix-ui";
import { useTopic, core } from "../core/react.ts";
import type { DriveTransferShown, DriveTransfersView, StationView } from "../core/shapes.ts";
import { useStations } from "../api.ts";
import { useGo } from "../go.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Button, IconButton } from "../ui.tsx";
import { Check, ChevronRight, Close, Folder, Move, Retry, Server, Trash } from "@stillfail/ui/icons.tsx";
import { fileSize } from "@stillfail/ui/fileSize.ts";
import { transfer, useAsking, type Answer } from "../drive/transfer.ts";
import type { Dragged } from "../drive/drag.ts";
import { drive, drivePath, folderName, type PickFolder } from "../drive/useDrive.ts";
import { stationBase } from "../station.tsx";
import { Dialog } from "../ui.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./Files.css.ts";
import { t } from "../i18n.ts";
import { StationNamed } from "../StationNamed.tsx";

/** The person's transfers into the workspace's stations. */
export function useTransfers(scope: string): DriveTransferShown[] {
  return useTopic<DriveTransfersView>({ topic: "driveTransfers", workspace: scope }).value?.transfers ?? [];
}

/** On the files' page's bar: the transfers, how many go and how far they are; its list on a press. Nothing while there
 * has been none. */
export function TransfersButton({ scope }: { scope: string }) {
  const all = useTransfers(scope);
  const [open, setOpen] = useState(false);
  const going = all.filter((x) => x.active);
  if (all.length === 0) return null;
  const total = going.reduce((n, x) => n + x.total, 0);
  const copied = going.reduce((n, x) => n + x.copied, 0);
  const label = going.length > 0 ? t("web-pages.files.transfersGoing", { n: going.length, percent: Math.floor((total > 0 ? copied / total : 0) * 100) }) : t("web-pages.files.transfers");
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <button type="button" className={css.transfersChip} data-going={going.length > 0 || undefined} data-failed={all.some((x) => x.state === "failed") || undefined}>
          <Move size={14} />{label}
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.transfers}`} side="bottom" align="end" sideOffset={6} collisionPadding={8} onOpenAutoFocus={(e) => e.preventDefault()}>
          <div className={css.transfersHead}>{t("web-pages.files.transfers")}</div>
          {all.map((x) => <TransferRow key={`${x.station}\n${x.id}`} x={x} onShown={() => setOpen(false)} />)}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

function TransferRow({ x, onShown }: { x: DriveTransferShown; onShown: () => void }) {
  const act = useAct();
  const go = useGo();
  const call = (name: string) => act(core().call(name, { station: x.station, id: x.id }), t("web-pages.files.transferWhat"));
  const way = x.fromStation === x.station ? t("web-pages.files.into", { to: x.toText }) : t("web-pages.files.fromInto", { from: x.fromStationName, to: x.toText });
  return (
    <div className={css.transfer} data-state={x.state}>
      <span className={css.transferMark}>{x.state === "done" ? <Check size={14} /> : x.state === "failed" ? <Retry size={14} /> : x.state === "cancelled" ? <Close size={14} /> : <Move size={14} />}</span>
      <span className={css.transferText}>
        <span className={css.transferTitle}><b>{x.title}</b> <span>{x.move ? t("web-pages.files.moving", { way }) : way}</span></span>
        {x.state === "copying" && <span className={css.transferBar}><span style={{ transform: `scaleX(${x.progress})` }} /></span>}
        <span className={css.transferStatus} data-failed={x.state === "failed" || undefined}>
          {x.statusText}
          {x.state === "copying" && x.files > 1 && <> · {t("web-pages.files.filesCount", { n: x.files })}</>}
          {x.state === "done" && x.files > 1 && <> · {t("web-pages.files.filesCount", { n: x.files })}</>}
        </span>
      </span>
      <span className={css.transferActions}>
        {x.active && <IconButton label={t("web-pages.files.cancelTransfer")} icon={Close} onClick={() => call("drive.transfer.cancel")} />}
        {x.state === "failed" && <IconButton label={t("web-pages.drive.retry")} icon={Retry} onClick={() => call("drive.transfer.retry")} />}
        {x.state === "done" && (
          <Button variant="ghost" onClick={() => { onShown(); go(drivePath(stationBase(x.station), x.toRoot, x.toPath)); }}>{t("web-pages.files.show")}</Button>
        )}
      </span>
    </div>
  );
}

/** What is asked about a name already where files go: each name in turn, or all the rest the same way. */
export function TransferAsk() {
  const asking = useAsking();
  const [all, setAll] = useState(false);
  const [answers, setAnswers] = useState<Record<string, Answer>>({});
  if (!asking) return null;
  const left = asking.clashes.filter((c) => answers[c.name] === undefined);
  const now = left[0];
  const finish = (next: Record<string, Answer> | null) => {
    setAnswers({});
    setAll(false);
    asking.answer(next);
  };
  if (!now) return null;
  const answer = (a: Answer) => {
    const next = { ...answers, ...(all ? Object.fromEntries(left.map((c) => [c.name, a])) : { [now.name]: a }) };
    if (asking.clashes.every((c) => next[c.name] !== undefined)) finish(next);
    else setAnswers(next);
  };
  return (
    <Dialog open onClose={() => finish(null)} title={t(now.dir ? "web-pages.files.clashFolder" : "web-pages.files.clash", { folder: asking.intoName, name: now.name })}
      description={asking.clashes.length > 1 ? t("web-pages.files.clashCount", { n: asking.total, clashes: asking.clashes.length }) : undefined}
      footer={<>
        <Button variant="ghost" onClick={() => answer("skip")}>{t("web-pages.files.skip")}</Button>
        <Button onClick={() => answer("keep")}>{t("web-pages.drive.keepBoth")}</Button>
        <Button variant="primary" icon={Trash} onClick={() => answer("replace")}>{t("web-pages.drive.replace")}</Button>
      </>}>
      <dl className={css.clash}>
        <dt>{t("web-pages.files.coming")}</dt>
        <dd>{now.dir ? t("web-pages.files.folder") : fileSize(now.coming.size)} · {now.coming.station}</dd>
        <dt>{t("web-pages.files.there")}</dt>
        <dd>{now.there.dir ? t("web-pages.files.folder") : now.there.sizeText} · {now.there.timeText}</dd>
      </dl>
      <p className={css.clashNote}>{t("web-pages.files.replaceNote")}</p>
      {left.length > 1 && (
        <label className={css.clashAll}>
          <input type="checkbox" checked={all} onChange={(e) => setAll(e.target.checked)} />
          {t("web-pages.files.applyAll", { n: left.length - 1 })}
        </label>
      )}
    </Dialog>
  );
}

/**
 * 复制到… / 移动到…: a folder of any station of the workspace to put `items` in (a station's places on the left, the
 * folders where it is on the right, gone into with a click), then as a drop there (drive/transfer.ts). Stations the
 * person may not write to, or from before copies, are there but cannot be picked, saying why.
 */
export function CopyTo({ items, move, from, onClose }: { items: Dragged[]; move: boolean; from: string; onClose: () => void }) {
  const scope = from.split("/")[0] ?? "";
  const views = (useStations(scope).value ?? []).filter((s) => s.overview?.drive);
  const act = useAct();
  const [station, setStation] = useState(from);
  const s = views.find((v) => v.station === station);
  const d = s?.overview?.drive;
  const [where, setWhere] = useState<string | null>(null);
  const [listed, setListed] = useState<{ at: string; folders: PickFolder[]; places: PickFolder[]; crumbs: { name: string; path: string }[] } | null>(null);
  const start = d?.anywhere && d.home ? d.home : d?.roots[0]?.path ?? null;
  const at = where ?? start;
  useEffect(() => {
    if (!at || !d?.anywhere) return;
    let live = true;
    drive.folders(station, at).then((f) => { if (live) setListed({ at, folders: f.entries.filter((e) => !e.unreadable), places: f.places, crumbs: f.crumbs }); }, () => { if (live) setListed({ at, folders: [], places: [], crumbs: [] }); });
    return () => { live = false; };
  }, [station, at, d?.anywhere]);
  const why = (v: StationView) => (!v.online ? t("web-pages.stations.offline") : v.overview?.viewer?.role === "viewer" ? t("web-pages.files.readOnly") : v.overview?.drive?.transfers !== true && v.station !== from ? t("web-pages.files.needsUpdate") : null);
  const shown = listed && listed.at === at ? listed : null;
  const pick = () => {
    if (!at || !s) return;
    onClose();
    act(transfer(items, { station, root: at, path: "" }, move, folderName(at), d?.anywhere === true), t(move ? "web-pages.drive.moveWhat" : "web-pages.files.copyWhat"));
  };
  const what = items.length > 1 ? t("web-pages.files.itemsCount", { n: items.length }) : items[0]?.name ?? "";
  return (
    <Dialog open wide onClose={onClose} title={t(move ? "web-pages.files.moveToTitle" : "web-pages.files.copyToTitle", { what })}
      footer={<>
        <span className={css.copyWhere}>{s && at ? <><StationNamed emoji={s.emoji} icon={s.icon} name={s.name} />{` › ${at}`}</> : ""}</span>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" disabled={!at || !s || why(s) !== null} onClick={pick}>{t(move ? "web-pages.files.moveHereButton" : "web-pages.files.copyHereButton")}</Button>
      </>}>
      <div className={css.copyTo}>
        <div className={css.copyStations}>
          {views.map((v) => {
            const no = why(v);
            return (
              <button key={v.station} type="button" className={css.copyRow} data-on={v.station === station || undefined} disabled={no !== null}
                onClick={() => { setStation(v.station); setWhere(null); setListed(null); }}>
                <Server size={16} /><span>{v.name}</span>{no && <small>{no}</small>}
              </button>
            );
          })}
        </div>
        <div className={css.copyFolders}>
          {shown && shown.crumbs.length > 0 && (
            <div className={css.copyCrumbs}>
              {shown.crumbs.map((c, i) => <button key={c.path} type="button" data-last={i === shown.crumbs.length - 1 || undefined} onClick={() => setWhere(c.path)}>{c.name}</button>)}
            </div>
          )}
          {!d?.anywhere && d?.roots.map((r) => (
            <button key={r.path} type="button" className={css.copyRow} data-on={at === r.path || undefined} onClick={() => setWhere(r.path)}><Folder size={16} /><span>{r.name}</span></button>
          ))}
          {d?.anywhere && !shown && <p className={css.copyNote}>{t("web-pages.files.reading")}</p>}
          {shown && shown.folders.length === 0 && <p className={css.copyNote}>{t("web-pages.drive.noSubfolders")}</p>}
          {shown?.folders.map((f) => (
            <button key={f.path} type="button" className={css.copyRow} onClick={() => setWhere(f.path)}><Folder size={16} /><span>{f.name}</span><ChevronRight size={12} /></button>
          ))}
        </div>
      </div>
    </Dialog>
  );
}
