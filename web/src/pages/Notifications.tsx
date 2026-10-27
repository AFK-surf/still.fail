// What this client tells its person about their chats, and how (notify.ts, docs/notifications.md), laid out as a
// phone's notification settings are: a preview that follows the settings, the way it tells (a banner; a browser puts
// no number on its icon, so the badge the apps have is not one here), and each kind of thing that happens with whether
// it uses it. The preview and the way's picture are of this device's system (SYSTEM, as the app's page has them:
// apps/mbui sfdesk notifications.mbt).
import { useEffect, useState } from "react";
import { useNavigate } from "react-router";
import type { Notice, NotifyKinds, NotifyView } from "../core/shapes.ts";
import { core, useTopic } from "../core/react.ts";
import { useWorkspaceMarks } from "../lastChat.ts";
import { CAN_NOTIFY, requestPermission, setNotify, useNotifyState, type NotifyState } from "../notify.ts";
import { ChevronRight } from "@stillfail/ui/icons.tsx";
import { MobileBack, Section, Segmented, Switch, SwitchRow, Waiting } from "../ui.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./Notifications.css.ts";

import { BETA } from "../channel.ts";
import { t } from "../i18n.ts";

type Kind = "wait" | "failed" | "done" | "message";
const KINDS_SHOWN: Kind[] = ["wait", "failed", "done", "message"];
const NOTIFY_DEFAULT: NotifyKinds = { wait: true, failed: true, done: "away", message: true };
/** An iPhone's or iPad's (an iPad asking for desktop pages says it is a Mac with a touch screen). */
const IOS = /iPhone|iPad|iPod/.test(navigator.userAgent) || (/Mac/.test(navigator.platform) && navigator.maxTouchPoints > 1);
/** How this device's system shows notifications, as the preview draws it: a phone's system (Android, iOS) the device
 * itself, a banner across the top over its home screen; Windows a banner in the screen's bottom right corner over the
 * taskbar; else macOS's, a banner in its top right corner and the Dock. */
const SYSTEM: "phone" | "windows" | "mac" = IOS || /Android/.test(navigator.userAgent) ? "phone" : /Win/.test(navigator.platform) ? "windows" : "mac";
/** A tablet rather than a phone (its screen's shorter side 600 or more), drawn as one. */
const TABLET = SYSTEM === "phone" && Math.min(window.screen.width, window.screen.height) >= 600;
/** The app's own icon, as the system shows it beside its notifications and in the Dock. */
const ICON = BETA ? "/icon-beta-192.png" : "/icon-192.png";

export function NotificationsPage({ back, workspace }: { back: string; workspace: string }) {
  const s = useSettings(workspace);
  const navigate = useNavigate();
  const [open, setOpen] = useState<Kind | "services" | null>(null);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.settings.nav.notifications")}</h1></div></header>
      {/* Not the device's settings yet (the core's): the page's bones, not the defaults as if they were its. */}
      {!s.read ? <Waiting sample={<Settings s={s} open={null} onOpen={() => undefined} />} /> : <Settings s={s} open={open} onOpen={setOpen} />}
    </div>
  );
}

/** The settings as `s` has them, `open` the kind whose ways are shown (and the preview's, one with a banner). */
function Settings({ s, open, onOpen }: { s: SettingsState; open: Kind | "services" | null; onOpen(kind: Kind | "services" | null): void }) {
  return <>
    <Preview s={s} kind={(open !== "services" ? open : null) ?? KINDS_SHOWN.find((k) => s.banner(k)) ?? "wait"} />
    <Section title={t("web-pages.notifications.ways.title")} description={s.note}>
      {CAN_NOTIFY && <div className={css.tiles}>
        <Tile way="banner" on={s.state === "on"} busy={s.busy} disabled={s.state === "unsupported" || s.permission === "denied"}
          action={s.permission === "denied" ? t("web-pages.notifications.enable.open") : s.permission === "default" ? t("web-pages.notifications.enable.allow") : undefined}
          onChange={(on) => (s.permission === "default" ? void requestPermission() : s.permission !== "denied" && s.setBanner(on))} />
      </div>}
    </Section>
    <Section title={t("web-pages.notifications.kinds.title")}>
      <div className={`${pagesCss.card} ${css.kinds}`}>
        {KINDS_SHOWN.map((k) => (
          <KindRow key={k} kind={k} s={s} open={open === k} onOpen={() => onOpen(open === k ? null : k)} />
        ))}
        <ServicesRow s={s} open={open === "services"} onOpen={() => onOpen(open === "services" ? null : "services")} />
      </div>
    </Section>
    <Section title={t("web-pages.notifications.more.title")}>
      <div className={pagesCss.card}>
        {/* (a browser's pushes follow it too: the cloud makes them as its registration says) */}
        <SwitchRow title={t("web-pages.notifications.preview")} description={t("web-pages.notifications.previewNote")}
          checked={s.preview} disabled={s.state !== "on"} onChange={s.setPreview} />
        <p className={css.sound}>{t("web-pages.notifications.browserNote")}</p>
      </div>
    </Section>
  </>;
}

