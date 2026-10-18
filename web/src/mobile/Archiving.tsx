// 设置 › 归档 on a phone (archiving.ts; the wide screen's pages/Archiving.tsx): whether a done chat suggests archiving
// it, on this device; then each station's automatic archiving, with whether its archive review is on.
import { Fragment } from "react";
import type { ArchivingView, StationView } from "../core/shapes.ts";
import { useStations } from "../api.ts";
import { t } from "../i18n.ts";
import { HINTS, IDLE_DAYS, MODES, SLACK_DAYS, daysLabel, daysOffered, hintLabel, hintNote, modeLabel, modeNote, modeOf, modePatch, reviewOf, useArchiveHint, useArchivingSave } from "../archiving.ts";
import { useApp } from "./app.tsx";
import { LargeTitle, SectionHeader, Seg, TopBack } from "./parts.tsx";
import { Waiting } from "@stillfail/ui/waiting.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./Settings.css.ts";

export function ArchivingScreen() {
  const app = useApp();
  const [hint, setHint] = useArchiveHint();
  const stations = useStations(app.entry.id);
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
      <LargeTitle small="" big={t("web-pages.archiving.title")} />
      <SectionHeader title={t("web-pages.appearance.archive.title")} start={24} />
      <div style={{ padding: "0 12px" }}>
        <Seg options={HINTS.map(hintLabel)} selected={HINTS.indexOf(hint)} onSelect={(i) => setHint(HINTS[i]!)} height={34} fill />
      </div>
      <div className={css.mSegNote}>{hintNote(hint)}</div>
      <div className={css.mSegNote}>{t("web-pages.appearance.archive.description")}</div>
      <SectionHeader title={t("web-pages.archiving.auto.title")} start={24} />
      <div className={css.mSegNote}>{t("web-pages.archiving.auto.description")}</div>
      {!stations.value && <Waiting shape="cards" count={1} text={t("common.readingStations")} error={stations.error?.message} />}
      {stations.value?.map((s) => <Fragment key={s.station}><StationArchiving s={s} /></Fragment>)}
      <div style={{ height: 30 }} />
    </div>
  );
}

function StationArchiving({ s }: { s: StationView }) {
  const view = s.online ? s.overview?.archiving : undefined;
  if (!view) {
    return <>
      <SectionHeader title={s.name} start={24} />
      <div className={css.mSegNote}>{!s.online ? t("web-pages.automaticDecisions.offline") : !s.overview ? t("common.connecting") : t("web-pages.archiving.upgrade")}</div>
    </>;
  }
  return <StationArchivingForm s={s} view={view} />;
}

function StationArchivingForm({ s, view }: { s: StationView; view: ArchivingView }) {
  const app = useApp();
  const { save, busy } = useArchivingSave(s.station);
  const review = reviewOf(s);
  const mode = modeOf(view);
  const locked = !view.canEdit || busy;
  const idle = daysOffered(view.days, IDLE_DAYS);
  const slack = daysOffered(view.slackDays, SLACK_DAYS);
  return <>
    <SectionHeader title={s.name} start={24} />
    <div className={css.mSegNote}>
      {review.text}{" · "}
      <a href={app.at("/settings/automatic-decisions/completion")} onClick={(e) => { e.preventDefault(); app.push(app.at("/settings/automatic-decisions/completion")); }}>{t("web-pages.archiving.reviewGo")}</a>
    </div>
    <div style={{ padding: "8px 12px 0" }}>
      <Seg options={MODES.map(modeLabel)} selected={MODES.indexOf(mode)} onSelect={(i) => { if (!locked) save(view, modePatch(view, MODES[i]!)); }} height={34} fill />
    </div>
    <div className={css.mSegNote}>
      {modeNote(mode)}
      {mode === "reviewed" && !review.on && <> {t("web-pages.archiving.reviewNeeded")}</>}
      {!view.canEdit && <> {t("web-pages.archiving.adminOnly")}</>}
    </div>
    {mode !== "off" && <>
      <div className={css.mSegNote}>{t("web-pages.archiving.idle")}</div>
      <div style={{ padding: "8px 12px 0" }}>
        <Seg options={idle.map(daysLabel)} selected={idle.indexOf(view.days)} onSelect={(i) => { if (!locked) save(view, { days: idle[i]! }); }} height={34} fill />
      </div>
    </>}
    <div className={css.mSegNote}>{t("web-pages.archiving.slack")}</div>
    <div style={{ padding: "8px 12px 0" }}>
      <Seg options={slack.map(daysLabel)} selected={slack.indexOf(view.slackDays)} onSelect={(i) => { if (!locked) save(view, { slackDays: slack[i]! }); }} height={34} fill />
    </div>
    <div className={css.mSegNote}>{t("web-pages.archiving.slackHint")}</div>
  </>;
}
