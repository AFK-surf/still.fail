// The app's root: one root that draws the app (src/Main.tsx), its pages its own (src/App.tsx), not the router's. The
// core is started first, before anything renders.
import "../src/core";
import { useEffect } from "react";
import { Main } from "../src/Main";
import { checkOta } from "../src/ota";

export default function Root() {
  useEffect(() => {
    checkOta();
  }, []);
  return <Main />;
}
