// Whether a Windows station runs as the machine's administrator, on its page (the station's elevation/elevation.ts):
// switched by the workspace's owners and admins, Windows asking (UAC) on the machine and the station restarting; what
// it means or how a change goes under it, and how the last one failed. The phone's page has the same row
// (./mobile/Stations.tsx).
import type { StationElevation } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { useDoing } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Section, Switch } from "./ui.tsx";
import { t } from "./i18n.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import * as css from "./StationElevation.css.ts";

/** Switches it, saying so if the station refused. */
export function useSetElevation(station: string) {
  const call = useCall();
  const act = useAct();
  const doing = useDoing("elevation.set", { station });
  return { doing, set: (on: boolean) => act(call("elevation.set", { station, on }), t("web-pages.stations.elevation.what")) };
}

export function ElevationSection({ station, elevation }: { station: string; elevation: StationElevation }) {
  const { doing, set } = useSetElevation(station);
  const busy = doing || elevation.busy;
  return (
    <Section title={t("web-pages.stations.elevation.section")}>
      <div className={pagesCss.card}>
        <div className={pagesCss.cardRow}>
          <span className={pagesCss.cardRowText}>
            <strong>{t("web-pages.stations.elevation.admin")}</strong>
            <span className={shellCss.muted}>{elevation.line}</span>
            {elevation.failed && <span className={css.failed}>{elevation.failed}</span>}
          </span>
          <Switch checked={elevation.on} disabled={!elevation.canChange || busy} busy={busy} label={t("web-pages.stations.elevation.admin")} onChange={(next) => void set(next)} />
        </div>
      </div>
    </Section>
  );
}
