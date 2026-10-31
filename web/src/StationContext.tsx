// How a station goes on with a session whose prompt cache is over, on its page: whether a message or notice to an agent
// whose large context's cache is over starts it afresh by itself, the default of 换新上下文's switch in each chat
// (CacheColdNotice.tsx), said by the workspace's owners and admins (others read it). The phone's page has the same row
// (./mobile/Stations.tsx).
import type { StationContext } from "./core/shapes.ts";
import { useEffect, useId, useRef, useState } from "react";
import { useCall } from "./core/react.ts";
import { useDoing } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Button, Field, Section, Switch } from "./ui.tsx";
import { t } from "./i18n.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as contextCss from "./StationContext.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as shellCss from "./styles/shell.css.ts";

/** Sets whether a session whose cache is over goes on afresh by itself, saying so if it could not. */
export function useSetAfresh(station: string) {
  const call = useCall();
  const act = useAct();
  const busy = useDoing("context.setAfresh", { station });
  return {
    busy,
    set: (afreshWhenCold: boolean) => act(call("context.setAfresh", { station, afreshWhenCold }), t("web-pages.stations.context.what")),
    setAbove: (afreshAbove: number) => act(call("context.setAfresh", { station, afreshAbove }), t("web-pages.stations.context.what")),
  };
}

/** The amount is its own edit: an update elsewhere does not overwrite what is being typed here. */
export function ContextThreshold({ station, above, manager }: { station: string; above: number; manager: boolean }) {
  const { busy, setAbove } = useSetAfresh(station);
  const id = useId();
  const [typed, setTyped] = useState(String(above));
  const last = useRef(String(above));
  useEffect(() => {
    const previous = last.current;
    last.current = String(above);
    setTyped((current) => current === previous ? last.current : current);
  }, [above]);
  const amount = typed.trim() === "" ? NaN : Number(typed);
  const valid = Number.isFinite(amount) && amount >= 0;
  return <div className={contextCss.threshold}>
    <Field label={t("web-pages.stations.context.threshold")} hint={t("web-pages.stations.context.thresholdHint")} htmlFor={id}>
      <input id={id} className={controlsCss.input} type="number" min="0" step="any" inputMode="decimal" value={typed} disabled={!manager || busy} onChange={(e) => setTyped(e.target.value)} />
    </Field>
    <Button variant="primary" busy={busy} disabled={!manager || !valid || amount === above} onClick={() => void setAbove(amount)}>{t("common.save")}</Button>
  </div>;
}

export function ContextSection({ station, context, manager }: { station: string; context: StationContext; manager: boolean }) {
  const { busy, set } = useSetAfresh(station);
  return (
    <Section title={t("web-pages.stations.context.section")}>
      <div className={pagesCss.card}>
        <div className={pagesCss.cardRow}>
          <span className={pagesCss.cardRowText}>
            <strong>{t("web-pages.stations.context.afresh")}</strong>
            <span className={shellCss.muted}>{t(context.afreshAbove === undefined ? "web-pages.stations.context.afreshLineLegacy" : "web-pages.stations.context.afreshLine")}</span>
          </span>
          <Switch checked={context.afreshWhenCold} disabled={!manager || busy} busy={busy} label={t("web-pages.stations.context.afresh")} onChange={(next) => void set(next)} />
        </div>
        {context.afreshAbove !== undefined && <ContextThreshold station={station} above={context.afreshAbove} manager={manager} />}
      </div>
    </Section>
  );
}
