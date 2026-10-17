// Signed out: the sign-in page (the Android app's screens/SignIn.kt). Google, through still.fail cloud, in the browser
// (SettingParts signIn); the app takes it back on its scheme (src/Main.tsx). A dev cloud's own users besides, when
// build.ts CLOUD_ORIGIN (EXPO_PUBLIC_STILLFAIL_CLOUD) is one.
import { useContext, useState } from "react";
import { Pressable, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { LocalApp, useApp, type AppState } from "../AppState";
import { t } from "../i18n";
import { Illustration } from "../ui/Drawing";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { signIn } from "./SettingParts";

/** A dev cloud (cloud/test/dev.ts) signs its users in without Google: alice (its admin, with a workspace) or bob (let in by nothing yet), through the core (`dev.signIn`). */
const DEV_CLOUD = /^http:\/\/(127\.0\.0\.1|localhost|10\.0\.2\.2):\d+$/;

async function devSignIn(app: AppState, user: string) {
  try {
    await app.core.call("dev.signIn", { user });
  } catch (e) {
    app.toast = t("android-settings.signIn.failed", { error: e instanceof Error ? e.message : String(e) });
  }
}

export function SignInScreen() {
  const app = useContext(LocalApp);
  const C = useC();
  const insets = useSafeAreaInsets();
  const [asked, setAsked] = useState(false);
  const doing = useApp(() => app.isDoing("auth.begin"));
  const busy = asked || doing;
  // A dev account signing in (against a dev cloud only: the Android app's debug builds; here a dev origin is enough).
  const [dev, setDev] = useState<string | null>(null);
  return (
    <View
      style={{
        flex: 1, backgroundColor: C.bg,
        paddingTop: insets.top + 40, paddingBottom: insets.bottom + 40, paddingLeft: insets.left + 30, paddingRight: insets.right + 30,
        alignItems: "center", justifyContent: "center", gap: 12,
      }}
    >
      <Illustration light="illus_sign_in" dark="illus_sign_in_dark" width={300} />
      <T size={28} weight="700" color={C.ink} style={{ letterSpacing: -0.5, paddingTop: 10 }}>{t("android-settings.signIn.title")}</T>
      <T size={15} color={C.muted} align="center">{t("android-settings.signIn.note")}</T>
      <View style={{ height: 6 }} />
      <View style={{ alignSelf: "stretch", height: 50, borderRadius: 25, overflow: "hidden", backgroundColor: C.ink }}>
        <Pressable
          disabled={busy}
          accessibilityRole="button"
          android_ripple={{ color: C.dark ? "rgba(0,0,0,0.12)" : "rgba(255,255,255,0.16)", borderless: false }}
          onPress={() => {
            setAsked(true);
            signIn(app).finally(() => setAsked(false));
          }}
          style={{ flex: 1, flexDirection: "row", gap: 10, alignItems: "center", justifyContent: "center" }}
        >
          <T size={16} weight="600" color={C.bg}>{busy ? t("common.opening") : t("android-settings.signIn.google")}</T>
        </Pressable>
      </View>
      <T size={12} color={C.muted}>{t("android-settings.signIn.many")}</T>
      {DEV_CLOUD.test(app.cloudOrigin) ? (
        <View style={{ flexDirection: "row" }}>
          {["alice", "bob"].map((user) => (
            <Pressable
              key={user}
              disabled={dev != null}
              onPress={() => {
                setDev(user);
                devSignIn(app, user).finally(() => setDev(null));
              }}
              style={{ padding: 8 }}
            >
              <T size={14} color={C.accent}>{dev === user ? t("android-settings.signIn.signingIn") : t("android-settings.signIn.dev", { user })}</T>
            </Pressable>
          ))}
        </View>
      ) : null}
    </View>
  );
}
