// How a station goes on with a session whose prompt cache is over, on its page: whether a message or notice to an agent
// whose large context's cache is over starts it afresh by itself, the default of 换新上下文's switch in each chat
// (CacheColdNotice.tsx), said by the workspace's owners and admins (others read it). The phone's page has the same row
// (./mobile/Stations.tsx).
import type { StationContext } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { useDoing } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Section, Switch } from "./ui.tsx";
import { t } from "./i18n.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as shellCss from "./styles/shell.css.ts";

/** Sets whether a session whose cache is over goes on afresh by itself, saying so if it could not. */
export function useSetAfresh(station: string) {
  const call = useCall();
  const act = useAct();
  const busy = useDoing("context.setAfresh", { station });
  return { busy, set: (afreshWhenCold: boolean) => act(call("context.setAfresh", { station, afreshWhenCold }), t("web-pages.stations.context.what")) };
}

export function ContextSection({ station, context, manager }: { station: string; context: StationContext; manager: boolean }) {
  const { busy, set } = useSetAfresh(station);
  return (
    <Section title={t("web-pages.stations.context.section")}>
      <div className={pagesCss.card}>
        <div className={pagesCss.cardRow}>
          <span className={pagesCss.cardRowText}>
            <strong>{t("web-pages.stations.context.afresh")}</strong>
            <span className={shellCss.muted}>{t("web-pages.stations.context.afreshLine")}</span>
          </span>
          <Switch checked={context.afreshWhenCold} disabled={!manager || busy} busy={busy} label={t("web-pages.stations.context.afresh")} onChange={(next) => void set(next)} />
        </div>
      </div>
    </Section>
  );
}
