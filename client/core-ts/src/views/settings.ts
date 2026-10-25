// What the settings say of the workspace as a whole (the `settings` view), over its stations as the `stations` view
// has them: how many have the automatic decisions' completion rule on, in words for its row (自动决策); and what the
// stations' archive reviews mean for the hint 按模型判断 (设置 › 归档).
import { t } from "../i18n.ts";
import { archiveReview } from "../present.ts";

type J = any;

/// `stations`: the `stations` view's items (each with its decorated overview).
export function settingsView(stations: J[]): J {
  const decisionsOn = stations.filter((s) => s?.overview?.automaticDecisions?.settings?.completion?.enabled === true).length;
  return {
    decisionsOn,
    decisionsText: decisionsOn > 0 ? t("core-views.settings.decisions.on", { n: decisionsOn }) : t("core-views.settings.decisions.off"),
    ...hintReview(stations),
  };
}

/// 按模型判断 goes by the stations' archive reviews: none on, it can suggest nothing (`hintNoReview`: not to be chosen);
/// some on, the others' chats are never suggested (`hintReviewText` says whose). Nothing said while no station is
/// known (online, its overview read), or every one known has its review on.
function hintReview(stations: J[]): J {
  const known = stations.filter((s) => s?.online === true && s?.overview !== null && typeof s?.overview === "object");
  const on = known.filter((s) => archiveReview(s.overview.automaticDecisions).on).map((s) => String(s.name));
  const off = known.filter((s) => !archiveReview(s.overview.automaticDecisions).on).map((s) => String(s.name));
  if (known.length === 0 || off.length === 0) return { hintNoReview: false, hintReviewText: "" };
  if (on.length === 0) return { hintNoReview: true, hintReviewText: t("web-pages.archiving.hintNoReview") };
  return { hintNoReview: false, hintReviewText: t("web-pages.archiving.hintSomeReview", { on: on.join("、"), off: off.join("、") }) };
}
