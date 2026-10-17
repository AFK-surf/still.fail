// A row that scrolls sideways, as tall as what it holds (Compose's horizontalScroll). React Native's horizontal
// ScrollView on Android, left to size itself in a list's cell, took the list's whole height (a table 43 000 px tall),
// and what it holds stretched with it: so it is given its height, worked out by whoever knows what it holds.
import type { ReactNode } from "react";
import { ScrollView, type ScrollViewProps } from "react-native";

export function SideScroll({ height, style, children, ...rest }: Omit<ScrollViewProps, "horizontal"> & { height: number; children?: ReactNode }) {
  return (
    <ScrollView horizontal {...rest} style={[style, { height }]}>
      {children}
    </ScrollView>
  );
}