/** Every setting the page shows, as the core keeps them, and their changing. */
function useSettings(workspace: string) {
  const toast = useToast();
  const state = useNotifyState();
  const [busy, setBusy] = useState(false);
  const notify = useTopic<NotifyView>({ topic: "notify" }).value;
  const notices = useTopic<{ items: Notice[] }>({ topic: "notices", workspace }).value?.items ?? [];
  const kept = useWorkspaceMarks(workspace)?.badgeKinds?.services ?? true;
  const [bell, setBellNow] = useState<boolean | null>(null);
  useEffect(() => setBellNow(null), [kept]);
  // What was just chosen shows before the core says it back.
  const [kinds, setKinds] = useState<NotifyKinds | null>(null);
  const [preview, setPreviewNow] = useState<boolean | null>(null);
  useEffect(() => setKinds(null), [notify?.kinds?.wait, notify?.kinds?.failed, notify?.kinds?.done, notify?.kinds?.message]);
  useEffect(() => setPreviewNow(null), [notify?.preview]);

  const k = kinds ?? notify?.kinds ?? NOTIFY_DEFAULT;
  const note = state === "unsupported" ? t("web-pages.notifications.unsupported") : t("web-pages.notifications.noteBrowser");
  const failed = (e: unknown) => toast(t("web-pages.notifications.kindsFailed", { error: failure(e) }));

  return {
    state: state as NotifyState, busy, note,
    /** The core's settings have come (until then, what is shown would be the defaults). */
    read: notify !== undefined,
    notices, preview: preview ?? notify?.preview ?? true,
    permission: notify?.permission ?? "unknown",
    kinds: k,
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
    /** Whether the services left up long light the rail's bell (`badgeKinds.services`). */
    bell: bell ?? kept,
    setBell: (on: boolean) => {
      setBellNow(on);
      core().call("prefs.set", { badgeKinds: { services: on } }).catch((e: unknown) => { setBellNow(null); failed(e); });
    },
    setPreview: (on: boolean) => {
      setPreviewNow(on);
      core().call("notify.set", { preview: on }).catch((e: unknown) => { setPreviewNow(null); failed(e); });
    },
  };
}
type SettingsState = ReturnType<typeof useSettings>;

export type Way = "banner" | "badge";

/** One way of telling, as a tile with a picture of it: pressed, on or off. `action`: the system has to allow it first,
 * the tile is the way to (its words on a button in it, the picture marked): pressed, it goes there. */
export function Tile({ way, on, onChange, busy, disabled, action }: { way: Way; on: boolean; onChange(on: boolean): void; busy?: boolean; disabled?: boolean; action?: string | undefined }) {
  return (
    <button type="button" className={css.tile} aria-pressed={action ? undefined : on} data-on={(on && !action) || undefined} data-action={action ? true : undefined} disabled={busy || disabled} onClick={() => onChange(!on)}>
      <span className={css.tilePicture} aria-hidden="true">
        {action && <span className={css.picAlert}>!</span>}
        {way === "banner" ? <span className={css.picBanner} data-system={SYSTEM} /> : <span className={css.picApp}><span className={css.picBadge} /></span>}
      </span>
      <span className={css.tileName}>{t(`web-pages.notifications.ways.${way}`)}</span>
      {action ? <span className={css.tileAction}>{action}<ChevronRight size={14} aria-hidden="true" /></span>
        : <span className={css.tileState}>{on ? t("web-pages.notifications.on") : t("web-pages.notifications.off")}</span>}
    </button>
  );
}

