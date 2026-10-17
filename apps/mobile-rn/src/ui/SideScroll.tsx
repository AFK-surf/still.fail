// A row that scrolls sideways, as tall as what it holds (Compose's horizontalScroll). React Native's horizontal
// ScrollView on Android lets what it holds stretch to the height it is given, and in a list's cell that was the list's
// whole height (a table 43 000 px tall): here what it holds keeps its own height, and the scroller is made as tall.
import { useState, type ReactNode } from "react";
import { ScrollView, View, type ScrollViewProps, type StyleProp, type ViewStyle } from "react-native";

export function SideScroll({ style, contentContainerStyle, children, ...rest }: Omit<ScrollViewProps, "horizontal"> & { contentContainerStyle?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const [height, setHeight] = useState(0);
  return (
    <ScrollView horizontal {...rest} style={[style, { height }]}>
      <View style={[{ alignSelf: "flex-start" }, contentContainerStyle]} onLayout={(e) => setHeight(Math.ceil(e.nativeEvent.layout.height))}>
        {children}
      </View>
    </ScrollView>
  );
}
