// Over-the-air updates for the trial: on launch, ask the update server for a newer bundle; if there is one, fetch it
// and reload into it at once, logging each step's time so a run can be measured from logcat.
import * as Updates from "expo-updates";
import { BUNDLE } from "./version";

export async function checkOta() {
  console.log("OTA running", BUNDLE, Updates.updateId ?? "embedded", Date.now());
  if (__DEV__ || !Updates.isEnabled) return;
  try {
    const t0 = Date.now();
    const found = await Updates.checkForUpdateAsync();
    console.log("OTA checked", found.isAvailable, Date.now() - t0);
    if (!found.isAvailable) return;
    const t1 = Date.now();
    await Updates.fetchUpdateAsync();
    console.log("OTA fetched", Date.now() - t1);
    await Updates.reloadAsync();
  } catch (e) {
    console.log("OTA failed", String(e));
  }
}
