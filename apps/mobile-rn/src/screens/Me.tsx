// The account, as the narrow web has it (web/src/mobile/Me.tsx), from the card atop settings (SettingsHome.kt): who is
// signed in, the accounts on this device, and where it is signed in.
import { Pressable, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { app, useApp } from "../AppState";
import type { Account, WorkspaceEntry } from "../data/Accounts";
import { Auth } from "../data/Calls";
import { rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { Avatar, Card, LargeTitle, ListCard, ListRow, ripple, SectionHeader } from "../ui/Parts";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { Spinner } from "../ui/Waiting";
import { Devices } from "./Settings";
import { signIn } from "./SettingParts";
import { TopBack } from "./Stations";

export function MeScreen({ current }: { current: WorkspaceEntry }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  useApp((s) => s.doing);
  const accounts = rememberTopic<Account[]>(Topics.accounts);
  const me = current.account;
  const list = accounts.value ?? [];
  const opening = app.isDoing("auth.begin");
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-settings.title")} onBack={() => app.pop()} />
      <LargeTitle small="" big={t("android-settings.me.title")} />
      <Card>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 14 }}>
          <Avatar id={me.email} name={me.name || me.email} size={46} picture={me.picture} />
          <View style={{ flexShrink: 1 }}>
            <T size={16} weight="700" color={C.ink}>{me.name || me.email}</T>
            <T size={13} color={C.muted}>{`${me.email} · Google`}</T>
          </View>
        </View>
      </Card>
      {/* Accounts: signing out is per account, as on the web (with one account it is just 退出登录), and another can be added. */}
      <SectionHeader title={t("android-settings.me.accounts")} start={24} />
      <ListCard>
        {list.map((a) => (
          <ListRow key={a.sub}>
            <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail" style={{ flex: 1, minWidth: 0 }}>{a.email}</T>
            {/* Signing out: home at once, the sign-out going on by itself (a toast if it could not); not asked twice meanwhile. */}
            {app.isDoing("auth.signOut", { account: a.sub }) ? <Spinner inline /> : (
              <Pressable android_ripple={ripple(C.ink)} onPress={() => {
                app.home();
                app.act(t("android-settings.me.signOutWhat"), () => Auth.signOut(app.core, a.sub), list.length > 1 ? t("android-settings.me.signedOut", { email: a.email }) : undefined);
              }}>
                <T size={15} color={C.red}>{list.length > 1 ? t("android-settings.me.signOut") : t("android-settings.me.signOutOnly")}</T>
              </Pressable>
            )}
          </ListRow>
        ))}
        <ListRow onClick={opening ? null : () => { void signIn(app); }}>
          <T size={15} color={C.accent} style={{ flex: 1, minWidth: 0 }}>{t("android-settings.me.addAccount")}</T>
          {opening && <Spinner inline />}
        </ListRow>
      </ListCard>
      <SectionHeader title={t("android-settings.me.devices")} start={24} />
      <Devices current={current} />
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}
