// Properties the browsers still.fail runs in have and csstype does not yet.
import "csstype";

declare module "csstype" {
  interface Properties {
    cornerShape?: string;
    WebkitUserDrag?: "auto" | "element" | "none";
  }
}
