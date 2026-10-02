// What only this client (browser, desktop app) keeps: how the pages look here.
import { AppearanceSetting } from "../components.tsx";
import { t } from "../i18n.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { MobileBack, Section, Segmented } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";

export function AppearancePage({ back }: { back: string }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.appearance.back")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.appearance.title")}</h1></div></header>
      <Section title={t("web-pages.appearance.theme.title")} description={t("web-pages.appearance.theme.description")}>
        <div className={chatCss.appearanceSetting}><AppearanceSetting /></div>
      </Section>
      <Section title={t("common.language")} description={t("web-pages.appearance.language.description")}>
        <div className={chatCss.appearanceSetting}><LanguageSetting /></div>
      </Section>
    </div>
  );
}

/** 语言: follow the system, or always Chinese, or always English (kept by the core with the other prefs). */
function LanguageSetting() {
  const language = usePrefs().language;
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
