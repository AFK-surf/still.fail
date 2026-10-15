// 文件 as a place of its own (the bottom bar's, Bar.tsx): every folder the workspace's stations lend, in one list —
// a row each, its name, the station it is on at its end (an offline station's rows dimmed); tapped, the folder's page
// (Drive.tsx), as from that station's page.
import { useStations } from "../api.ts";
import { stationBase } from "../station.tsx";
import { drivePath } from "../drive/useDrive.ts";
import { ChevronRight, Folder } from "../icons.tsx";
import { useApp } from "./app.tsx";
import { ListCard, ListRow, Loading, PlaceHead } from "./parts.tsx";
import { usePlaceActions } from "./placeActions.tsx";
import * as listsCss from "./styles/lists.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as css from "./Files.css.ts";
import { t } from "../i18n.ts";

export function FilesScreen() {
  const app = useApp();
  const stations = useStations(app.entry.id).value;
  const folders = (stations ?? []).flatMap((s) => (s.overview?.drive?.roots ?? []).map((root) => ({ station: s, root })));
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <PlaceHead title={t("web-pages.drive.title")} back={t("web-mobile.settings.title")} onBack={app.pop} primary={usePlaceActions().files} />
      {!stations ? <Loading text={t("web-mobile.reading")} />
        : folders.length === 0 ? <p className={css.mNone}>{t("web-main.rail.filesNone")}</p>
        : (
          <ListCard>
            {folders.map(({ station, root }) => (
              <ListRow key={`${station.station}/${root.path}`} onClick={() => app.push(drivePath(stationBase(station.station), root.path))}>
                <span className={css.mFolder} data-off={!station.online || undefined}><Folder size={22} /></span>
                <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{root.name}</span>
                <span className={css.mWhere} data-off={!station.online || undefined}>{station.name}</span>
                <ChevronRight size={14} className={partsCss.mSubtle} />
              </ListRow>
            ))}
          </ListCard>
        )}
    </div>
  );
}
