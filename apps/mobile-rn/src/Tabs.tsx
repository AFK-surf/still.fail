// Android: still.fail's own bottom bar (下方栏) over the pages.
import { Tabs as RouterTabs } from "expo-router";
import { Bar } from "./Bar";

export default function Tabs() {
  return (
    <RouterTabs screenOptions={{ headerShown: false, animation: "shift" }} tabBar={(props) => <Bar {...props} />}>
      <RouterTabs.Screen name="(chats)" options={{ title: "对话" }} />
      <RouterTabs.Screen name="files" options={{ title: "文件" }} />
      <RouterTabs.Screen name="profiles" options={{ title: "Profile" }} />
      <RouterTabs.Screen name="stations" options={{ title: "Station" }} />
    </RouterTabs>
  );
}
