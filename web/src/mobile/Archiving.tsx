// 设置 › 归档 on a phone (archiving.ts; the wide screen's pages/Archiving.tsx): whether a done chat suggests archiving
// it, on this device; then the stations, a row each saying how it archives on its own, each opening a screen of its own.
import { useParams } from "react-router";
import type { ArchivingView, StationView } from "../core/shapes.ts";
import { useStations } from "../api.ts";
import { t } from "../i18n.ts";
import { StationNamed } from "../StationNamed.tsx";
import { HINTS, MODES, daysLabel, hintLabel, hintNote, hintReviews, modeLabel, modeNote, modeOf, modePatch, reviewOf, useArchiveHint, useArchivingSave } from "../archiving.ts";
import { ChevronRight } from "@stillfail/ui/icons.tsx";
import { useApp } from "./app.tsx";
import { LargeTitle, ListCard, ListRow, SectionHeader, Seg, TopBack } from "./parts.tsx";
import { Waiting } from "@stillfail/ui/waiting.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as css from "./Settings.css.ts";
import * as chatCss from "../styles/chat.css.ts";

export function ArchivingScreen() {
  const app = useApp();
  const [hint, setHint] = useArchiveHint();
  const stations = useStations(app.entry.id);
  const reviews = hintReviews(stations.value);
  const decisions = app.at("/settings/automatic-decisions/completion");
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
      <LargeTitle small="" big={t("web-pages.archiving.title")} />
      <SectionHeader title={t("web-pages.appearance.archive.title")} start={24} />
      <div style={{ padding: "0 12px" }}>
        <Seg options={HINTS.map(hintLabel)} selected={HINTS.indexOf(hint)} height={34} fill
          onSelect={(i) => { if (!(HINTS[i] === "reviewed" && reviews?.none)) setHint(HINTS[i]!); }} />
      </div>
      <div className={css.mSegNote}>{hintNote(hint)}</div>
      {reviews && (hint === "reviewed" || reviews.none) && <div className={css.mSegNote}>
        {reviews.text}{" "}<a className={chatCss.inlineLink} href={decisions} onClick={(e) => { e.preventDefault(); app.push(decisions); }}>{t("web-pages.archiving.reviewGo")}</a>
      </div>}
      <div className={css.mSegNote}>{t("web-pages.appearance.archive.description")}</div>
      <SectionHeader title={t("web-pages.archiving.auto.title")} start={24} />
      {!stations.value && <Waiting shape="cards" count={1} text={t("common.readingStations")} error={stations.error?.message} />}
      {stations.value && <ListCard>{stations.value.map((s) => <StationRow key={s.station} s={s} />)}</ListCard>}
      <div className={css.mSegNote}>{t("web-pages.archiving.auto.description")}</div>
      <div style={{ height: 30 }} />
    </div>
  );
}

/** A station's row: how it archives on its own, in a line; it opens the station's screen once it can say. */
function StationRow({ s }: { s: StationView }) {
  const app = useApp();
  const view = s.online ? s.overview?.archiving : undefined;
  const stalled = view !== undefined && view.reviewed && view.days > 0 && !reviewOf(s).on;
  const note = !view ? (!s.online ? t("web-pages.automaticDecisions.offline") : !s.overview ? t("common.connecting") : t("web-pages.archiving.upgrade"))
    : stalled ? t("web-pages.archiving.stalled") : view.summaryText;
  return (
    <ListRow onClick={view ? () => app.push(app.at(`/settings/archive/${encodeURIComponent(s.station)}`)) : undefined}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}><StationNamed emoji={s.emoji} icon={s.icon} name={s.name} /></span>
        <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}${stalled ? ` ${partsCss.mRed}` : ""}`}>{note}</span>
      </span>
      {view && <ChevronRight size={14} className={partsCss.mSubtle} />}
    </ListRow>
  );
}

/** A station's own screen (设置 › 归档 › its name): its review, how it archives, after how long, and Slack's. */
export function StationArchivingScreen() {
  const app = useApp();
  const { station = "" } = useParams();
  const stations = useStations(app.entry.id);
  const s = stations.value?.find((x) => x.station === station);
  const view = s?.online ? s.overview?.archiving : undefined;
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-pages.archiving.title")} onBack={app.pop} />
      <LargeTitle small={t("web-pages.archiving.auto.title")} big={s?.name ?? ""} />
      {s && view ? <StationArchivingForm s={s} view={view} />
        : !stations.value ? <Waiting shape="cards" count={1} text={t("common.readingStations")} error={stations.error?.message} />
        : <div className={css.mSegNote}>{!s?.online ? t("web-pages.automaticDecisions.offline") : !s.overview ? t("common.connecting") : t("web-pages.archiving.upgrade")}</div>}
      <div style={{ height: 30 }} />
    </div>
  );
}

function StationArchivingForm({ s, view }: { s: StationView; view: ArchivingView }) {
  const app = useApp();
  const { save, busy } = useArchivingSave(s.station);
  const review = reviewOf(s);
  const mode = modeOf(view);
  const locked = !view.canEdit || busy;
  const idle = view.daysOffered ?? [];
  const slack = view.slackDaysOffered ?? [];
  const decisions = app.at("/settings/automatic-decisions/completion");
  return <>
    {!view.canEdit && <div className={css.mSegNote}>{t("web-pages.archiving.adminOnly")}</div>}
    <SectionHeader title={t("web-pages.archiving.review")} start={24} />
    <div className={css.mSegNote}>
      {review.short}{" · "}
      <a className={chatCss.inlineLink} href={decisions} onClick={(e) => { e.preventDefault(); app.push(decisions); }}>{t("web-pages.archiving.reviewGo")}</a>
    </div>
    <SectionHeader title={t("web-pages.archiving.mode")} start={24} />
    <div style={{ padding: "0 12px" }}>
      <Seg options={MODES.map(modeLabel)} selected={MODES.indexOf(mode)} height={34} fill
        onSelect={(i) => { if (!locked && !(MODES[i] === "reviewed" && !review.on)) save(view, modePatch(view, MODES[i]!)); }} />
    </div>
    <div className={css.mSegNote}>
      {modeNote(mode)}
      {mode === "reviewed" && !review.on && <> {t("web-pages.archiving.reviewNeeded")}</>}
      {mode !== "reviewed" && !review.on && <> {t("web-pages.archiving.stationNeedsReview")}</>}
    </div>
    {mode !== "off" && <>
      <SectionHeader title={t("web-pages.archiving.idle")} start={24} />
      <div style={{ padding: "0 12px" }}>
        <Seg options={idle.map(daysLabel)} selected={idle.indexOf(view.days)} onSelect={(i) => { if (!locked) save(view, { days: idle[i]! }); }} height={34} fill />
      </div>
    </>}
    <SectionHeader title={t("web-pages.archiving.slack")} start={24} />
    <div style={{ padding: "0 12px" }}>
      <Seg options={slack.map(daysLabel)} selected={slack.indexOf(view.slackDays)} onSelect={(i) => { if (!locked) save(view, { slackDays: slack[i]! }); }} height={34} fill />
    </div>
    <div className={css.mSegNote}>{t("web-pages.archiving.slackHint")}</div>
  </>;
}
