//! Whether the system lets the desktop app show notifications, as its own settings say (System Settings'
//! Notifications on macOS, Settings' Notifications on Windows): the page's notification settings show it, since a
//! notification the system turns away is silently lost. "default" is macOS's not asked yet; "unknown" is anything
//! not known (another platform, no app bundle, an error, no answer in time).
use napi_derive::napi;

#[napi]
pub fn status(app_id: String) -> String {
    // Nothing here may unwind into Node.
    std::panic::catch_unwind(|| system(&app_id))
        .unwrap_or("unknown")
        .to_string()
}

#[cfg(target_os = "macos")]
fn system(_app_id: &str) -> &'static str {
    use objc2_foundation::NSBundle;
    use objc2_user_notifications::{
        UNAuthorizationStatus, UNNotificationSettings, UNUserNotificationCenter,
    };
    use std::{ptr::NonNull, sync::mpsc, time::Duration};

    // The notification center raises an Objective-C exception, which aborts the process, when the process is not an
    // app bundle (plain node): it asks only for its own bundle, so appId is not used here.
    if NSBundle::mainBundle().bundleIdentifier().is_none() {
        return "unknown";
    }
    // The handler runs on the center's own queue; a late answer goes to a closed channel and is dropped.
    let (tx, rx) = mpsc::sync_channel(1);
    let handler = block2::RcBlock::new(move |settings: NonNull<UNNotificationSettings>| {
        let _ = tx.try_send(unsafe { settings.as_ref() }.authorizationStatus());
    });
    UNUserNotificationCenter::currentNotificationCenter()
        .getNotificationSettingsWithCompletionHandler(&handler);
    match rx.recv_timeout(Duration::from_secs(2)) {
        Ok(
            UNAuthorizationStatus::Authorized
            | UNAuthorizationStatus::Provisional
            | UNAuthorizationStatus::Ephemeral,
        ) => "granted",
        Ok(UNAuthorizationStatus::Denied) => "denied",
        Ok(UNAuthorizationStatus::NotDetermined) => "default",
        _ => "unknown",
    }
}

#[cfg(windows)]
fn system(app_id: &str) -> &'static str {
    use windows::{
        UI::Notifications::{NotificationSetting, ToastNotificationManager},
        core::HSTRING,
    };

    // The app's AppUserModelID (electron-builder's appId, which the installer's shortcut carries).
    let setting = ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(app_id))
        .and_then(|n| n.Setting());
    match setting {
        Ok(NotificationSetting::Enabled) => "granted",
        Ok(
            NotificationSetting::DisabledForApplication
            | NotificationSetting::DisabledForUser
            | NotificationSetting::DisabledByGroupPolicy
            | NotificationSetting::DisabledByManifest,
        ) => "denied",
        _ => "unknown",
    }
}

#[cfg(not(any(target_os = "macos", windows)))]
fn system(_app_id: &str) -> &'static str {
    "unknown"
}
