// An icon of still.fail's set (IconSet.ts, the Android app's Icons): drawn in the colour it is given at the set's
// 1.75 line, 24 units square scaled to `size`.
import { memo } from "react";
import Svg, { Path } from "react-native-svg";
import { Icons, type IconName, type IconPaths } from "./IconSet";

export { Icons, type IconName };

export const Icon = memo(function Icon({ icon, size = 24, color }: { icon: IconPaths | IconName; size?: number; color: string }) {
  const paths = typeof icon === "string" ? Icons[icon] : icon;
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      {paths.lines.map((d, i) => <Path key={`l${i}`} d={d} fill="none" stroke={color} strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" />)}
      {paths.dots.map((d, i) => <Path key={`d${i}`} d={d} fill={color} />)}
    </Svg>
  );
});
