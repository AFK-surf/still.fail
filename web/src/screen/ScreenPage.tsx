// A station's screen on a page of its own (`/w/<workspace>/s/<station>/screen/<id>`: its page in the station's list, a
// link an agent posted in a chat), over the whole window as a file opened is. Back goes where it was opened from, or
// to the station's page when it was opened straight. It moves to a window of its own on asking (`?window`: the
// desktop app opens the app's pages as windows with the system's title bar, main.ts), where back closes that window.
import { useLocation, useParams } from "react-router";
import { useGo } from "../go.ts";
import { scopeOf, useStation } from "../station.tsx";
import { stationPage } from "../cloud/StationPage.tsx";
import { t } from "../i18n.ts";
import { ScreenViewer } from "./ScreenViewer.tsx";
import * as css from "./ScreenViewer.css.ts";

export function ScreenPage() {
  const { id = "" } = useParams();
  const station = useStation();
  const go = useGo();
  const { pathname, search } = useLocation();
  const alone = new URLSearchParams(search).has("window");
  const back = () => {
    if (alone) window.close();
    else if (((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0) go(-1);
    else go(stationPage(scopeOf(station.address), station.id));
  };
  // The view moves there: this one closes, so the screen is not open twice. (The desktop app answers no window to the
  // page: it opens its own, main.ts.)
  const own = () => {
    window.open(`${pathname}?window`, "_blank");
    back();
  };
  return (
    <div className={css.page}>
      <ScreenViewer key={`${station.address} ${id}`} station={station.address} screen={id} backLabel={alone ? t("common.close") : t("common.back")} onBack={back}
        onWindow={alone ? undefined : own} />
    </div>
  );
}
