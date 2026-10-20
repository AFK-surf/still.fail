// What some parts keep of their own wherever they are put: a list's first one its width and room, the about mark its
// place beside its words, a column's edge its strip. In the cascade after the app's columns (web/src/styles/index.ts:
// last of the shared), whose rules for what is put straight in them (`${column} > *`) would otherwise size these too.
import { globalStyle } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { about, firstOne, resizeHandle } from "./parts.css.ts";

/** A list's first one to make (FirstOne): a scene, a title, a line, what to do. */
globalStyle(firstOne, {
  display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center", gap: "8px", margin: "24px auto",
  padding: "8px 0 24px", maxWidth: "480px",
});
/** A quiet mark that says what a thing is on hover (About), in place of a paragraph. */
globalStyle(about, {
  display: "inline-flex", alignItems: "center", justifyContent: "center", width: "20px", height: "20px",
  marginLeft: "6px", padding: "0", border: "0", borderRadius: "999px", background: "none", color: vars.subtle,
  verticalAlign: "middle", cursor: "help", transition: `color ${vars.dur} ${vars.easeOut}`,
});
globalStyle(resizeHandle, {
  position: "absolute", top: "0", bottom: "0", width: "7px", zIndex: "5", cursor: "col-resize", touchAction: "none",
});
