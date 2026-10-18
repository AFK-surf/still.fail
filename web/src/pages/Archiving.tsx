// 设置 › 归档 (archiving.ts): whether a done chat suggests archiving it, on this device; then each station's automatic
// archiving, with whether its archive review is on.
import { Link } from "react-router";
import type { ArchivingView, StationView } from "../core/shapes.ts";
import { useStations } from "../api.ts";
import { t } from "../i18n.ts";
import { HINTS, IDLE_DAYS, MODES, SLACK_DAYS, daysLabel, daysOffered, hintLabel, hintNote, modeLabel, modeNote, modeOf, modePatch, reviewOf, useArchiveHint, useArchivingSave } from "../archiving.ts";
import { MobileBack, Section, Segmented, Waiting } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";

export function ArchivingPage({ back, workspace }: { back: string; workspace: string }) {
  const [hint, setHint] = useArchiveHint();
  const stations = useStations(workspace);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.appearance.back")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.archiving.title")}</h1></div></header>
      <Section title={t("web-pages.appearance.archive.title")} description={t("web-pages.appearance.archive.description")}>
        <div className={chatCss.appearanceSetting}>
          <Segmented label={t("web-pages.appearance.archive.title")} value={hint} onChange={setHint}
            options={HINTS.map((h) => ({ value: h, label: hintLabel(h) }))} />
        </div>
        <p className={chatCss.appearanceHint}>{hintNote(hint)}</p>
      </Section>
      <Section title={t("web-pages.archiving.auto.title")} description={t("web-pages.archiving.auto.description")}>
        {!stations.value && <Waiting count={1} text={t("common.readingStations")} />}
      </Section>
      {stations.value?.map((s) => <StationArchiving key={s.station} workspace={workspace} s={s} />)}
    </div>
  );
}

/** A station's automatic archiving: how, after how long, and Slack's; read only for those who do not manage it. */
function StationArchiving({ workspace, s }: { workspace: string; s: StationView }) {
  const view = s.online ? s.overview?.archiving : undefined;
  const review = reviewOf(s);
  if (!view) {
    return (
      <Section title={s.name} description={!s.online ? t("web-pages.automaticDecisions.offline") : !s.overview ? t("common.connecting") : t("web-pages.archiving.upgrade")}>
        <></>
      </Section>
    );
  }
  return <StationArchivingForm workspace={workspace} s={s} view={view} review={review} />;
}

function StationArchivingForm({ workspace, s, view, review }: { workspace: string; s: StationView; view: ArchivingView; review: { on: boolean; text: string } }) {
  const { save, busy } = useArchivingSave(s.station);
  const mode = modeOf(view);
  const locked = !view.canEdit || busy;
  return (
    <Section title={s.name} description={<>{review.text}{" · "}<Link to={`/w/${workspace}/settings/automatic-decisions/completion`}>{t("web-pages.archiving.reviewGo")}</Link></>}>
      <div className={chatCss.appearanceSetting}>
        <Segmented label={t("web-pages.archiving.auto.title")} value={mode} onChange={(m) => save(view, modePatch(view, m))}
          options={MODES.map((m) => ({ value: m, label: modeLabel(m), disabled: locked }))} />
      </div>
      <p className={chatCss.appearanceHint}>
        {modeNote(mode)}
        {mode === "reviewed" && !review.on && <> {t("web-pages.archiving.reviewNeeded")}</>}
        {!view.canEdit && <> {t("web-pages.archiving.adminOnly")}</>}
      </p>
      {mode !== "off" && <>
        <h3 className={chatCss.archivingLabel}>{t("web-pages.archiving.idle")}</h3>
        <div className={chatCss.appearanceSetting}>
          <Segmented label={t("web-pages.archiving.idle")} value={String(view.days)} onChange={(d) => save(view, { days: Number(d) })}
            options={daysOffered(view.days, IDLE_DAYS).map((n) => ({ value: String(n), label: daysLabel(n), disabled: locked }))} />
        </div>
      </>}
      <h3 className={chatCss.archivingLabel}>{t("web-pages.archiving.slack")}</h3>
      <div className={chatCss.appearanceSetting}>
        <Segmented label={t("web-pages.archiving.slack")} value={String(view.slackDays)} onChange={(d) => save(view, { slackDays: Number(d) })}
          options={daysOffered(view.slackDays, SLACK_DAYS).map((n) => ({ value: String(n), label: daysLabel(n), disabled: locked }))} />
      </div>
      <p className={chatCss.appearanceHint}>{t("web-pages.archiving.slackHint")}</p>
    </Section>
  );
}
