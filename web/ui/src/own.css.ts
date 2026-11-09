// What some parts keep of their own wherever they are put: a list's first one its width and room, the about mark its
// place beside its words, a column's edge its strip. In the cascade after the app's columns (web/src/styles/index.ts:
// last of the shared), whose rules for what is put straight in them (`${column} > *`) would otherwise size these too.
import { globalStyle } from "@vanilla-extract/css";
import {  } from "./styles/tokens.css.ts";
import { resizeHandle } from "./parts.css.ts";
globalStyle(resizeHandle, {
  position: "absolute", top: "0", bottom: "0", width: "7px", zIndex: "5", cursor: "col-resize", touchAction: "none",
});
