// iOS: the system's tab bar (Liquid Glass on iOS 26), shrinking as a list scrolls down.
import { Icon, Label, NativeTabs } from "expo-router/unstable-native-tabs";
import { useColors } from "./theme";

export default function Tabs() {
  const c = useColors();
  return (
    <NativeTabs minimizeBehavior="onScrollDown" tintColor={c.accent}>
      <NativeTabs.Trigger name="(chats)">
        <Label>对话</Label>
        <Icon sf={{ default: "bubble.left.and.bubble.right", selected: "bubble.left.and.bubble.right.fill" }} />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="files">
        <Label>文件</Label>
        <Icon sf={{ default: "folder", selected: "folder.fill" }} />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="profiles">
        <Label>Profile</Label>
        <Icon sf="key" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="stations">
        <Label>Station</Label>
        <Icon sf="server.rack" />
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