/** A kind of thing that happens: what tells of it, in a line; opened, each way on or off. */
function KindRow({ kind, s, open, onOpen }: { kind: Kind; s: SettingsState; open: boolean; onOpen(): void }) {
  const ways = [
    CAN_NOTIFY && s.banner(kind) ? (kind === "done" && s.kinds.done === "away" ? t("web-pages.notifications.sumBannerAway") : t("web-pages.notifications.ways.banner")) : null,
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
        </div>
      )}
    </div>
  );
}

/** The services and jobs left up long: told of only by the rail's bell, which they light until it has shown them. */
function ServicesRow({ s, open, onOpen }: { s: SettingsState; open: boolean; onOpen(): void }) {
  return (
    <div className={css.kind} data-open={open || undefined}>
      <button type="button" className={css.kindHead} aria-expanded={open} onClick={onOpen}>
        <span className={css.kindText}><span>{t("web-pages.notifications.kinds.services")}</span><span className={css.muted}>{t("web-pages.notifications.kinds.servicesNote")}</span></span>
        <span className={css.sum}>{s.bell ? t("web-pages.notifications.ways.bell") : t("web-pages.notifications.none")}</span>
        <ChevronRight size={16} className={css.chevron} aria-hidden="true" />
      </button>
      {open && (
        <div className={css.kindWays}>
          <WayRow title={t("web-pages.notifications.inBell")} checked={s.bell} disabled={false} onChange={s.setBell} />
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

/** A screen of this device's system as the settings make it (SYSTEM): the banner of `kind` (the latest one that came,
 * else a sample) where the system shows one, the app's icon among others with what it carries now: on Android the
 * system's own dot while a banner shows. */
function Preview({ s, kind }: { s: SettingsState; kind: Kind }) {
  const latest = [...s.notices].reverse().find((n) => (n.kind === "block" ? "wait" : n.kind) === kind);
  const shown = latest ? { title: latest.title, body: latest.body } : SAMPLE[kind]();
  const body = s.preview ? shown.body : t(`web-pages.notifications.hidden.${kind}`);
  const banner = CAN_NOTIFY && s.banner(kind);
  const dot = SYSTEM === "phone" && !IOS && banner;
  const card = (
    <div className={SYSTEM === "phone" ? css.bannerAcross : css.banner} data-system={SYSTEM} data-off={!banner || undefined}>
      <img src={ICON} alt="" className={css.bannerIcon} />
      <span className={css.bannerText}>
        <span className={css.bannerHead}><b>{shown.title}</b><span className={css.muted}>{t("web-pages.notifications.now")}</span></span>
        <span className={css.bannerBody}>{body}</span>
      </span>
    </div>
  );
  const icons = (
    <>
      <span className={SYSTEM === "phone" ? css.homeApp : css.appIcon} />
      <span className={SYSTEM === "phone" ? css.homeApp : css.appIcon} />
      <span className={SYSTEM === "phone" ? css.homeAppMine : css.appIconMine}>
        <img src={ICON} alt="" className={css.appIconImage} />
        {dot && <span className={css.dot} />}
      </span>
      <span className={SYSTEM === "phone" ? css.homeApp : css.appIcon} />
    </>
  );
  if (SYSTEM === "phone") {
    // The device itself, standing up from the preview's foot, its top in view.
    return (
      <div className={css.stage} aria-label={t("web-pages.notifications.previewLabel")} role="img" data-depicts>
        <div className={css.device} data-tablet={TABLET || undefined}>
          <div className={css.deviceScreen}>
            <div className={css.status}><span>9:41</span><span className={css.battery} /></div>
            <span className={IOS ? css.island : css.hole} />
            <div className={css.homeRow}>{icons}</div>
            {card}
          </div>
        </div>
      </div>
    );
  }
  return (
    <div className={css.screen} aria-label={t("web-pages.notifications.previewLabel")} role="img" data-depicts>
      {card}
      <div className={SYSTEM === "windows" ? css.taskbar : css.dockBar}>{icons}</div>
    </div>
  );
}
