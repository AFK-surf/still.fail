// A first look at the core through the bridge: the accounts it has, and the workspaces (trial; the real page follows).
import { Text, View } from "react-native";
import { useTopic } from "../../../web/src/core/react.ts";
import { useColors } from "../src/theme";

export default function Page() {
  const c = useColors();
  const accounts = useTopic<unknown[]>({ topic: "accounts" });
  const workspaces = useTopic<unknown[]>({ topic: "workspaces" });
  return (
    <View style={{ flex: 1, backgroundColor: c.bg, padding: 24, paddingTop: 80, gap: 12 }}>
      <Text style={{ color: c.ink }}>accounts: {accounts.loading ? "…" : accounts.error ? accounts.error.message : JSON.stringify(accounts.value).slice(0, 300)}</Text>
      <Text style={{ color: c.ink }}>workspaces: {workspaces.loading ? "…" : workspaces.error ? workspaces.error.message : JSON.stringify(workspaces.value).slice(0, 300)}</Text>
    </View>
  );
}
