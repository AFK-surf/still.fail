// The app's root: one root that draws the app (src/Main.tsx), its pages its own (src/App.tsx), not the router's. The
// core is started first, before anything renders. Loaded by require, so that a module failing as the app starts says
// where (its stack, which `npx metro-symbolicate` reads against the bundle's map), not only the router's "no layout".
import { useEffect, type ComponentType } from "react";

function load<T>(what: string, get: () => T): T {
  try {
    return get();
  } catch (e) {
    console.error(`stillfail: ${what} failed to load:`, (e as Error)?.stack ?? String(e));
    throw e;
  }
}

load("the core", () => require("../src/core"));
const { Main } = load("the app", () => require("../src/Main") as { Main: ComponentType });
const { checkOta } = load("updates", () => require("../src/ota") as { checkOta: () => void });

export default function Root() {
  useEffect(() => {
    checkOta();
  }, []);
  return <Main />;
}
