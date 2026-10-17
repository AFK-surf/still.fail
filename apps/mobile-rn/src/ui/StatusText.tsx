// A status line with the core's done and waiting leads drawn as the web's StatusText draws them (a check, an open arc
// and dots) in place of their words.
import { View, type StyleProp, type TextStyle } from "react-native";
import { t } from "../i18n";
import { Icon, Icons } from "./Icon";
import { T } from "./Text";
import { useC } from "./Theme";

/** The core's done lead in either language (client/core-ts present.ts: 做完了, 做完了：<why>; Done, Done: <why>). */
export const doneLead = /^(?:(?:做完了|已完成)(?:：|$)|Done(?:: |$))/;

/** The core's waiting lead in either language (present.ts: 等待中, 在等：<what>; Waiting, Waiting: <what>). */
export const waitLead = /^(?:在等：|等待：|等待中$|Waiting(?:: |$))/;

/** Same compact completed/waiting label as web StatusText (a check, an open arc and dots); the explanation and accessible name stay intact. */
export function StatusText({
  text,
  modifier,
  fontSize,
  color,
  maxLines,
  overflow = "clip",
  style,
  lineHeight,
}: {
  text: string;
  modifier?: StyleProp<TextStyle>;
  fontSize?: number;
  color?: string;
  maxLines?: number;
  overflow?: "clip" | "ellipsis";
  style?: StyleProp<TextStyle>;
  lineHeight?: number;
}) {
  const C = useC();
  const ink = color ?? C.muted;
  const done = doneLead.exec(text);
  const lead = done ?? waitLead.exec(text);
  const reason = lead ? text.substring(lead[0].length) : "";
  const leadWords = lead ? t(done ? "android-misc.status.done" : "android-misc.status.waiting") : "";
  return (
    <T
      size={fontSize}
      line={lineHeight}
      color={ink}
      numberOfLines={maxLines}
      ellipsizeMode={overflow === "ellipsis" ? "tail" : "clip"}
      style={[style, modifier]}
      accessibilityLabel={lead ? leadWords + (reason ? ` ${reason}` : "") : undefined}
    >
      {lead ? (
        <>
          {/* The lead's mark in a 14sp box, centred on the text (PlaceholderVerticalAlign.TextCenter). */}
          <View style={{ width: 14, height: 14 }}>
            <Icon icon={done ? Icons.Check : Icons.Wait} size={14} color={ink} />
          </View>
          {reason ? ` ${reason}` : ""}
        </>
      ) : (
        text
      )}
    </T>
  );
}
