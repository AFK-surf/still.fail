// What only this client (browser, desktop app) keeps: how the pages look here.
import { AppearanceSetting } from "../components.tsx";
import { t } from "../i18n.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { useMotionSetting } from "../theme.ts";
import { Button, MobileBack, Section, Segmented } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import { editRail } from "../Rail.tsx";
import * as railCss from "../Rail.css.ts";

export function AppearancePage({ back }: { back: string }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.appearance.back")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.appearance.title")}</h1></div></header>
      <Section title={t("web-pages.appearance.theme.title")} description={t("web-pages.appearance.theme.description")}>
        <div className={chatCss.appearanceSetting}><AppearanceSetting /></div>
      </Section>
      <Section title={t("web-pages.appearance.motion.title")} description={t("web-pages.appearance.motion.description")}>
        <div className={chatCss.appearanceSetting}><MotionSetting /></div>
      </Section>
      <Section title={t("common.language")} description={t("web-pages.appearance.language.description")}>
        <div className={chatCss.appearanceSetting}><LanguageSetting /></div>
      </Section>
      <Section title={t("web-pages.appearance.drop.title")} description={t("web-pages.appearance.drop.description")}>
        <div className={chatCss.appearanceSetting}><DropSetting /></div>
      </Section>
      <ArchiveSetting />
      {/* The rail is the wide screen's (Rail.tsx). */}
      <div className={railCss.wideOnly}>
        <Section title={t("web-main.rail.title")} description={t("web-main.rail.lead")}>
          <div><Button onClick={() => editRail(true)}>{t("web-main.rail.customize")}</Button></div>
        </Section>
      </div>
    </div>
  );
}

/** Files dragged into a chat: named by their path (the default), or sent as files; a chat may say otherwise (its file
 * cards' hover). */
function DropSetting() {
  const value = usePrefs((p) => p.dropAs) === "file" ? "file" : "path";
  return (
    <Segmented label={t("web-pages.appearance.drop.title")} value={value}
      onChange={(v) => setPrefs({ dropAs: v === "file" ? "file" : null })}
      options={[
        { value: "path", label: t("web-pages.appearance.drop.path") },
        { value: "file", label: t("web-pages.appearance.drop.file") },
      ]} />
  );
}

/** 提示归档: when a done chat is offered to archive (the core's `archiveHint`): never, once done (the default), or once
 * its station's archive review recommended it; what the one chosen does, under it. */
function ArchiveSetting() {
  const kept = usePrefs((p) => p.archiveHint);
  const value = kept === "off" || kept === "reviewed" ? kept : "done";
  return (
    <Section title={t("web-pages.appearance.archive.title")} description={t("web-pages.appearance.archive.description")}>
      <div className={chatCss.appearanceSetting}>
        <Segmented label={t("web-pages.appearance.archive.title")} value={value}
          onChange={(v) => setPrefs({ archiveHint: v === "done" ? null : v })}
          options={[
            { value: "off", label: t("web-pages.appearance.archive.off") },
            { value: "done", label: t("web-pages.appearance.archive.done") },
            { value: "reviewed", label: t("web-pages.appearance.archive.reviewed") },
          ]} />
      </div>
      <p className={chatCss.appearanceHint}>{t(`web-pages.appearance.archive.${value}Hint`)}</p>
    </Section>
  );
}

/** 动画: as the system asks, or reduced, or full whatever it asks (kept by the core with the other prefs). */
function MotionSetting() {
  const [motion, setMotion] = useMotionSetting();
  return (
    <Segmented label={t("web-pages.appearance.motion.title")} value={motion} onChange={setMotion}
      options={[
        { value: "system", label: t("web-pages.appearance.motion.system") },
        { value: "reduce", label: t("web-pages.appearance.motion.reduce") },
        { value: "full", label: t("web-pages.appearance.motion.full") },
      ]} />
  );
}

/** 语言: follow the system, or always Chinese, or always English (kept by the core with the other prefs). */
function LanguageSetting() {
  const language = usePrefs((p) => p.language);
  const value = language === "zh" || language === "en" ? language : "system";
  return (
    <Segmented label={t("common.language")} value={value}
      onChange={(v) => setPrefs({ language: v === "system" ? null : v })}
      options={[
        { value: "system", label: t("common.language.system") },
        { value: "zh", label: t("common.language.zh") },
        { value: "en", label: t("common.language.en") },
      ]} />
  );
}
