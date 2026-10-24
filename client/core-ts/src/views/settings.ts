// What the settings say of the workspace as a whole (the `settings` view), over its stations as the `stations` view
// has them: how many have the automatic decisions' completion rule on, in words for its row (自动决策).
import { t } from "../i18n.ts";

type J = any;

/// `stations`: the `stations` view's items (each with its decorated overview).
export function settingsView(stations: J[]): J {
  const decisionsOn = stations.filter((s) => s?.overview?.automaticDecisions?.settings?.completion?.enabled === true).length;
  return {
    decisionsOn,
    decisionsText: decisionsOn > 0 ? t("core-views.settings.decisions.on", { n: decisionsOn }) : t("core-views.settings.decisions.off"),
  };
}
