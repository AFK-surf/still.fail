// Going somewhere on the files' page (docs/drive.md "The files' page"): another station from a folder's trail (the
// station's button at its start: the same folder there when it has one, else its home; ⌥ in a new tab), and a folder
// by its path (⌘⇧G, as Finder's 前往文件夹): `mba:~/Projects` names the station before the colon, `~` its home, a path
// without a slash in front is under the folder shown; Tab completes a folder's name, as a terminal does.
import { useEffect, useRef, useState } from "react";
import { DropdownMenu } from "radix-ui";
import { useDriveStations } from "../api.ts";
import { useGo } from "../go.ts";
import { useToast } from "@stillfail/ui/toast.tsx";
import { useCall } from "../core/react.ts";
import type { StationView } from "../core/shapes.ts";
import { stationBase } from "../station.tsx";
import { useThisMachineAddress } from "../thisMachine.ts";
import { Dialog } from "../ui.tsx";
import { StationMark } from "../StationMark.tsx";
import { ChevronDown, Folder, Monitor, Server } from "@stillfail/ui/icons.tsx";
import { absoluteOf, childOf, drive, drivePath } from "../drive/useDrive.ts";
import { useFilesActions } from "./Files.tsx";
import type { Pane } from "../drive/tabs.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./FilesGo.css.ts";
import { t } from "../i18n.ts";

/** A folder typed by its path, worked out (`files.go`): the station, the folder it names, the folder it is in and what is
 * typed of its last part. */
interface Typed { station: string; abs: string; parent: string; partial: string }

/** Where to open `station` from the folder `abs` of another one: the same folder when it has one, else its home (or the
 * first folder it pins, for a read-only member); null when it has neither. `same`: it had the same folder. */
async function sameOrHome(s: StationView, abs: string): Promise<{ root: string; same: boolean } | null> {
  const d = s.overview?.drive;
  if (!d) return null;
  if (d.anywhere && d.home) {
    const there = await drive.folders(s.station, abs).then((f) => !f.unreadable, () => false);
    return there ? { root: abs, same: true } : { root: d.home, same: false };
  }
  const first = d.roots[0]?.path;
  return first ? { root: first, same: false } : null;
}

