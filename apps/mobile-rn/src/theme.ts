// still.fail's colours (apps/android/shared/.../ui/Theme.kt).
import { useColorScheme } from "react-native";

const light = { bg: "#F5F3EF", surface: "#FFFFFF", raised: "#FFFFFF", ink: "#24272B", muted: "#7A7D83", subtle: "#A6A8AC", line: "#E7E3DC", accent: "#E5704A", green: "#2F8F5B", bubble: "#E8E4DC" };
const dark = { bg: "#1B1C1F", surface: "#26272B", raised: "#2A2C31", ink: "#ECECED", muted: "#9A9DA3", subtle: "#6E7177", line: "#34353A", accent: "#EF7A55", green: "#5CC08A", bubble: "#313237" };
export type Colors = typeof light;
export function useColors(): Colors & { dark: boolean } {
  const dk = useColorScheme() === "dark";
  return { ...(dk ? dark : light), dark: dk };
}
