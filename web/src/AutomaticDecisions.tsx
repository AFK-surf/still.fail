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
import { ChevronRight, Refresh } from "./icons.tsx";
import { stationBase } from "./station.tsx";
import * as pages from "./styles/pages.css.ts";
import * as css from "./AutomaticDecisions.css.ts";

/** Start with the decision point; each point opens the stations that configure it. */
export function AutomaticDecisions({ workspace }: { workspace: string }) {
  return <div className={css.content}><ul className={pages.list}><li>
    <Link className={pages.listRow} to={`/w/${workspace}/settings/automatic-decisions/completion`}>
      <span className={pages.listRowText}><span className={pages.listRowTitle}>{t("web-pages.automaticDecisions.completion")}</span><span className={css.note}>{t("web-pages.automaticDecisions.completionNote")}</span></span>
      <ChevronRight size={16} className={css.note} />
    </Link>
  </li></ul></div>;
}

export function AutomaticDecisionCompletion({ workspace }: { workspace: string }) {
  const stations = useStations(workspace);
  return <div className={css.content}>
    {!stations.value && <p className={css.note}>{stations.error?.message ?? t("web-pages.automaticDecisions.reading")}</p>}
    {stations.value?.length === 0 && <p className={css.note}>{t("web-pages.automaticDecisions.addStation")}</p>}
    {stations.value?.map(s => s.online && s.overview?.automaticDecisions
      ? <AutomaticDecisionPanel key={s.station} station={s.station} name={s.name} view={s.overview.automaticDecisions} />
      : <Section key={s.station} title={s.name}><p className={css.note}>{!s.online ? t("web-pages.automaticDecisions.offline") : !s.overview ? t("web-pages.automaticDecisions.connecting") : t("web-pages.automaticDecisions.upgrade")}</p></Section>)}
  </div>;
}

/** Check history has its own page, separate from the decision point's settings. */
export function AutomaticDecisionLogs({ workspace }: { workspace: string }) {
  const stations = useStations(workspace);
  return <div className={css.content}>
    {!stations.value && <p className={css.note}>{stations.error?.message ?? t("web-pages.automaticDecisions.reading")}</p>}
    {stations.value?.map(s => <Section key={s.station} title={s.name}>
      {!s.online ? <p className={css.note}>{t("web-pages.automaticDecisions.offline")}</p>
        : !s.overview ? <p className={css.note}>{t("web-pages.automaticDecisions.connecting")}</p>
        : !s.overview.automaticDecisions ? <p className={css.note}>{t("web-pages.automaticDecisions.upgrade")}</p>
        : !s.overview.automaticDecisions.canEdit ? <p className={css.note}>{t("web-pages.automaticDecisions.adminOnly")}</p>
        : <DecisionRecords station={s.station} view={s.overview.automaticDecisions} />}
    </Section>)}
  </div>;
}
function DecisionRecords({station,view}:{station:string;view:AutomaticDecisionView}) {
  return !view.recent.length ? <p className={css.note}>{t("web-pages.automaticDecisions.empty")}</p> : <ul className={pages.list}>
    {view.recent.map(row => <li key={row.id}>
      <Link className={pages.listRow} to={`${stationBase(station)}/chats/${encodeURIComponent(row.session)}`}>
        <span className={pages.listRowText}>
          <span className={css.recordHead}><span className={pages.listRowTitle}>{row.title}</span><Time stamp={row.stamp} className={css.time} /></span>
          <span className={css.meta}><span className={row.accepted ? undefined : css.bad}>{row.label}</span><span>·</span><span>{row.model}</span></span>
          {row.error && <span className={css.error}>{row.error}</span>}
        </span>
      </Link>
    </li>)}
  </ul>;
}
function AutomaticDecisionPanel({ station, name, view }: { station: string; name: string; view: AutomaticDecisionView }) {
  const {d, state, saving, refreshing, saveFailed, refreshFailed, edit, save, refresh} = useAutomaticDecisionForm(station, view);
  if (!view.canEdit) return <Section title={name}><p className={css.note}>{t("web-pages.automaticDecisions.adminOnly")}</p></Section>;
  if (!d) return <Section title={name}><p className={css.note}>{state.error?.message ?? t("web-pages.automaticDecisions.readingConfig")}</p></Section>;
  const busy = d.pending || saving;
  const chosen = view.models.find(m => m.id === d.model);
  return <Section title={<span className={css.tools}><StatusDot state="online" label={t("web-pages.automaticDecisions.online")} />{name}</span>} actions={<>
    {d.pick ? <ModelTriple modelOnly pick={{view:d.pick, saving:busy,
      set: patch => edit(patch.open ? {pickOpen:true} : {pickModel:patch.model}),
      save: async () => {await edit({pickConfirm:true});return {saved:true};},
    } satisfies Picking} onConfirm={() => edit({pickConfirm:true})} />
      : <span className={css.note}>{chosen?.name ?? t("web-pages.automaticDecisions.noModels")}</span>}
    <Switch id={`decision-${station}`} label={t("web-pages.automaticDecisions.enableOn",{station:name})} checked={d.enabled} disabled={busy} onChange={enabled => edit({enabled})} />
    <IconButton label={t("web-pages.automaticDecisions.refresh")} icon={Refresh} busy={refreshing} failed={refreshFailed} onClick={refresh} />
    {d.dirty && <Button variant="primary" busy={saving} disabled={busy} onClick={save}>{t("web-pages.automaticDecisions.save")}</Button>}
  </>}>
    {saveFailed && <p className={css.error} role="alert">{saveFailed}</p>}
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
