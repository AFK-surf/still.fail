// still.fail's core in JavaScriptCore, no app's modules (scripts/core.sh bundle; an app's entry calls startJsc itself).
import { startJsc } from "./jsc-start.ts";

startJsc([]);
