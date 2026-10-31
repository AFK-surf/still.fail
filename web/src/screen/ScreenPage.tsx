// A station's screen on a page of its own (`/w/<workspace>/s/<station>/screen/<id>`: its page in the station's list, a
// link an agent posted in a chat), over the whole window as a file opened is. Back goes where it was opened from, or
// to the station's page when it was opened straight. It moves to a window of its own on asking (`?window`), where back
// closes that window.
// One opened for a while only (`?until-gone`: a sign-in's page in the station's browser, its tab closed as it ends)
// goes back by itself once its screen is gone.
import { useLocation, useParams } from "react-router";
import { useGo } from "../go.ts";
import { scopeOf, useStation } from "../station.tsx";
import { stationPage } from "../cloud/StationPage.tsx";
import { t } from "../i18n.ts";
import { ScreenViewer } from "./ScreenViewer.tsx";
import { UNTIL_GONE } from "./InStation.tsx";
import * as css from "./ScreenViewer.css.ts";

export function ScreenPage() {
  const { id = "" } = useParams();
  const station = useStation();
  const go = useGo();
  const { pathname, search } = useLocation();
  const alone = new URLSearchParams(search).has("window");
  const leaves = new URLSearchParams(search).has(UNTIL_GONE);
  const back = () => {
    if (alone) window.close();
    else if (((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0) go(-1);
    else go(stationPage(scopeOf(station.address), station.id));
  };
  // The view moves there: this one closes, so the screen is not open twice.
  const own = () => {
    window.open(`${pathname}?window`, "_blank");
    back();
  };
  return (
    <div className={css.page}>
      <ScreenViewer key={`${station.address} ${id}`} station={station.address} screen={id} backLabel={alone ? t("common.close") : t("common.back")} onBack={back}
        onWindow={alone ? undefined : own} onGone={leaves ? back : undefined} onGrants={() => go(`${stationPage(scopeOf(station.address), station.id)}?part=settings`)} />
    </div>
  );
}
