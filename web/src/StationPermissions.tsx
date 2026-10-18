// A Mac station's grants to still.fail Helper (the overview's `permissions`, as the core says them: docs/remote-screens.md
// "Grants") on its page: a row each with what it is for and whether it is given; one not given asked for from here
// (`permissions.request`), which puts the helper's window up on that Mac. Where the Mac's screen can be seen and driven
// the next step is that screen, opened at once, for the person to click in the window from wherever they are; else the
// row says to click Allow on that Mac, and turns as they do. A station that says none (not a Mac, or older) shows nothing.
import type { ComponentType } from "react";
import type { StationGrant, StationPermissions } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { useDoing } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Cursor, Devices, Disk, Download, FileText, Folder, Monitor, Server, type IconProps } from "@stillfail/ui/icons.tsx";
import { Button, Section } from "./ui.tsx";
import { useGo } from "./go.ts";
import { t } from "./i18n.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./StationPermissions.css.ts";

/** Each grant's mark: the screen's two by what they do, the folders by what they hold, the LAN by the devices on it. */
export const GRANT_MARK: Record<string, ComponentType<IconProps>> = {
  capture: Monitor, control: Cursor, documents: FileText, desktop: Folder, downloads: Download, removable: Disk, network: Server, localNetwork: Devices,
};
export const grantMark = (id: string) => GRANT_MARK[id] ?? Folder;

/** What a row does at its end: say it is given, open the screen (its window up, the screen drivable), wait for it at
 *  the Mac, ask for it, or (a member who may not ask) say it is not given. */
export type GrantEnd = "granted" | "open" | "waiting" | "request" | "missing";
export function grantEnd(g: StationGrant, p: StationPermissions): GrantEnd {
  if (g.granted) return "granted";
  if (g.asking) return p.screen ? "open" : "waiting";
  return p.canRequest ? "request" : "missing";
}

/**
 * Asking for a grant (the phone's page too: ./mobile/StationPermissions.tsx): the window up on the Mac; then, where its
 * screen can be driven, that screen opened (`open`, with its page) so the person grants from here in one tap.
 */
export function useGrantRequest(station: string, open: (link: string) => void) {
  const call = useCall();
  const act = useAct();
  return (g: StationGrant, p: StationPermissions) => act(
    (call("permissions.request", { station, grant: g.id }) as Promise<{ window?: string; screen?: boolean } | null>).then((answer) => {
      if (answer?.window === "up" && answer.screen === true && p.screen) open(p.screen);
    }),
    t("web-pages.stations.permissions.requestWhat", { name: g.name }),
  );
}

/** The station page's section (cloud/StationPage.tsx). */
export function PermissionsSection({ station, permissions: p }: { station: string; permissions: StationPermissions }) {
  const go = useGo();
  const request = useGrantRequest(station, (link) => go(link));
  return (
    <Section title={t("web-pages.stations.permissions.section")} description={p.note}>
      <div className={pagesCss.list}>
        {p.grants.map((g) => <GrantRow key={g.id} station={station} g={g} end={grantEnd(g, p)} onRequest={() => request(g, p)} onOpen={() => p.screen && go(p.screen)} />)}
      </div>
    </Section>
  );
}

function GrantRow({ station, g, end, onRequest, onOpen }: { station: string; g: StationGrant; end: GrantEnd; onRequest(): void; onOpen(): void }) {
  const busy = useDoing("permissions.request", { station, grant: g.id });
  const Mark = grantMark(g.id);
  return (
    <div className={`${pagesCss.listRow} ${css.row}`} data-end={end}>
      <span className={`${pagesCss.mark} ${css.mark}`}><Mark size={18} /></span>
      <span className={pagesCss.cardRowText}>
        <strong className={css.name}>{g.name}</strong>
        <span className={css.line}>{g.line}</span>
      </span>
      <span className={css.end}>
        {end === "granted" ? t("web-pages.stations.permissions.granted")
          : end === "waiting" ? t("web-pages.stations.permissions.waiting")
          : end === "missing" ? t("web-pages.stations.permissions.missing")
          : end === "open" ? <Button onClick={onOpen}>{t("web-pages.stations.permissions.openScreen")}</Button>
          : <Button variant="primary" busy={busy} disabled={busy} aria-label={t("web-pages.stations.permissions.requestLabel", { name: g.name })} onClick={onRequest}>{t("web-pages.stations.permissions.request")}</Button>}
      </span>
    </div>
  );
}
