// What a station sends still.fail to find its problems by, on its page: whether its log goes, scrubbed
// (station/src/ops/log-export.ts), said by the workspace's owners and admins (others read it). The phone's page has the
// same row (./mobile/Stations.tsx).
import type { StationDiagnostics } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { useDoing } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Section, Switch } from "./ui.tsx";
import { t } from "./i18n.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as shellCss from "./styles/shell.css.ts";

/** Sets whether the station sends its log, saying so if it could not. */
export function useSetLogs(station: string) {
  const call = useCall();
  const act = useAct();
  const busy = useDoing("diagnostics.setLogs", { station });
  return { busy, set: (logs: boolean) => act(call("diagnostics.setLogs", { station, logs }), t("web-pages.stations.diagnostics.what")) };
}

export function DiagnosticsSection({ station, diagnostics, manager }: { station: string; diagnostics: StationDiagnostics; manager: boolean }) {
  const { busy, set } = useSetLogs(station);
  return (
    <Section title={t("web-pages.stations.diagnostics.section")}>
      <div className={pagesCss.card}>
        <div className={pagesCss.cardRow}>
          <span className={pagesCss.cardRowText}>
            <strong>{t("web-pages.stations.diagnostics.logs")}</strong>
            <span className={shellCss.muted}>{t("web-pages.stations.diagnostics.logsLine")}</span>
          </span>
          <Switch checked={diagnostics.logs} disabled={!manager || busy} busy={busy} label={t("web-pages.stations.diagnostics.logs")} onChange={(next) => void set(next)} />
        </div>
      </div>
    </Section>
  );
}
