// Whether a Windows station runs as the machine's administrator (its elevation/elevation.ts), as the station's page
// shows it: the overview's `elevation` put in words. The switch where it stands (where a change under way goes), what it
// means or how the change goes, how the last one failed, and whether the viewer may switch it. A station that says
// none (not Windows, or from before it) has none: the page shows nothing.
import { t } from "./i18n.ts";
import { isObject } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const FAILURES = ["declined", "unanswered", "notStarted", "error"];

/// The overview's `elevation` (`{on, elevated, canElevate, step?, want?, failed?, message?, manage}`) as the page shows
/// it; undefined when the station said none.
export function elevationShown(v: unknown): J | undefined {
  if (!isObject(v) || typeof v.on !== "boolean") return undefined;
  const step = typeof v.step === "string" ? v.step : null;
  const elevated = v.elevated === true;
  const canElevate = v.canElevate === true;
  const line =
    step === "asking"
      ? t("core-views.elevation.asking")
      : step === "applying"
        ? t("core-views.elevation.applying")
        : step === "restarting"
          ? t("core-views.elevation.restarting")
          : !canElevate
            ? t("core-views.elevation.notAdmin")
            : v.on && !elevated
              ? t("core-views.elevation.notYet")
              : !v.on && elevated
                ? t("core-views.elevation.elevatedApart")
                : t("core-views.elevation.line");
  const failure = step === null && typeof v.failed === "string" && FAILURES.includes(v.failed) ? v.failed : null;
  const failed =
    failure === null
      ? undefined
      : failure === "error" && typeof v.message === "string" && v.message !== ""
        ? t("core-views.elevation.failed.errorWhy", { why: v.message })
        : t(`core-views.elevation.failed.${failure}`);
  return {
    on: step !== null && typeof v.want === "boolean" ? v.want : v.on,
    busy: step !== null,
    line,
    ...(failed !== undefined ? { failed } : {}),
    canChange: v.manage === true && canElevate && step === null,
  };
}
