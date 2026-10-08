import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { activityPulse } from "./conversation.css.ts";

export const callout = style({
  display: "flex", alignItems: "center", gap: "10px", padding: "12px 14px",
  borderRadius: `calc(14px * ${vars.cornerScale})`, fontSize: vars.textSecondary, background: vars.neutralBg,
  cornerShape: vars.cornerShape,
  selectors: {
    "&[data-tone=\"amber\"]": { display: "block", background: vars.amberBg, color: vars.text },
    "&[data-tone=\"blue\"]": { background: vars.blueBg, color: vars.blue },
    "&[data-tone=\"green\"]": { background: vars.greenBg, color: vars.green },
  },
});
export const choiceBadge = style({
  marginLeft: "8px", padding: "1px 7px", borderRadius: "999px", background: vars.accentBg, color: vars.accentText,
  fontSize: vars.textLabel, fontWeight: "500",
});
export const inputRow = style({ display: "flex", gap: "8px", alignItems: "center" });
export const inline = style({
  selectors: {
    // Making the Slack app by hand, when there is no configuration token: tucked under the token form.
    [`${activityPulse}&`]: { display: "inline-block", marginRight: "8px", verticalAlign: "middle" },
  },
});
globalStyle(`${callout} > span`, { flex: "1" });
globalStyle(`${callout}[data-tone="amber"] strong`, { color: vars.amber });
globalStyle(`${callout}[data-tone="amber"] ul`, { margin: "6px 0 0", paddingLeft: "18px", display: "grid", gap: "4px" });
