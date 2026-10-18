// What a station's search finds of its machine (docs/search.md), on its page: whether the person's own mail, messages,
// calendars, contacts, notes and photos are found too, said by the workspace's owners and admins (others read it). The
// phone's page has the same row (./mobile/Stations.tsx).
import type { StationSearch } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { useDoing } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Section, Switch } from "./ui.tsx";
import { t } from "./i18n.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as shellCss from "./styles/shell.css.ts";

/** Sets whether the station's search finds the person's own data, saying so if it could not. */
export function useSetPersonal(station: string) {
  const call = useCall();
  const act = useAct();
  const busy = useDoing("search.setPersonal", { station });
  return { busy, set: (personal: boolean) => act(call("search.setPersonal", { station, personal }), t("web-pages.stations.search.what")) };
}

export function SearchSection({ station, search, manager }: { station: string; search: StationSearch; manager: boolean }) {
  const { busy, set } = useSetPersonal(station);
  // Only Spotlight finds a person's mail and the like; elsewhere there is nothing to say.
  if (search.files !== "spotlight") return null;
  return (
    <Section title={t("web-pages.stations.search.section")}>
      <div className={pagesCss.card}>
        <div className={pagesCss.cardRow}>
          <span className={pagesCss.cardRowText}>
            <strong>{t("web-pages.stations.search.personal")}</strong>
            <span className={shellCss.muted}>{t("web-pages.stations.search.personalLine")}</span>
          </span>
          <Switch checked={search.personal} disabled={!manager || busy} busy={busy} label={t("web-pages.stations.search.personal")} onChange={(next) => void set(next)} />
        </div>
      </div>
    </Section>
  );
}
