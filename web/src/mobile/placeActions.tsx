// Each place's primary action (docs/mobile-parity.md, 下方栏): what the bottom bar's notch holds on its top page, and its
// head's ＋ when it is opened from elsewhere. The chats' family has 令 (a new chat); a place with a primary ＋ has it
// (a station, a profile, a connect, a folder lent), when the viewer may (a manager; a station online to put it on);
// the rest none, and the notch closes.
import { useStations, type StationView } from "../api.ts";
import { t } from "../i18n.ts";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import type { BarPlace } from "./Bar.tsx";
import { PickerSheet } from "./Drive.tsx";
import { PickStation } from "./Profiles.tsx";
import { AddStationSheet, useManager } from "./Stations.tsx";
import { PickRow, type PlaceAction } from "./parts.tsx";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as partsCss from "./styles/parts.css.ts";

export function usePlaceActions(): Partial<Record<BarPlace, PlaceAction>> {
  const app = useApp();
  const list = useStations(app.entry.id).value;
  const manager = useManager();
  const online = list?.filter((s) => s.online) ?? [];
  const actions: Partial<Record<BarPlace, PlaceAction>> = {};
  const ling: PlaceAction = { key: "ling", label: t("web-mobile.home.newChat"), run: () => app.open(app.at("/new")) };
  actions.chats = actions.archive = ling;
  if (manager && list) {
    actions.stations = {
      key: "station", label: t("web-mobile.stations.add"),
      run: () => app.sheet({ height: 0.72, draggable: true, content: () => <AddStationSheet known={list.map((s) => s.id)} /> }),
    };
  }
  // On a station: the one online, or picked from those that are.
  const onOne = (label: string, path: string) => () => online.length === 1
    ? app.push(app.at(`/s/${online[0]!.id}/${path}`))
    : app.sheet({ height: 0.5, content: () => <PickStation title={label} stations={online} to={(s) => `/s/${s.id}/${path}`} /> });
  if (online.length > 0) {
    actions.profiles = { key: "profile", label: t("web-mobile.newChat.addProfile"), run: onOne(t("web-mobile.newChat.addProfile"), "profiles/new") };
    actions.connects = { key: "connect", label: t("web-mobile.connects.add"), run: onOne(t("web-mobile.connects.add"), "connects/new") };
  }
  if (manager && online.length > 0) {
    const pick = (s: StationView) => app.sheet({ height: 0.85, draggable: true, content: () => <PickerSheet station={s.station} roots={s.overview?.drive?.roots ?? []} /> });
    actions.files = {
      key: "folder", label: t("web-pages.drive.addRoot"),
      run: () => online.length === 1 ? pick(online[0]!) : app.sheet({ height: 0.5, content: () => <PickLender stations={online} pick={pick} /> }),
    };
  }
  return actions;
}

/** Which station a folder is lent from, with more than one online. */
function PickLender({ stations, pick }: { stations: StationView[]; pick: (s: StationView) => void }) {
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.drive.addRoot")} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>{t("web-mobile.profiles.whichStation")}</p>
        {stations.map((s) => <PickRow key={s.id} label={s.name} onClick={() => pick(s)} />)}
      </div>
    </>
  );
}
