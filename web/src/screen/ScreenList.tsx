// A station's screens (the core's `screens` topic; docs/remote-screens.md) where its page lists what it has: a row each
// (what it is by its mark, its name, the core's line about it), opening it. A station from before screens says so in
// a quiet row; one with none says nothing (unless the core says why).
import { Link } from "react-router";
import { useTopic } from "../core/react.ts";
import type { ScreenItem, ScreensView } from "../core/shapes.ts";
import { ChevronRight, Monitor, Web, type IconProps } from "@stillfail/ui/icons.tsx";
import { ICON, Section } from "../ui.tsx";
import { t } from "../i18n.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as settingsCss from "../cloud/settings.css.ts";
import * as css from "./ScreenList.css.ts";

/** A station's screens, as the core has them; undefined until it has. */
export function useScreens(station: string): ScreensView | undefined {
  return useTopic<ScreensView>({ topic: "screens", station }).value ?? undefined;
}

/** What there is to say of them: the screens, else why there are none (the core's note), else nothing. */
export function screensShown(v: ScreensView | undefined): { screens: ScreenItem[]; note: string | null } | null {
  if (!v) return null;
  if (v.screens.length) return { screens: v.screens, note: null };
  return v.note ? { screens: [], note: v.note } : null;
}

/** The station lacks what it needs to show it or to drive it (a macOS grant): its line, which says what, is off. */
export const lacks = (s: ScreenItem) => !!s.access && (!s.access.capture || !s.access.control);

/** A screen's mark: a display for the machine's desktop, the globe for a tab of its browser. */
export function ScreenMark({ kind, ...props }: { kind: string } & IconProps) {
  return kind === "browser" ? <Web {...props} /> : <Monitor {...props} />;
}

/** The station page's section (cloud/StationPage.tsx). */
export function ScreensSection({ station }: { station: string }) {
  const shown = screensShown(useScreens(station));
  if (!shown) return null;
  return (
    <Section title={<>{t("web-pages.screen.section")}{shown.screens.length > 0 && <span className={settingsCss.titleCount}>{shown.screens.length}</span>}</>}>
      <ul className={pagesCss.list}>
        {shown.screens.map((s) => (
          <li key={s.id}>
            <Link className={`${pagesCss.listRow} ${css.row}`} to={s.link}>
              <ScreenMark kind={s.kind} {...ICON} className={shellCss.muted} />
              <span className={pagesCss.listRowText}>
                <span className={pagesCss.listRowTitle}>{s.title}</span>
                <span className={lacks(s) ? `${css.line} ${css.off}` : css.line}>{s.line}</span>
              </span>
              <ChevronRight {...ICON} className={shellCss.muted} />
            </Link>
          </li>
        ))}
        {shown.note && (
          <li>
            <div className={`${pagesCss.listRow} ${css.row} ${css.still}`}>
              <Monitor {...ICON} className={shellCss.muted} />
              <span className={css.line}>{shown.note}</span>
            </div>
          </li>
        )}
      </ul>
    </Section>
  );
}
