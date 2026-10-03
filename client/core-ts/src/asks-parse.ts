// The asks' calls by name (asks.rs `parse`): a link's target, a newer app, a picture, the buddies, a dev sign-in.
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { get } from "./util.ts";

export type Ask =
  | { kind: "linkParse"; url: string }
  | { kind: "appUpdate"; platform: string; version: number; now: boolean }
  | { kind: "picture"; url: string }
  | { kind: "buddies" }
  | { kind: "devSignIn"; user: string };

/// The ask `name` names, with its params; null when it is none of these. Throws when its params are wrong.
export function parseAsk(name: string, params: unknown): Ask | null {
  const text = (field: string) => {
    const v = get(params, field);
    if (typeof v !== "string" || v === "") throw CoreError.invalid(t("core-misc.params.missing", { field }));
    return v;
  };
  switch (name) {
    case "link.parse":
      return { kind: "linkParse", url: text("url") };
    case "app.update": {
      const platform = text("platform");
      const version = get(params, "versionCode");
      if (typeof version !== "number" || !Number.isInteger(version)) throw CoreError.invalid(t("core-misc.params.missing", { field: "versionCode" }));
      return { kind: "appUpdate", platform, version, now: get(params, "now") === true };
    }
    case "picture":
      return { kind: "picture", url: text("url") };
    case "buddies":
      return { kind: "buddies" };
    case "dev.signIn":
      return { kind: "devSignIn", user: text("user") };
    default:
      return null;
  }
}
