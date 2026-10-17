// 重试 for a connection down (the web's Connection.tsx): the connections tried again at once.
import { Pressable, View, type StyleProp, type ViewStyle } from "react-native";
import { core } from "../../../../web/src/core/react.ts";
import { useDoing } from "../../../../web/src/doing.ts";
import { app } from "../AppState";
import { t } from "../i18n";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { Spinner } from "../ui/Waiting";

/**
 * 重试 as a small grey pill: the connections tried again at once, a spinner in it until the core has and while `retrying`
 * (the station's link: down, and tried again just now). On a station down, where it is tried again (Stations.tsx).
 */
export function RetryPill({ style, retrying = false }: { style?: StyleProp<ViewStyle>; retrying?: boolean }) {
  const C = useC();
  const trying = useDoing("client.wake") || retrying;
  return (
    <View style={[{ height: 22, borderRadius: 11, overflow: "hidden", backgroundColor: C.chip }, style]}>
      <Pressable
        disabled={trying}
        android_ripple={{ color: withAlpha(C.ink, 0.1) }}
        onPress={() => {
          // A person's retry (client/core-ts/src/wake.ts): `network` for a core from before `retry`.
          app.act(t("android-misc.connection.reconnect"), () => core().call("client.wake", { away: 0, network: true, retry: true }));
        }}
        style={{ height: 22, paddingHorizontal: 10, flexDirection: "row", alignItems: "center", gap: 5 }}
      >
        {trying && <Spinner inline />}
        <T size={13} color={C.ink}>{t("common.retry")}</T>
      </Pressable>
    </View>
  );
}
