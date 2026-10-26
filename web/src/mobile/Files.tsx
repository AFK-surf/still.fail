// 文件 as a place of its own (the bottom bar's, Bar.tsx): every folder the workspace's stations lend, under a heading
// for each station (离线 beside it, its rows dimmed, while away), a station's home first where the viewer browses all of
// it; tapped, the folder's page (Drive.tsx), as from that station's page.
import { useStations } from "../api.ts";
import type { DriveRoot, StationView } from "../core/shapes.ts";
import { stationBase } from "../station.tsx";
import { drivePath } from "../drive/useDrive.ts";
import { ChevronRight, Folder, Server } from "@stillfail/ui/icons.tsx";
import { useApp, useRootPage } from "./app.tsx";
import { NavItem, NavPhone, NavSection } from "../SidebarList.tsx";
import { ListCard, ListRow, PlaceHead } from "./parts.tsx";
import { Waiting } from "@stillfail/ui/waiting.tsx";
import { usePlaceActions } from "./placeActions.tsx";
import * as listsCss from "./styles/lists.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as css from "./Files.css.ts";
import { t } from "../i18n.ts";
import { StationInWords } from "../StationNamed.tsx";
import { sampleDriveRoots, sampleStations } from "../samples.ts";

export function FilesScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id).value;
  const folders = (stations ?? []).flatMap((s) => (s.overview?.drive?.roots ?? []).map((root) => ({ station: s, root })));
  const root = useRootPage();
  // The bar's place: each station's home (where the viewer browses every folder of it), then its folders, as the wide screen's sidebar (../cloud/workspace.tsx FilesNav).
  const lending = (stations ?? []).flatMap((s) => {
    const drive = s.overview?.drive;
    const home = drive?.anywhere && drive.home ? drive.home : null;
    const roots = drive?.roots ?? [];
    return home || roots.length > 0 ? [{ station: s, home, roots }] : [];
  });
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <PlaceHead title={t("web-pages.drive.title")} back={t("web-mobile.settings.title")} onBack={app.pop} primary={usePlaceActions().files} />
      {/* Its folders are in each station's overview: none yet while one online is not read. */}
      {!stations || ((root ? lending.length : folders.length) === 0 && stations.some((s) => s.online && !s.overview))
        ? <Waiting {...(!stations ? { text: t("common.readingStations") } : {})} sample={root ? <Lending lending={SAMPLE_LENDING} onOpen={() => undefined} /> : <Folders folders={SAMPLE_FOLDERS} onOpen={() => undefined} />} />
        : (root ? lending.length : folders.length) === 0 ? <p className={css.mNone}>{t("web-main.rail.filesNone")}</p>
        : root ? <Lending lending={lending} onOpen={(station, path) => app.push(drivePath(stationBase(station.station), path))} />
        : <Folders folders={folders} onOpen={(station, root) => app.push(drivePath(stationBase(station.station), root.path))} />}
    </div>
  );
}

/** As the bar's place: each station's home (where the viewer browses every folder of it), then its folders. */
function Lending({ lending, onOpen }: { lending: { station: StationView; home: string | null; roots: DriveRoot[] }[]; onOpen(station: StationView, path: string): void }) {
  return (
    <NavPhone>
      {lending.map(({ station, home, roots }) => {
        const open = (path: string) => () => onOpen(station, path);
        return (
          <NavSection key={station.station} label={station.online ? station.name : t("web-pages.drive.stationAway", { name: station.name })}
            title={<StationInWords station={station.station} text={station.online ? station.name : t("web-pages.drive.stationAway", { name: station.name })} />}>
            {home && <NavItem onClick={open(home)} mark={<Server size={16} />} title={t("web-pages.drive.home")} away={!station.online} />}
            {roots.map((r) => <NavItem key={r.path} onClick={open(r.path)} mark={<Folder size={16} />} title={r.name} away={!station.online} />)}
          </NavSection>
        );
      })}
    </NavPhone>
  );
}

/** Every folder lent, on a card: its name, its station's. */
function Folders({ folders, onOpen }: { folders: { station: StationView; root: DriveRoot }[]; onOpen(station: StationView, root: DriveRoot): void }) {
  return (
    <ListCard>
      {folders.map(({ station, root }) => (
        <ListRow key={`${station.station}/${root.path}`} onClick={() => onOpen(station, root)}>
          <span className={css.mFolder} data-off={!station.online || undefined}><Folder size={22} /></span>
          <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{root.name}</span>
          <span className={css.mWhere} data-off={!station.online || undefined}>{station.name}</span>
          <ChevronRight size={14} className={partsCss.mSubtle} />
        </ListRow>
      ))}
    </ListCard>
  );
}

/** Stations and the folders they lend made up, for what the screen shows while they are read (in their bones). */
const SAMPLE_ROOTS = sampleDriveRoots();
const SAMPLE_LENDING = sampleStations(2).map((station, i) => ({ station, home: i === 0 ? "/sample" : null, roots: SAMPLE_ROOTS.slice(i * 2, i * 2 + 2) }));
const SAMPLE_FOLDERS = SAMPLE_LENDING.flatMap(({ station, roots }) => roots.map((root) => ({ station, root })));
