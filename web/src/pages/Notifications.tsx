// What this client tells its person about their chats, and how (notify.ts, docs/notifications.md), laid out as a
// phone's notification settings are: a preview that follows the settings, the ways it tells (a banner, the badge), and
// each kind of thing that happens with which of those it uses.
import { useEffect, useState } from "react";
import { useNavigate } from "react-router";
import type { BadgeKinds, Notice, NotifyKinds, NotifyView } from "../core/shapes.ts";
import { core, useTopic } from "../core/react.ts";
import { CAN_NOTIFY, requestPermission, setNotify, useNotifyState, type NotifyState } from "../notify.ts";
import { useWorkspaceMarks } from "../lastChat.ts";
import { setPrefs } from "../prefs.ts";
import { ChevronRight } from "@stillfail/ui/icons.tsx";
import { MobileBack, Section, Segmented, Switch, SwitchRow, Waiting } from "../ui.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./Notifications.css.ts";

import { BETA, NAME } from "../channel.ts";
import { t } from "../i18n.ts";

type Kind = "wait" | "failed" | "done" | "message";
const KINDS_SHOWN: Kind[] = ["wait", "failed", "done", "message"];
const NOTIFY_DEFAULT: NotifyKinds = { wait: true, failed: true, done: "away", message: true };
const BADGE_DEFAULT: BadgeKinds = { on: true, wait: true, failed: true, done: false, message: false };
const MAC_APP = !!window.stillfailDesktop && /Mac/.test(navigator.platform);
/** The app's own icon, as the system shows it beside its notifications and in the Dock. */
const ICON = BETA || window.stillfailDesktop?.beta ? "/icon-beta-192.png" : "/icon-192.png";

export function NotificationsPage({ back, workspace }: { back: string; workspace: string }) {
  const s = useSettings(workspace);
  const navigate = useNavigate();
  const [open, setOpen] = useState<Kind | null>(null);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.settings.nav.notifications")}</h1></div></header>
      {/* Not the device's settings yet (the core's): their cards' shapes, not the defaults as if they were its. */}
      {!s.read ? <Waiting shape="cards" /> : <>
      <Preview s={s} kind={open ?? KINDS_SHOWN.find((k) => s.banner(k)) ?? "wait"} />
      <Section title={t("web-pages.notifications.ways.title")} description={s.note}>
        <div className={css.tiles}>
          {CAN_NOTIFY && <Tile way="banner" on={s.state === "on"} busy={s.busy} disabled={s.state === "unsupported" || (s.permission === "denied" && !s.openSettings)}
            action={s.permission === "denied" ? t("web-pages.notifications.enable.open") : s.permission === "default" ? t("web-pages.notifications.enable.allow") : undefined}
            onChange={(on) => (s.permission === "denied" ? s.openSettings?.() : s.permission === "default" ? void requestPermission() : s.setBanner(on))} />}
          <Tile way="badge" on={s.badge.on} onChange={(on) => s.setBadge({ on })} />
        </div>
      </Section>
      <Section title={t("web-pages.notifications.kinds.title")}>
        <div className={`${pagesCss.card} ${css.kinds}`}>
          {KINDS_SHOWN.map((k) => (
            <KindRow key={k} kind={k} s={s} open={open === k} onOpen={() => setOpen(open === k ? null : k)} />
          ))}
        </div>
      </Section>
      <Section title={t("web-pages.notifications.more.title")}>
        <div className={pagesCss.card}>
          {window.stillfailDesktop && <SwitchRow title={t("web-pages.notifications.preview")} description={t("web-pages.notifications.previewNote")}
            checked={s.preview} disabled={s.state !== "on"} onChange={s.setPreview} />}
          {MAC_APP && <p className={css.sound}>{t("web-pages.notifications.sound", { name: NAME })}</p>}
          {!window.stillfailDesktop && <p className={css.sound}>{t("web-pages.notifications.browserNote")}</p>}
        </div>
      </Section>
      </>}
    </div>
  );
}

