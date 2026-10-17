import { router, useLocalSearchParams } from "expo-router";
import { useEffect, useRef } from "react";
import { FlatList, Platform, Pressable, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { ChatRow } from "../../src/ChatRow";
import { tour } from "../../src/demo";
import { chats, type Chat } from "../../src/data";
import { Icon } from "../../src/Icon";
import { useColors } from "../../src/theme";
import { TOP, TopBar } from "../../src/TopBar";

export default function Chats() {
  const c = useColors();
  const insets = useSafeAreaInsets();
  const ios = Platform.OS === "ios";
  const list = useRef<FlatList<Chat>>(null);
  const { demo } = useLocalSearchParams<{ demo?: string }>();
  useEffect(() => {
    if ((demo || process.env.EXPO_PUBLIC_DEMO) && list.current) tour(list.current as unknown as FlatList<unknown>);
  }, [demo]);
  const settings = (
    <Pressable hitSlop={10} style={{ padding: 8 }}>
      <Icon name="settings" color={c.ink} size={22} />
    </Pressable>
  );
  const rows = (
    <FlatList
      ref={list}
      data={chats}
      keyExtractor={(chat) => chat.id}
      renderItem={({ item }) => <ChatRow chat={item} onPress={() => router.push({ pathname: "/chat/[id]", params: { id: item.id } })} />}
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: c.bg }}
      contentContainerStyle={ios ? undefined : { paddingTop: insets.top + TOP + 4, paddingBottom: insets.bottom + 88 }}
    />
  );
  // iOS: the list is the page itself, as the system's large title and tab bar need it to follow its scrolling.
  if (ios) return rows;
  return (
    <View style={{ flex: 1, backgroundColor: c.bg }}>
      {rows}
      <TopBar title="对话" left={settings} />
    </View>
  );
}
