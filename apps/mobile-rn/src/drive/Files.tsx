// 文件 as a place of the bottom bar (drive/Files.kt; Places.tsx): every station's lent folders (docs/drive.md), under a
// heading for each station, each opening its folder's page (DriveScreen.tsx); a "+" (in the bar's notch) lends another,
// on a station the viewer may name folders on.
import { useContext } from "react";
import { FlatList, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTopic } from "../../../../web/src/core/react.ts";
import type { DriveRoot, StationView } from "../../../../web/src/core/shapes.ts";
import { SheetSpec, app } from "../AppState";
import { manager, type WorkspaceEntry, type WorkspaceView } from "../data/Accounts";
import { t } from "../i18n";
import { LocalBarRoom } from "../Places";
import { PlacePage } from "../screens/PlacePage";
import { PlaceRow } from "../screens/PlaceRows";
import { BarAction } from "../ui/Bar";
import { PickRow } from "../ui/Controls";
import { Icons } from "../ui/IconSet";
import { IconIn, SectionHeader } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { Waiting } from "../ui/Waiting";
import { openFolderPicker } from "./DriveScreen";

/** A folder lent, and the station it is on; `home` the station's home (every folder of it). */
interface Lent { s: StationView; root: DriveRoot; home: boolean }

type Item = { key: string; header: string } | { key: string; lent: Lent };

export function FilesScreen({ current }: { current: WorkspaceEntry }) {
  const C = useC();
  const ws = current.workspace;
  const stations = useTopic<StationView[]>({ topic: "stations", scope: ws.id });
  const workspace = useTopic<WorkspaceView>({ topic: "workspace", workspace: ws.id });
  const list = stations.value;
  // Each station's home first, for a member who browses every folder of it (as the web's sidebar), then its folders lent.
  const lent: Lent[] = (list ?? []).flatMap((s) => {
    const drive = s.overview?.drive;
    const home = drive?.anywhere === true ? drive.home : undefined;
    return [
      ...(home ? [{ s, root: { path: home, name: t("web-pages.drive.home"), state: "ok" as const }, home: true }] : []),
      ...(drive?.roots ?? []).map((root) => ({ s, root, home: false })),
    ];
  });
  // Where another folder can be lent: a station online that has a drive (a station from before it has none), by
  // whoever may name its folders (the workspace's owners and admins).
  const lenders = workspace.value !== undefined && manager(workspace.value) ? (list ?? []).filter((it) => it.online && it.overview?.drive !== undefined) : [];
  const add = lenders.length > 0 ? new BarAction("lend-folder", t("android-misc.bar.action.files"), Icons.Plus, () => lend(lenders)) : null;
  const room = useContext(LocalBarRoom);
  const insets = useSafeAreaInsets();
  const foot = insets.bottom + 30 + room;
  const known = (list !== undefined || stations.error !== null) && (workspace.value !== undefined || workspace.error !== null);
  return (
    <PlacePage current={current} place="files" primary={add} known={known} content={(top: number) => {
      // The stations, or a station up whose folders are not here yet: not "none lent" before it is known.
      if (list === undefined || (lent.length === 0 && list.some((it) => it.online && it.overview === undefined))) {
        return <Waiting text={t("common.reading")} error={stations.error?.message ?? null} style={{ paddingTop: top }} />;
      }
      if (lent.length === 0) {
        return (
          <View style={{ paddingTop: top }}>
            <View style={{ paddingHorizontal: 32, paddingVertical: 56, alignItems: "center", gap: 12 }}>
              <IconIn icon={Icons.Folder} size={40} tint={C.subtle} />
              <T size={14} color={C.muted} align="center">{lenders.length > 0 ? t("android-misc.files.none.manager") : t("android-misc.files.none.member")}</T>
            </View>
          </View>
        );
      }
      // A heading for each station (its name; 离线 beside it while away), its folders under it.
      const items: Item[] = [];
      const seen = new Set<string>();
      for (const l of lent) {
        if (seen.has(l.s.station)) continue;
        seen.add(l.s.station);
        const s = l.s;
        items.push({ key: `station|${s.station}`, header: s.online ? s.name : t("web-pages.drive.stationAway", { name: s.name }) });
        for (const r of lent.filter((it) => it.s.station === s.station)) items.push({ key: `${r.s.station}|${r.root.path}`, lent: r });
      }
      return (
        <FlatList
          style={{ flex: 1 }}
          contentContainerStyle={{ paddingTop: top, paddingBottom: foot }}
          data={items}
          keyExtractor={(it) => it.key}
          renderItem={({ item }) => ("header" in item ? <SectionHeader title={item.header} /> : <FolderRow l={item.lent} />)}
        />
      );
    }} />
  );
}

/** A folder, as the desktop sidebar's: its mark (a station's home the station's), its name (faint while the station is away). */
function FolderRow({ l }: { l: Lent }) {
  const C = useC();
  return (
    <PlaceRow
      title={l.root.name} onClick={() => app.push({ kind: "Drive", station: l.s.station, root: l.root.path, path: "" })} away={!l.s.online}
      mark={<IconIn icon={l.home ? Icons.Server : Icons.Folder} size={16} tint={C.muted} />}
    />
  );
}

/** Another folder lent: on the one station there is, or the one chosen first. */
function lend(on: StationView[]) {
  const pick = (s: StationView) => openFolderPicker(s.station, (s.overview?.drive?.roots ?? []).map((it) => it.path));
  if (on.length === 1) return pick(on[0]!);
  app.sheet = new SheetSpec(0.4, false, 96 + on.length * 48 + 24, null, false, () => (
      <>
        <SheetGrab />
        <SheetHead title={t("android-misc.files.lendOn")} />
        {on.map((s) => <PickRow key={s.station} label={s.name} onClick={() => { app.sheet = null; pick(s); }} />)}
        <View style={{ height: 12 }} />
      </>
    ));
}
