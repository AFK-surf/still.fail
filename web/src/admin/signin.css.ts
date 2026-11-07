// The admin's sign-in page's ways (signin.tsx): one column, each as wide as the others, as the console's own page had them.
import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const ways = style({ display: "flex", flexDirection: "column", alignItems: "stretch", gap: "12px", width: "300px", maxWidth: "100%", marginTop: "8px" });
export const or = style({ color: vars.subtle, fontSize: vars.textMeta, textAlign: "center", lineHeight: "16px" });
export const ghost = style({ borderColor: "transparent", background: "transparent", justifyContent: "center", gap: "6px" });
export const form = style({ display: "flex", flexDirection: "column", gap: "12px" });
/** Email and password as one block: a grey ground, a hairline gap between, no outlines. */
export const fields = style({ display: "flex", flexDirection: "column", gap: "1px", borderRadius: "16px", overflow: "hidden" }); // own corner: the two fields as one block, as the console's sign-in had them
export const input = style({
  height: "44px", border: 0, padding: "0 18px", fontSize: vars.textInput, color: vars.text, outline: "none",
  background: `color-mix(in srgb, ${vars.text} 5%, transparent)`,
  selectors: { "&:hover, &:focus": { background: vars.hover } },
});
export const error = style({ textAlign: "left", paddingLeft: "18px", fontSize: vars.textMeta, color: vars.red });
