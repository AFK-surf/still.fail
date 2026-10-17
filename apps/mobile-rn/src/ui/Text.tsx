// Text as the Android app sets it (ui/Theme.kt WebType: line height 1.4 × the size, no letter spacing), in the
// palette's ink unless told: `<T size={15} weight="600" color={C.muted}>`.
import type { ReactNode } from "react";
import { Text, type StyleProp, type TextProps, type TextStyle } from "react-native";
import { useC } from "./Theme";

export interface TProps extends TextProps {
  /** sp, as the Kotlin's fontSize (Material's body is 16). */
  size?: number;
  weight?: TextStyle["fontWeight"];
  color?: string;
  /** Line height in sp; 1.4 × the size unless given. */
  line?: number;
  align?: TextStyle["textAlign"];
  mono?: boolean;
  style?: StyleProp<TextStyle>;
  children?: ReactNode;
}

export function T({ size = 16, weight, color, line, align, mono, style, children, ...rest }: TProps) {
  const C = useC();
  return (
    <Text
      {...rest}
      style={[{ fontSize: size, lineHeight: line ?? size * 1.4, color: color ?? C.ink, fontWeight: weight, textAlign: align, letterSpacing: 0, includeFontPadding: false }, mono && { fontFamily: "JetBrainsMono" }, style]}
    >
      {children}
    </Text>
  );
}