/** Every setting the page shows, as the core and the desktop app keep them, and their changing. */
function useSettings(workspace: string) {
  const toast = useToast();
  const state = useNotifyState();
  const [busy, setBusy] = useState(false);
  const notify = useTopic<NotifyView>({ topic: "notify" }).value;
  const marks = useWorkspaceMarks(workspace);
  const notices = useTopic<{ items: Notice[] }>({ topic: "notices", workspace }).value?.items ?? [];
  // What was just chosen shows before the core says it back.
  const [kinds, setKinds] = useState<NotifyKinds | null>(null);
  const [preview, setPreviewNow] = useState<boolean | null>(null);
  const [badge, setBadgeNow] = useState<BadgeKinds | null>(null);
  useEffect(() => setKinds(null), [notify?.kinds?.wait, notify?.kinds?.failed, notify?.kinds?.done, notify?.kinds?.message]);
  useEffect(() => setPreviewNow(null), [notify?.preview]);
  const badgeKept = marks?.badgeKinds;
  useEffect(() => setBadgeNow(null), [badgeKept?.on, badgeKept?.wait, badgeKept?.failed, badgeKept?.done, badgeKept?.message]);

  const k = kinds ?? notify?.kinds ?? NOTIFY_DEFAULT;
  const kept = badge ?? badgeKept ?? BADGE_DEFAULT;
  const b = { on: kept.on !== false, wait: kept.wait === true, failed: kept.failed === true, done: kept.done === true, message: kept.message === true };
  const desktop = !!window.stillfailDesktop;
  const note = state === "unsupported" ? t("web-pages.notifications.unsupported")
    : desktop ? t("web-pages.notifications.noteDevice") : t("web-pages.notifications.noteBrowser");
  const failed = (e: unknown) => toast(t("web-pages.notifications.kindsFailed", { error: failure(e) }));

  return {
    state: state as NotifyState, busy, note,
    /** The core's settings have come (until then, what is shown would be the defaults). */
    read: notify !== undefined,
    notices, preview: preview ?? notify?.preview ?? true,
    count: marks?.badge ?? 0,
    permission: notify?.permission ?? "unknown",
    /** The system's notification settings for the app, where the app can open them (not a browser's). */
    openSettings: window.stillfailDesktop?.notify?.settings ? () => { void window.stillfailDesktop?.notify?.settings?.(); } : null,
    kinds: k, badge: b,
    /** Whether a kind comes as a banner now. */
    banner: (kind: Kind) => state === "on" && (kind === "done" ? k.done !== "off" : k[kind] !== false),
    setBanner: (on: boolean) => {
      setBusy(true);
      setNotify(on).then((now) => { if (on && now !== "on") toast(t("web-pages.notifications.notAllowed")); }, (e: unknown) => toast(on ? t("web-pages.notifications.onFailed", { error: failure(e) }) : t("web-pages.notifications.offFailed", { error: failure(e) })))
        .finally(() => setBusy(false));
    },
    setKinds: (patch: Partial<NotifyKinds>) => {
      setKinds({ ...k, ...patch });
      core().call("notify.set", { kinds: patch }).catch((e: unknown) => { setKinds(null); failed(e); });
    },
    setPreview: (on: boolean) => {
      setPreviewNow(on);
      core().call("notify.set", { preview: on }).catch((e: unknown) => { setPreviewNow(null); failed(e); });
    },
    setBadge: (patch: BadgeKinds) => {
      setBadgeNow({ ...b, ...patch });
      setPrefs({ badgeKinds: patch });
    },
  };
}
type Settings = ReturnType<typeof useSettings>;

export type Way = "banner" | "badge";

/** One way of telling, as a tile with a picture of it: pressed, on or off. `action`: the system has to allow it first,
 * the tile is the way to (its words on a button in it, the picture marked): pressed, it goes there. */
export function Tile({ way, on, onChange, busy, disabled, action }: { way: Way; on: boolean; onChange(on: boolean): void; busy?: boolean; disabled?: boolean; action?: string | undefined }) {
  return (
    <button type="button" className={css.tile} aria-pressed={action ? undefined : on} data-on={(on && !action) || undefined} data-action={action ? true : undefined} disabled={busy || disabled} onClick={() => onChange(!on)}>
      <span className={css.tilePicture} aria-hidden="true">
        {action && <span className={css.picAlert}>!</span>}
        {way === "banner" ? <span className={css.picBanner} /> : <span className={css.picApp}><span className={css.picBadge} /></span>}
      </span>
      <span className={css.tileName}>{t(`web-pages.notifications.ways.${way}`)}</span>
      {action ? <span className={css.tileAction}>{action}<ChevronRight size={14} aria-hidden="true" /></span>
        : <span className={css.tileState}>{on ? t("web-pages.notifications.on") : t("web-pages.notifications.off")}</span>}
    </button>
  );
}

