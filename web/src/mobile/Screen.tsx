// A station's screen on a phone (`/w/<workspace>/s/<station>/screen/<id>`, as on the desktop): the whole page, its bars
// floating above and below the picture (../screen/ScreenViewer.tsx), fingers driving it; and the station's page's rows
// of them.
import { useLocation, useParams } from "react-router";
import { useStation } from "../station.tsx";
import { ScreenViewer } from "../screen/ScreenViewer.tsx";
import { UNTIL_GONE } from "../screen/InStation.tsx";
import { lacks, ScreenMark, screensShown, useScreens } from "../screen/ScreenList.tsx";
import * as listCss from "../screen/ScreenList.css.ts";
import { ChevronRight, Monitor } from "@stillfail/ui/icons.tsx";
import { ListCard, ListRow, SectionHeader } from "./parts.tsx";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import { t } from "../i18n.ts";
import { useApp } from "./app.tsx";
import * as pagesCss from "./styles/pages.css.ts";

export function ScreenScreen() {
  const app = useApp();
  const { id = "" } = useParams();
  const station = useStation();
  // Opened for a while only (a sign-in's page in the station's browser): back by itself once its screen is gone.
  const leaves = new URLSearchParams(useLocation().search).has(UNTIL_GONE);
  return (
    <div className={pagesCss.mScreen}>
      <ScreenViewer key={`${station.address} ${id}`} station={station.address} screen={id} backLabel={t("common.back")} onBack={app.pop} phone
        onGone={leaves ? app.pop : undefined} onGrants={() => app.push(app.at(`/s/${station.id}/overview`))} />
    </div>
  );
}

/** A station's screens on its page (./Stations.tsx), a row each; a station from before them says so in a quiet row. */
export function ScreensCard({ station }: { station: string }) {
  const app = useApp();
  const shown = screensShown(useScreens(station));
  if (!shown) return null;
  return (
    <>
      <SectionHeader title={t("web-pages.screen.section")} start={24} />
      <ListCard>
        {shown.screens.map((s) => (
          <ListRow key={s.id} onClick={() => app.push(s.link)}>
            <ScreenMark kind={s.kind} size={18} className={partsCss.mSubtle} />
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{s.title}</span><span className={lacks(s) ? `${listsCss.mRowNote} ${listCss.off}` : listsCss.mRowNote}>{s.line}</span></span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
        ))}
        {shown.note && (
          <ListRow>
            <Monitor size={18} className={partsCss.mSubtle} />
            <span className={`${partsCss.mGrow} ${listsCss.mRowNote}`}>{shown.note}</span>
          </ListRow>
        )}
      </ListCard>
    </>
  );
}
