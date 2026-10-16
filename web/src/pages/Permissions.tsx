// What the system lets still.fail do on this device, every permission it needs in one place (as apps that need them
// do: Rectangle, Ice, AltTab): each with what it is for, whether it is given, what goes without it, and the way to give
// it. Asked again each second while the page shows, so a change in the system's settings shows at once.
import { useEffect, type ComponentType } from "react";
import type { NotifyView } from "../core/shapes.ts";
import { useTopic } from "../core/react.ts";
import { checkPermission, CAN_NOTIFY, requestPermission } from "../notify.ts";
import { Bell, Check, type IconProps } from "@stillfail/ui/icons.tsx";
import { Button, MobileBack } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./Permissions.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";

export type PermissionState = "granted" | "denied" | "default" | "unknown";

/** Where the system keeps it, as its settings name the way there. */
function wayThere(): string {
  if (!window.stillfailDesktop) return t("web-pages.permissions.where.browser");
  return /Win/.test(navigator.platform) ? t("web-pages.permissions.where.windows", { name: NAME }) : t("web-pages.permissions.where.mac", { name: NAME });
}

export function PermissionsPage({ back }: { back: string }) {
  const notify = useTopic<NotifyView>({ topic: "notify" }).value;
  // Asked again each second while shown: given or taken back in the system's settings, it shows here at once.
  useEffect(() => {
    checkPermission();
    const every = setInterval(() => { if (document.visibilityState === "visible") checkPermission(); }, 1000);
    return () => clearInterval(every);
  }, []);
  const open = window.stillfailDesktop?.notify?.settings;
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.settings.nav.permissions")}</h1><p className={css.lead}>{t("web-pages.permissions.lead", { name: NAME })}</p></div></header>
      {CAN_NOTIFY && (
        <PermissionRow icon={Bell} name={t("web-pages.permissions.notify.name")} purpose={t("web-pages.permissions.notify.purpose")}
          without={t("web-pages.permissions.notify.without")} where={wayThere()} state={(notify?.permission ?? "unknown") as PermissionState}
          onAllow={() => { void requestPermission(); }} onOpen={open ? () => { void open(); } : null} />
      )}
    </div>
  );
}

/** One permission: what it is for and whether it is given; not given, what goes without it and the way to give it. */
export function PermissionRow({ icon: Icon, name, purpose, without, where, state, onAllow, onOpen }: {
  icon: ComponentType<IconProps>; name: string; purpose: string; without: string; where: string; state: PermissionState;
  onAllow(): void; onOpen: (() => void) | null;
}) {
  return (
    <section className={`${pagesCss.card} ${css.permission}`} data-state={state}>
      <div className={pagesCss.cardRow}>
        <span className={css.icon} aria-hidden="true"><Icon size={18} /></span>
        <span className={pagesCss.cardRowText}><strong>{name}</strong><span className={css.muted}>{purpose}</span></span>
        <span className={css.state}>{state === "granted" && <Check size={14} aria-hidden="true" />}{t(`web-pages.permissions.state.${state}`)}</span>
      </div>
      {state !== "granted" && state !== "unknown" && (
        <div className={pagesCss.cardRow}>
          <span className={pagesCss.cardRowText}>
            <span>{without}</span>
            {state === "denied" && <span className={css.muted}>{where}</span>}
          </span>
          {state === "default" ? <Button variant="primary" onClick={onAllow}>{t("web-pages.permissions.allow")}</Button>
            : onOpen && <Button onClick={onOpen}>{t("web-pages.permissions.open")}</Button>}
        </div>
      )}
    </section>
  );
}
