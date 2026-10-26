// What this client says about itself: this build and what changed, whether it sends usage statistics and error reports (telemetry.ts, docs/telemetry.md), and where still.fail's terms
// of service and privacy policy are. The narrow screen's settings and the app have the same (mobile/Settings.tsx; apps/
// mbui sfdesk/about.mbt).
import { ArrowUpRight, ChevronRight } from "@stillfail/ui/icons.tsx";
import { Link } from "react-router";
import { useChangelog } from "../changelog.ts";
import { NAME } from "../channel.ts";
import { lang, t } from "../i18n.ts";
import { HAS_TELEMETRY, setTelemetry, useTelemetryOn } from "../telemetry.ts";
import { ICON, MobileBack, Section, SwitchRow } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";

/** still.fail's terms of service or privacy policy on its site: the English one while the pages speak English. */
export function legalUrl(page: "terms" | "privacy"): string {
  return `https://still.fail/${lang() === "en" ? "en/" : ""}${page}`;
}

/** The legal pages, as the settings list them. */
export function legalPages(): ["terms" | "privacy", string][] {
  return [["terms", t("common.legal.terms")], ["privacy", t("common.legal.privacy")]];
}

export function AboutPage({ back }: { back: string }) {
  const sending = useTelemetryOn();
  const build = useChangelog().value?.build;
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.settings.nav.about")}</h1></div></header>
      {/* This build, and what changed. */}
      <Section title={t("web-pages.settings.nav.version")}>
        <ul className={pagesCss.list}>
          <li className={pagesCss.listRow}>
            <span className={pagesCss.listRowTitle}>{NAME}{build != null ? ` 0.1.${build}` : ""}</span>
          </li>
          <li>
            <Link className={pagesCss.listRow} to={`${back}/changelog`}>
              <span className={pagesCss.listRowTitle}>{t("web-pages.settings.nav.changelog")}</span>
              <ChevronRight {...ICON} className={shellCss.muted} />
            </Link>
          </li>
        </ul>
      </Section>
      {/* A build without PostHog sends nothing: nothing to turn off. */}
      {HAS_TELEMETRY && (
        <Section title={t("web-pages.about.privacy")}>
          <div className={pagesCss.card}>
            <SwitchRow title={t("common.telemetry.title")} description={t("common.telemetry.note", { name: NAME })} checked={sending} onChange={setTelemetry} />
          </div>
        </Section>
      )}
      {/* On still.fail's site, in a tab of their own. */}
      <Section title={t("web-pages.about.legal")}>
        <ul className={pagesCss.list}>
          {legalPages().map(([page, label]) => (
            <li key={page}>
              <a className={pagesCss.listRow} href={legalUrl(page)} target="_blank" rel="noopener noreferrer">
                <span className={pagesCss.listRowTitle}>{label}</span>
                <ArrowUpRight {...ICON} className={shellCss.muted} />
              </a>
            </li>
          ))}
        </ul>
      </Section>
    </div>
  );
}