/** The station's button before a folder's trail: the workspace's stations, the one shown checked. */
export function StationSwitch({ station, abs }: { station: string; abs: string }) {
  const scope = station.split("/")[0] ?? "";
  const views = useDriveStations(scope).value ?? [];
  const here = useThisMachineAddress();
  const go = useGo();
  const toast = useToast();
  const files = useFilesActions();
  const current = views.find((s) => s.station === station);
  // ⌥ held as a station is picked: it opens in a new tab.
  const alt = useRef(false);
  const pick = async (s: StationView, e: { altKey: boolean }) => {
    if (s.station === station) return;
    const to = await sameOrHome(s, abs);
    if (!to) return;
    if (!to.same) toast(t("web-pages.files.notThere", { name: s.name }));
    const pane: Pane = { station: s.station, root: to.root, path: "" };
    if (e.altKey && files) files.open(pane, "tab");
    else go(drivePath(stationBase(s.station), to.root));
  };
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger asChild>
        <button type="button" className={css.switchButton} aria-label={t("web-pages.files.switchStation")}>
          {current?.emoji || current?.icon ? <StationMark emoji={current.emoji} icon={current.icon} size={14} /> : station === here ? <Monitor size={14} /> : <Server size={14} />}
          <span>{current?.name ?? ""}</span>
          <ChevronDown size={12} strokeWidth={2} />
        </button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList} ${css.stations}`} align="start" sideOffset={4} collisionPadding={8}>
          {views.map((s) => (
            <DropdownMenu.Item key={s.station} className={controlsCss.menuItem} disabled={!s.online} data-on={s.station === station || undefined}
              onPointerDown={(e) => { alt.current = e.altKey; }} onKeyDown={(e) => { alt.current = e.altKey; }}
              onSelect={() => void pick(s, { altKey: alt.current })}>
              {s.emoji || s.icon ? <StationMark emoji={s.emoji} icon={s.icon} size={16} /> : s.station === here ? <Monitor size={16} /> : <Server size={16} />}
              <span className={css.stationName}>{s.name}</span>
              <span className={css.stationMeta}>
                {[s.station === here ? t("web-pages.files.thisMachine") : null, s.station === station ? t("web-pages.files.current") : null, !s.online ? t("web-pages.stations.offline") : null].filter(Boolean).join(" · ")}
              </span>
            </DropdownMenu.Item>
          ))}
          <div className={css.stationsFoot}>{t("web-pages.files.switchNote")}</div>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

/** ⌘⇧G: a folder by its path, of any station of the workspace. */
export function GoTo({ scope, here, onClose }: { scope: string; here: Pane; onClose: () => void }) {
  const known = useDriveStations(scope).value;
  const views = known ?? [];
  const go = useGo();
  const call = useCall();
  const from = { station: here.station, abs: absoluteOf(here.root, here.path) };
  const [typed, setTyped] = useState("");
  const [at, setAt] = useState(0);
  const [folders, setFolders] = useState<{ station: string; parent: string; names: string[] } | null>(null);
  // What is typed, worked out by the core as it changes (the last answer for what is typed now).
  const resolve = (text: string) => call("files.go", { workspace: scope, typed: text, ...from }) as Promise<Typed | null>;
  const [resolvedFor, setResolved] = useState<{ typed: string; resolved: Typed | null } | null>(null);
  useEffect(() => {
    let live = true;
    resolve(typed).then((r) => { if (live) setResolved({ typed, resolved: r }); }, () => undefined);
    return () => { live = false; };
  }, [typed, known, from.station, from.abs]); // eslint-disable-line react-hooks/exhaustive-deps
  const resolved = resolvedFor?.resolved ?? null;
  const named = views.find((v) => v.station === resolved?.station);
  // The folders where the last part is being typed, read as the way to it changes.
  const asked = useRef("");
  useEffect(() => {
    if (!resolved || !named?.overview?.drive?.anywhere) return;
    const key = `${resolved.station}\n${resolved.parent}`;
    if (asked.current === key) return;
    asked.current = key;
    drive.folders(resolved.station, resolved.parent).then(
      (f) => { if (asked.current === key) setFolders({ station: resolved.station, parent: resolved.parent, names: f.entries.map((e) => e.name) }); },
      () => { if (asked.current === key) setFolders({ station: resolved.station, parent: resolved.parent, names: [] }); },
    );
  }, [resolved?.station, resolved?.parent, named]); // eslint-disable-line react-hooks/exhaustive-deps
  const prefix = (s: StationView) => (s.station === here.station && !typed.includes(":") ? "" : `${s.name.toLowerCase()}:`);
  // Stations while their name is typed (nothing before a colon yet), then folders whose name starts with what is typed.
  const stationsTyped = !typed.includes(":") && !typed.startsWith("/") && !typed.startsWith("~") && typed !== ""
    ? views.filter((v) => v.name.toLowerCase().startsWith(typed.toLowerCase())) : [];
  const matches = resolved && folders && folders.station === resolved.station && folders.parent === resolved.parent
    ? folders.names.filter((n) => !n.startsWith(".") && n.toLowerCase().startsWith(resolved.partial.toLowerCase())).slice(0, 8).map((n) => childOf(resolved.parent, n)) : [];
  const rows: { label: string; complete: string; target: { station: string; abs: string } | null }[] = [
    ...stationsTyped.map((s) => ({ label: s.name, complete: `${s.name.toLowerCase()}:~/`, target: s.overview?.drive?.home ? { station: s.station, abs: s.overview.drive.home } : null })),
    ...(resolved && named ? matches.map((abs) => ({ label: `${named.name} › ${abs}`, complete: `${prefix(named)}${abs}/`, target: { station: resolved.station, abs } })) : []),
  ];
  const chosen = rows[Math.min(at, rows.length - 1)];
  const open = (target: { station: string; abs: string } | null) => {
    if (!target) return;
    onClose();
    go(drivePath(stationBase(target.station), target.abs));
  };
  return (
    <Dialog open onClose={onClose} title={t("web-pages.files.goTo")} description={t("web-pages.files.goToNote")}>
      <input className={`${controlsCss.input} ${css.goInput}`} autoFocus spellCheck={false} value={typed} placeholder={t("web-pages.files.goToPlaceholder")}
        aria-label={t("web-pages.files.goTo")}
        onChange={(e) => { setTyped(e.target.value); setAt(0); }}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return;
          if (e.key === "ArrowDown") { e.preventDefault(); setAt((n) => Math.min(rows.length - 1, n + 1)); }
          else if (e.key === "ArrowUp") { e.preventDefault(); setAt((n) => Math.max(0, n - 1)); }
          else if (e.key === "Tab" && chosen) { e.preventDefault(); setTyped(chosen.complete); setAt(0); }
          else if (e.key === "Enter") {
            e.preventDefault();
            // As typed now, whatever came back for what was typed before.
            const now = typed;
            const enter = (r: Typed | null) => open(chosen && rows.length > 0 && r?.partial ? chosen.target : r ? { station: r.station, abs: r.abs } : chosen?.target ?? null);
            if (resolvedFor?.typed === now) enter(resolved);
            else resolve(now).then(enter, () => undefined);
          }
        }} />
      {resolved && named && <p className={css.goWhere}>{named.name} › {resolved.abs}</p>}
      {rows.length > 0 && (
        <div className={css.goList} role="listbox">
          {rows.map((r, i) => (
            <button key={r.complete} type="button" role="option" aria-selected={i === at} className={css.goRow} data-on={i === at || undefined}
              onMouseEnter={() => setAt(i)} onClick={() => open(r.target)}>
              <Folder size={16} /><span>{r.label}</span>{i === at && <kbd>Tab</kbd>}
            </button>
          ))}
        </div>
      )}
      <p className={css.goKeys}>{t("web-pages.files.goToKeys")}</p>
    </Dialog>
  );
}
