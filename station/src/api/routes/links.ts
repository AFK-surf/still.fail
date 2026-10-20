// GET /link-preview?url=: what a web link in a message is, for its preview card (src/links/preview.ts): `{kind: "none"}`
// when there is nothing to show of it.
import { type Request, error, json, param } from "../request.ts";
import type { Route } from "../admin.ts";
import { linkPreview } from "../../links/preview.ts";

export const routes = (): Route[] => [
  {
    method: "GET",
    pattern: /^\/link-preview$/,
    handle: async (r: Request) => {
      const url = param(r, "url") ?? "";
      if (!/^https?:\/\//i.test(url) || url.length > 4096) return error(400, "an http(s) url is required");
      return json(200, JSON.stringify((await linkPreview(url)) ?? { kind: "none" }));
    },
  },
];
