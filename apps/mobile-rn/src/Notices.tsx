// Notifications (docs/notifications.md → Clients): one channel (消息), one notification per chat (its tag), opening the
// chat at the message it is about. Local notices are those the core's `notify` says to show while the app is in front
// (Main.tsx; client/core-ts/src/attend.ts decides), pushes come while it is not (Push). 我 → 通知 turns both off (kept
// in the core). Notices.kt, with expo-notifications for the system's NotificationManager.
import * as Notifications from "expo-notifications";
import { useEffect, useRef } from "react";
import { Platform } from "react-native";
import type { Notice, NotifyView } from "../../../web/src/core/shapes.ts";
import { app as theApp, useApp, type AppState } from "./AppState";
import { APP_NAME, CLOUD_ORIGIN } from "./build";
import { Topics } from "./data/Topics";
import { t } from "./i18n";

const CHANNEL = "messages";

// Shown as the system shows any notification, the app in front or not (the Kotlin's notify does not ask).
Notifications.setNotificationHandler({
  handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false }),
});

/** What the system said last (asked again each time the app comes in front): whether the app may show notifications. */
let granted: boolean | null = null;
let canAsk = true;
function refresh() {
  Notifications.getPermissionsAsync().then((p) => { granted = p.granted; canAsk = p.canAskAgain; }, () => undefined);
}
refresh();

// A tap opens the chat (its url) at the message it is about (its seq), as MainActivity's ACTION_VIEW with AT does.
Notifications.addNotificationResponseReceivedListener((response) => {
  const data = response.notification.request.content.data as { url?: string; seq?: number } | undefined;
  if (typeof data?.url !== "string") return;
  theApp.openLink(CLOUD_ORIGIN.replace(/\/+$/, "") + data.url, true, typeof data.seq === "number" && data.seq > 0 ? data.seq : null);
});

export const Notifier = {
  /** Whether the app is on screen (Main.tsx's started and stopped). */
  inFront: false,

  allowed(): boolean { return granted === true; },

  /**
   * What the system lets the app show, as the core's `notify.permission` takes it (what every client's notifications
   * page shows): the app's notifications on, off, or not asked yet (`asked`: whether it was, as the core keeps it).
   */
  permission(asked: boolean | null): string {
    refresh();
    if (granted === true) return "granted";
    if ((Platform.OS === "ios" || (Platform.OS === "android" && Number(Platform.Version) >= 33)) && asked === false && canAsk) return "default";
    return "denied";
  },

  /** A tap opens the chat (`url`) at the message it is about (`seq`; at its usual place without one: an older station or cloud). */
  async show(tag: string, title: string, body: string, url: string, seq: number | null | undefined) {
    if (Platform.OS === "android") {
      await Notifications.setNotificationChannelAsync(CHANNEL, { name: t("android-misc.notify.channel"), importance: Notifications.AndroidImportance.HIGH });
    }
    // The chat's tag as its identifier: a newer one for a chat replaces the older.
    await Notifications.scheduleNotificationAsync({
      identifier: tag,
      content: { title, body, data: { url, ...(seq != null ? { seq } : {}) }, color: "#E5704A", categoryIdentifier: undefined },
      trigger: Platform.OS === "android" ? { channelId: CHANNEL } : null,
    });
  },

  showNotice(notice: Notice) { return Notifier.show(notice.tag, notice.title, notice.body, notice.url, notice.seq); },

  /** A chat opened: its notification is read. */
  cancel(tag: string) { Notifications.dismissNotificationAsync(tag).catch(() => undefined); },
};

/**
 * While the app is in front: the notices the core's `notify` says to show now (not while off, not for the chat looked
 * at, only of the workspace the app is in; client/core-ts/src/attend.ts), each shown once it is taken (`notice.claim`).
 * Returns how to stop.
 */
export function showNotices(app: AppState): () => void {
  const taken = new Set<string>();
  let workspace: string | null | undefined;
  let stop: (() => void) | null = null;
  const follow = () => {
    if (app.workspace === workspace) return;
    workspace = app.workspace;
    stop?.();
    stop = app.core.subscribe(Topics.notify(workspace), (value) => {
      const view = value as NotifyView | null;
      if (view == null || typeof view !== "object" || !Array.isArray(view.show)) return;
      for (const notice of view.show) {
        if (taken.has(notice.id)) continue;
        taken.add(notice.id);
        app.core.call("notice.claim", { id: notice.id }).then(
          (answer) => { if ((answer as { show?: boolean } | null)?.show === true) void Notifier.showNotice(notice); },
          () => undefined,
        );
      }
    }, () => undefined);
  };
  follow();
  const unwatch = app.subscribe(follow);
  return () => { unwatch(); stop?.(); };
}

/**
 * Asks for the system's permission once, the first time the app is signed in with notifications on; `ask` is also what
 * 我 → 通知 turned on calls.
 */
export function rememberNotificationAsk(app: AppState, once: boolean): () => void {
  const ask = useRef(() => {
    if (Notifier.allowed() || !(Platform.OS === "ios" || Number(Platform.Version) >= 33)) return;
    Notifications.requestPermissionsAsync().then((p) => {
      granted = p.granted;
      canAsk = p.canAskAgain;
      if (!p.granted && !once) app.toast = t("android-misc.notify.allowInSettings", { app: APP_NAME });
      // The answer, to the core at once.
      app.core.call("notify.permission", { state: p.granted ? "granted" : "denied" }).catch(() => undefined);
    }, () => undefined);
  }).current;
  // Once the core says whether it was asked.
  const notify = useApp((s) => s.notify);
  const asked = useApp((s) => s.notifyAsked);
  useEffect(() => {
    if (once && notify && asked === false) { void app.askedNotify(); ask(); }
  }, [once, notify, asked]); // eslint-disable-line react-hooks/exhaustive-deps
  return ask;
}
