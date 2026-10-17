// Installing an APK (an update of the app, a file a chat has): the system's installer, asked; what it says (Install.kt).
import { requireOptionalNativeModule, type EventSubscription } from "expo-modules-core";
import { ToastAndroid } from "react-native";
import { t } from "./i18n";

/** What the system's installer said of a session (PackageInstaller.EXTRA_STATUS), as the native side hands it on. */
export type InstallStatus = "pendingUserAction" | "success" | "aborted" | "failure";

/**
 * The native side of installing (the Android app does it in Kotlin: PackageManager, PackageInstaller, a
 * BroadcastReceiver for what the installer says).
 */
interface ApkInstaller {
  /** PackageManager.canRequestPackageInstalls(). */
  canRequestPackageInstalls(): boolean;
  /** The system's page for this app's 安装未知应用 (Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, package:<this app>). */
  openUnknownSources(): void;
  /**
   * A PackageInstaller session (MODE_FULL_INSTALL) with the APK at `path` written into it ("stillfail.apk", fsync'd),
   * committed with a broadcast (FLAG_UPDATE_CURRENT, FLAG_MUTABLE from Android 12: the installer puts its status in
   * it). `self`: this app's own newer build: setAppPackageName(this app) and, from Android 12,
   * USER_ACTION_NOT_REQUIRED. A status of `pendingUserAction` has the native side start the installer's confirm page
   * (EXTRA_INTENT, FLAG_ACTIVITY_NEW_TASK) itself, then say it here.
   */
  install(path: string, self: boolean): void;
  addListener(event: "result", listener: (said: { status: InstallStatus; message?: string | null; self: boolean }) => void): EventSubscription;
}

// NATIVE: the StillfailInstall module (canRequestPackageInstalls, the unknown-sources page, a PackageInstaller session
// and the receiver of its status, as Install.kt has them) is not in modules/ yet; until it is, nothing installs.
const installer = requireOptionalNativeModule<ApkInstaller>("StillfailInstall");

/** Whether this app may install apps (安装未知应用); when not, the system's page for it opens instead. */
export function mayInstall(): boolean {
  if (installer == null) return false;
  if (installer.canRequestPackageInstalls()) return true;
  installer.openUnknownSources();
  return false;
}

/**
 * Hands an APK (a file on the phone's disk, `apk` its path) to the system's installer; what it says comes to
 * `InstallResult`, which opens its page for the person to confirm. `self`: this app's own newer build, installed over
 * it without asking where the system allows that.
 */
export function installApk(apk: string, self = false): void {
  if (installer == null) return;
  InstallResult.listen();
  installer.install(apk, self);
}

/** What the installer said, heard (the Android app's BroadcastReceiver). */
export const InstallResult = {
  SELF: "self",
  listening: null as EventSubscription | null,

  listen(): void {
    if (InstallResult.listening != null || installer == null) return;
    InstallResult.listening = installer.addListener("result", ({ status, message, self }) => InstallResult.onReceive(status, message ?? null, self));
  },

  onReceive(status: InstallStatus, message: string | null, self: boolean): void {
    switch (status) {
      // Its confirm page opened by the native side.
      case "pendingUserAction": return;
      case "success": return;
      case "aborted": return;
      default: {
        // The words follow the core's language already (src/i18n.ts), the Kotlin's KeptLang.words.
        const said = message ?? t("android-misc.updates.installFailed");
        const words = self ? "android-misc.updates.failed" : "android-chat.file.installFailed";
        ToastAndroid.show(t(words, { error: said }), ToastAndroid.LONG);
      }
    }
  },
};
