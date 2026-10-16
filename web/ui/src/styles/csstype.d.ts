// Properties the browsers ember runs in have and csstype (what *.css.ts styles are checked against) does not yet.
import "csstype";

declare module "csstype" {
  interface Properties {
    cornerShape?: string;
    WebkitAppRegion?: "drag" | "no-drag";
    WebkitUserDrag?: "auto" | "element" | "none";
  }
}
