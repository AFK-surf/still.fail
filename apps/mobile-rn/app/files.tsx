import { Text, View } from "react-native";
import { useColors } from "../src/theme";

export default function Page() {
  const c = useColors();
  return (
    <View style={{ flex: 1, backgroundColor: c.bg, alignItems: "center", justifyContent: "center" }}>
      <Text style={{ color: c.muted, fontSize: 15 }}>文件</Text>
    </View>
  );
}
