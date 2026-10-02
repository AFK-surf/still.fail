import { t } from "./i18n.ts";
import { useEffect, useId } from "react";
import { Link } from "react-router";
import { useStations } from "./api.ts";
import { useCall, useTopic } from "./core/react.ts";
import type { AutomaticDecisionDraft, AutomaticDecisionView } from "./core/shapes.ts";
import { useAct } from "./toast.tsx";
import { useDoing, useDoingFailed } from "./doing.ts";
import { Button, IconButton, Section, StatusDot, Switch, Time } from "./ui.tsx";
import { ModelTriple } from "./ModelTriple.tsx";
import type { Picking } from "./pick.ts";
import { Refresh } from "./icons.tsx";
import { stationBase } from "./station.tsx";
import * as pages from "./styles/pages.css.ts";
import * as css from "./AutomaticDecisions.css.ts";

export function AutomaticDecisions({ workspace }: { workspace: string }) {
  const stations = useStations(workspace);
  return <div className={css.content}>
    {!stations.value && <p className={css.note}>{stations.error?.message ?? t("web-pages.automaticDecisions.reading")}</p>}
    {stations.value?.length === 0 && <p className={css.note}>{t("web-pages.automaticDecisions.addStation")}</p>}
    {stations.value?.map(s => s.online && s.overview?.automaticDecisions
      ? <AutomaticDecisionPanel key={s.station} station={s.station} name={s.name} view={s.overview.automaticDecisions} />
      : <Section key={s.station} title={s.name}><p className={css.note}>{!s.online ? t("web-pages.automaticDecisions.offline") : !s.overview ? t("web-pages.automaticDecisions.connecting") : t("web-pages.automaticDecisions.upgrade")}</p></Section>)}
  </div>;
}
function AutomaticDecisionPanel({ station, name, view }: { station: string; name: string; view: AutomaticDecisionView }) {
  const {d, state, saving, refreshing, saveFailed, refreshFailed, edit, save, refresh} = useAutomaticDecisionForm(station, view);
  if (!view.canEdit) return <Section title={name}><p className={css.note}>{t("web-pages.automaticDecisions.adminOnly")}</p></Section>;
  if (!d) return <Section title={name}><p className={css.note}>{state.error?.message ?? t("web-pages.automaticDecisions.readingConfig")}</p></Section>;
  const busy = d.pending || saving;
  const chosen = view.models.find(m => m.id === d.model);
  return <Section title={<span className={css.tools}><StatusDot state="online" label={t("web-pages.automaticDecisions.online")} />{name}</span>} actions={<>
    {d.dirty && <Button variant="primary" busy={saving} disabled={busy} onClick={save}>{t("web-pages.automaticDecisions.save")}</Button>}
    <IconButton label={t("web-pages.automaticDecisions.refresh")} icon={Refresh} busy={refreshing} failed={refreshFailed} onClick={refresh} />
  </>}>
    <div className={css.rule}>
      <div className={css.ruleText}><label className={css.ruleTitle} htmlFor={`decision-${station}`}>{t("web-pages.automaticDecisions.completion")}</label><span className={css.note}>{t("web-pages.automaticDecisions.completionNote")}</span></div>
      <div className={css.controls}>
        {d.pick ? <ModelTriple modelOnly pick={{view:d.pick, saving:busy,
          set: patch => edit(patch.open ? {pickOpen:true} : {pickModel:patch.model}),
          save: async () => {await edit({pickConfirm:true});return {saved:true};},
        } satisfies Picking} onConfirm={() => edit({pickConfirm:true})} />
          : <span className={css.note}>{chosen?.name ?? t("web-pages.automaticDecisions.noModels")}</span>}
        <Switch id={`decision-${station}`} label={t("web-pages.automaticDecisions.completion")} checked={d.enabled} disabled={busy} onChange={enabled => edit({enabled})} />
      </div>
    </div>
    {saveFailed && <p className={css.error} role="alert">{saveFailed}</p>}
    <div className={css.records}><Section title={t("web-pages.automaticDecisions.recent")}>
      {!view.recent.length ? <p className={css.note}>{t("web-pages.automaticDecisions.empty")}</p> : <ul className={pages.list}>
        {view.recent.map(row => <li key={row.id}>
          <Link className={pages.listRow} to={`${stationBase(station)}/chats/${encodeURIComponent(row.session)}`}>
            <span className={pages.listRowText}>
              <span className={css.recordHead}><span className={pages.listRowTitle}>{row.title}</span><Time stamp={row.stamp} className={css.time} /></span>
              <span className={css.meta}><span className={row.accepted ? undefined : css.bad}>{row.label}</span><span>·</span><span>{row.model}</span></span>
              {row.error && <span className={css.error}>{row.error}</span>}
            </span>
          </Link>
        </li>)}
      </ul>}
    </Section></div>
  </Section>;
}

/** Both layouts render the same core-owned draft and named actions. */
export function useAutomaticDecisionForm(station: string, view: AutomaticDecisionView) {
  const form = useId(); const call = useCall(); const act = useAct();
  const state = useTopic<AutomaticDecisionDraft | null>({ topic: "decisionForm", station, form });
  const d = state.value;
  const saving = useDoing("automaticDecisions.form.save", { station, form });
  const refreshing = useDoing("automaticDecisions.refresh", { station });
  const saveFailed = useDoingFailed("automaticDecisions.form.save", {station,form});
  const refreshFailed = useDoingFailed("automaticDecisions.refresh", {station});
  useEffect(() => {
    if (!view.canEdit) return;
    act(call("automaticDecisions.form.open", { station, form }), t("web-pages.automaticDecisions.readAction"));
    return () => { act(call("automaticDecisions.form.drop", { station, form }), t("web-pages.automaticDecisions.closeAction")); };
  }, [call, station, form, view.canEdit, act]);
  const edit = (input: Record<string, unknown>) => act(call("automaticDecisions.form.edit", { station, form, input }), t("web-pages.automaticDecisions.editAction"));
  return {d, state, saving, refreshing, saveFailed, refreshFailed, edit,
    save: () => act(call("automaticDecisions.form.save", {station,form}), t("web-pages.automaticDecisions.saveAction"), t("web-pages.automaticDecisions.saved")),
    refresh: () => act(call("automaticDecisions.refresh", {station}), t("web-pages.automaticDecisions.refreshAction"), t("web-pages.automaticDecisions.refreshed"))};
}
