// One of the Android app's drawings (Drawables.ts): `Illustration(light, dark, width)` as ui/Parts.kt has it, and
// any drawing at a width, its height as its own aspect.
import { SvgXml } from "react-native-svg";
import { Drawables, type DrawableName } from "./Drawables";
import { useC } from "./Theme";

export function Drawing({ name, width, height }: { name: DrawableName; width?: number; height?: number }) {
  const d = Drawables[name];
  const w = width ?? (height !== undefined ? (height * d.width) / d.height : d.width);
  const h = height ?? (w * d.height) / d.width;
  return <SvgXml xml={d.svg} width={w} height={h} />;
}

/** ui/Parts.kt Illustration: the light or the dark drawing, `width` wide. */
export function Illustration({ light, dark, width }: { light: DrawableName; dark: DrawableName; width: number }) {
  const C = useC();
  return <Drawing name={C.dark ? dark : light} width={width} />;
}
