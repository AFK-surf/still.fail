// 设置 › 归档 (archiving.ts): whether a done chat suggests archiving it, on this device; then the stations, a row each
// saying how it archives on its own, each opening a page of its own to change that.
import { Link } from "react-router";
import type { ArchivingView, StationView } from "../core/shapes.ts";
import { useStations } from "../api.ts";
import { t } from "../i18n.ts";
import { HINTS, IDLE_DAYS, MODES, SLACK_DAYS, daysLabel, daysOffered, hintLabel, hintNote, hintReviews, modeLabel, modeNote, modeOf, modePatch, reviewOf, summaryOf, useArchiveHint, useArchivingSave } from "../archiving.ts";
import { ChevronRight } from "@stillfail/ui/icons.tsx";
import { MobileBack, Section, Segmented, StatusDot, Waiting } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";

export function ArchivingPage({ back, workspace }: { back: string; workspace: string }) {
  const [hint, setHint] = useArchiveHint();
  const stations = useStations(workspace);
  const reviews = hintReviews(stations.value);
  const decisions = `/w/${workspace}/settings/automatic-decisions/completion`;
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.appearance.back")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.archiving.title")}</h1></div></header>
      <Section title={t("web-pages.appearance.archive.title")} description={t("web-pages.appearance.archive.description")}>
        <div className={chatCss.appearanceSetting}>
          <Segmented label={t("web-pages.appearance.archive.title")} value={hint} onChange={setHint}
            options={HINTS.map((h) => ({ value: h, label: hintLabel(h), disabled: h === "reviewed" && reviews?.none === true && hint !== "reviewed" }))} />
        </div>
        <p className={chatCss.appearanceHint}>{hintNote(hint)}</p>
        {reviews && (hint === "reviewed" || reviews.none) && <p className={chatCss.appearanceHint}>
          {reviews.text}{" "}<Link className={chatCss.inlineLink} to={decisions}>{t("web-pages.archiving.reviewGo")}</Link>
        </p>}
      </Section>
      <Section title={t("web-pages.archiving.auto.title")} description={t("web-pages.archiving.auto.description")}>
        {!stations.value && <Waiting count={1} text={t("common.readingStations")} />}
        <ul className={pagesCss.list}>{stations.value?.map((s) => <StationRow key={s.station} workspace={workspace} s={s} />)}</ul>
      </Section>
    </div>
  );
}

/** A station's row: how it archives on its own, in a line; it opens the station's page once it can say. */
function StationRow({ workspace, s }: { workspace: string; s: StationView }) {
  const view = s.online ? s.overview?.archiving : undefined;
  const title = <span className={pagesCss.listRowTitle}>{s.name}</span>;
  if (!view) {
    return (
      <li className={pagesCss.listRow}>
        <StatusDot state={s.online ? "online" : "offline"} />
        <span className={pagesCss.listRowText}>{title}<span className={chatCss.archivingNote}>{!s.online ? t("web-pages.automaticDecisions.offline") : !s.overview ? t("common.connecting") : t("web-pages.archiving.upgrade")}</span></span>
      </li>
    );
  }
  const stalled = view.reviewed && view.days > 0 && !reviewOf(s).on;
  return (
    <li>
      <Link className={pagesCss.listRow} to={`/w/${workspace}/settings/archive/${encodeURIComponent(s.station)}`}>
        <StatusDot state="online" />
        <span className={pagesCss.listRowText}>
          {title}
          <span className={chatCss.archivingNote} data-bad={stalled || undefined}>{stalled ? t("web-pages.archiving.stalled") : summaryOf(view)}</span>
        </span>
        <ChevronRight size={16} className={chatCss.archivingNote} />
      </Link>
    </li>
  );
}

/** A station's own page (设置 › 归档 › its name): its review, how it archives, after how long, and Slack's. */
export function StationArchiving({ workspace, station }: { workspace: string; station: string }) {
  const stations = useStations(workspace);
  const s = stations.value?.find((x) => x.station === station);
  const view = s?.online ? s.overview?.archiving : undefined;
  if (s && view) return <StationArchivingForm workspace={workspace} s={s} view={view} />;
  if (!stations.value && !stations.error) return <Waiting count={1} text={t("common.readingStations")} />;
  return <p className={chatCss.archivingNote}>{stations.error?.message ?? (!s?.online ? t("web-pages.automaticDecisions.offline") : !s.overview ? t("common.connecting") : t("web-pages.archiving.upgrade"))}</p>;
}

function StationArchivingForm({ workspace, s, view }: { workspace: string; s: StationView; view: ArchivingView }) {
  const { save, busy } = useArchivingSave(s.station);
  const review = reviewOf(s);
  const mode = modeOf(view);
  const locked = !view.canEdit || busy;
  return <>
    {!view.canEdit && <p className={chatCss.appearanceHint}>{t("web-pages.archiving.adminOnly")}</p>}
    <Section title={t("web-pages.archiving.review")} description={<>{review.text}{" · "}<Link className={chatCss.inlineLink} to={`/w/${workspace}/settings/automatic-decisions/completion`}>{t("web-pages.archiving.reviewGo")}</Link></>}>
      <></>
    </Section>
    <Section title={t("web-pages.archiving.mode")}>
      <div className={chatCss.appearanceSetting}>
        <Segmented label={t("web-pages.archiving.mode")} value={mode} onChange={(m) => save(view, modePatch(view, m))}
          options={MODES.map((m) => ({ value: m, label: modeLabel(m), disabled: locked || (m === "reviewed" && !review.on && mode !== "reviewed") }))} />
      </div>
      <p className={chatCss.appearanceHint}>
        {modeNote(mode)}
        {mode === "reviewed" && !review.on && <> {t("web-pages.archiving.reviewNeeded")}</>}
        {mode !== "reviewed" && !review.on && <> {t("web-pages.archiving.stationNeedsReview")}</>}
      </p>
    </Section>
    {mode !== "off" && <Section title={t("web-pages.archiving.idle")}>
      <div className={chatCss.appearanceSetting}>
        <Segmented label={t("web-pages.archiving.idle")} value={String(view.days)} onChange={(d) => save(view, { days: Number(d) })}
          options={daysOffered(view.days, IDLE_DAYS).map((n) => ({ value: String(n), label: daysLabel(n), disabled: locked }))} />
      </div>
    </Section>}
    <Section title={t("web-pages.archiving.slack")}>
      <div className={chatCss.appearanceSetting}>
        <Segmented label={t("web-pages.archiving.slack")} value={String(view.slackDays)} onChange={(d) => save(view, { slackDays: Number(d) })}
          options={daysOffered(view.slackDays, SLACK_DAYS).map((n) => ({ value: String(n), label: daysLabel(n), disabled: locked }))} />
      </div>
      <p className={chatCss.appearanceHint}>{t("web-pages.archiving.slackHint")}</p>
    </Section>
  </>;
}