/** A kind of thing that happens: what tells of it, in a line; opened, each way on or off. */
function KindRow({ kind, s, open, onOpen }: { kind: Kind; s: Settings; open: boolean; onOpen(): void }) {
  const ways = [
    CAN_NOTIFY && s.banner(kind) ? (kind === "done" && s.kinds.done === "away" ? t("web-pages.notifications.sumBannerAway") : t("web-pages.notifications.ways.banner")) : null,
    s.badge.on && s.badge[kind] ? t("web-pages.notifications.ways.badge") : null,
  ].filter(Boolean);
  const off = s.state !== "on";
  return (
    <div className={css.kind} data-open={open || undefined}>
      <button type="button" className={css.kindHead} aria-expanded={open} onClick={onOpen}>
        <span className={css.kindText}><span>{t(`web-pages.notifications.kinds.${kind}`)}</span><span className={css.muted}>{t(`web-pages.notifications.kinds.${kind}Note`)}</span></span>
        <span className={css.sum}>{ways.length ? ways.join(" · ") : t("web-pages.notifications.none")}</span>
        <ChevronRight size={16} className={css.chevron} aria-hidden="true" />
      </button>
      {open && (
        <div className={css.kindWays}>
          {CAN_NOTIFY && (kind === "done" ? (
            <div className={css.wayRow}>
              <span>{t("web-pages.notifications.ways.banner")}</span>
              <Segmented label={t("web-pages.notifications.ways.banner")} value={(s.kinds.done || "away") as "off" | "away" | "always"} onChange={(done) => s.setKinds({ done })}
                options={[
                  { value: "off", label: t("web-pages.notifications.kinds.doneOff"), disabled: off },
                  { value: "away", label: t("web-pages.notifications.kinds.doneAway"), disabled: off },
                  { value: "always", label: t("web-pages.notifications.kinds.doneAlways"), disabled: off },
                ]} />
            </div>
          ) : (
            <WayRow title={t("web-pages.notifications.ways.banner")} checked={s.kinds[kind] !== false} disabled={off} onChange={(v) => s.setKinds({ [kind]: v })} />
          ))}
          <WayRow title={t("web-pages.notifications.inBadge")} checked={s.badge[kind]} disabled={!s.badge.on} onChange={(v) => s.setBadge({ [kind]: v })} />
        </div>
      )}
    </div>
  );
}

function WayRow({ title, checked, disabled, onChange }: { title: string; checked: boolean; disabled: boolean; onChange(on: boolean): void }) {
  return (
    <label className={css.wayRow}>
      <span>{title}</span>
      <Switch checked={checked} disabled={disabled} onChange={onChange} small />
    </label>
  );
}

const SAMPLE: Record<Kind, () => { title: string; body: string }> = {
  wait: () => ({ title: t("web-pages.notifications.sample.title"), body: t("web-pages.notifications.sample.wait") }),
  failed: () => ({ title: t("web-pages.notifications.sample.title"), body: t("web-pages.notifications.sample.failed") }),
  done: () => ({ title: t("web-pages.notifications.sample.title"), body: t("web-pages.notifications.sample.done") }),
  message: () => ({ title: t("web-pages.notifications.sample.title"), body: t("web-pages.notifications.sample.message") }),
};

/** A screen as the settings make it: the banner of `kind` (the latest one that came, else a sample), the app's badge
 * with what it counts now. */
function Preview({ s, kind }: { s: Settings; kind: Kind }) {
  const latest = [...s.notices].reverse().find((n) => (n.kind === "block" ? "wait" : n.kind) === kind);
  const shown = latest ? { title: latest.title, body: latest.body } : SAMPLE[kind]();
  const body = s.preview ? shown.body : t(`web-pages.notifications.hidden.${kind}`);
  const banner = CAN_NOTIFY && s.banner(kind);
  const badge = s.badge.on && s.count > 0;
  return (
    <div className={css.screen} aria-label={t("web-pages.notifications.previewLabel")} role="img">
      <div className={css.banner} data-off={!banner || undefined}>
        <img src={ICON} alt="" className={css.bannerIcon} />
        <span className={css.bannerText}>
          <span className={css.bannerHead}><b>{shown.title}</b><span className={css.muted}>{t("web-pages.notifications.now")}</span></span>
          <span className={css.bannerBody}>{body}</span>
        </span>
      </div>
      <div className={css.dockBar}>
        <span className={css.appIcon} />
        <span className={css.appIcon} />
        <span className={css.appIconMine}>
          <img src={ICON} alt="" className={css.appIconImage} />
          {badge && <span className={css.badge}>{s.count > 99 ? "99+" : s.count}</span>}
        </span>
        <span className={css.appIcon} />
      </div>
    </div>
  );
}
