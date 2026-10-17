// still.fail's icons (design/icons), stroked as drawn there.
import Svg, { Circle, Path } from "react-native-svg";

const paths = {
  chats: "M8 5V4.5Q8 3 10 3H17Q20.5 3 20.5 6.5V11Q20.5 13 18.5 13.5 M7 8H12.5Q16 8 16 11.5V15Q16 18.5 12.5 18.5H9L4 21V17.5Q3 16.5 3 15V12Q3 8 7 8Z",
  folder: "M3.5 7.5Q3.5 4.5 6.5 4.5H9.5L12 7H17.5Q20.5 7 20.5 10V16.5Q20.5 19.5 17.5 19.5H6.5Q3.5 19.5 3.5 16.5Z",
  server: "M8 3.5H16Q20.5 3.5 20.5 8V16Q20.5 20.5 16 20.5H8Q3.5 20.5 3.5 16V8Q3.5 3.5 8 3.5Z M4 12H20 M11 8H16 M11 16H16",
  key: "M12 12L3.5 20.5 M5 19L7 21 M8 16L10 18",
  settings: "M10.5 5L10.5 3L13.5 3L13.5 5L15.89 5.99L17.3 4.58L19.42 6.7L18.01 8.11L19 10.5L21 10.5L21 13.5L19 13.5L18.01 15.89L19.42 17.3L17.3 19.42L15.89 18.01L13.5 19L13.5 21L10.5 21L10.5 19L8.11 18.01L6.7 19.42L4.58 17.3L5.99 15.89L5 13.5L3 13.5L3 10.5L5 10.5L5.99 8.11L4.58 6.7L6.7 4.58L8.11 5.99Z",
  plus: "M12 5V19 M5 12H19",
};
export type IconName = keyof typeof paths;

export function Icon({ name, size = 24, color }: { name: IconName; size?: number; color: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round">
      <Path d={paths[name]} />
      {name === "server" && <><Circle cx={7.5} cy={8} r={1} fill={color} stroke="none" /><Circle cx={7.5} cy={16} r={1} fill={color} stroke="none" /></>}
      {name === "key" && <Circle cx={15.5} cy={8.5} r={5} />}
      {name === "settings" && <Circle cx={12} cy={12} r={3} />}
    </Svg>
  );
}
