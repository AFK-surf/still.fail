// still.fail's web pages of their own, apart from the app (index.html, mbui's): each light, none loading the app.
// Signing in (/login, /auth/callback: login/, no core) and, on the core but not the app, Slack sending back an app a
// station made (/slack/installed), a service sending back a person who signed in to it for their vault (/vault/oauth)
// and a station's web service on a page of its own (/w/…/s/…/services/…). Any other
// page is the app's (cloud/src/web.ts WEB_PAGES).
import "./styles/global.css.ts";
import { nameTitle } from "./cloud/beta.tsx";
import { isSignIn, show } from "./login/page.tsx";

nameTitle();

const root = document.getElementById("app")!;
const path = location.pathname.replace(/\/+$/, "");
const service = /^\/w\/([^/]+)\/s\/([^/]+)\/services\/([^/]+)$/.exec(path);

if (isSignIn(path)) show(root, path);
else if (path === "/slack/installed") void import("./pages/slack.tsx").then((m) => m.show(root));
else if (path === "/vault/oauth") void import("./pages/vault-oauth.tsx").then((m) => m.show(root));
else if (service) void import("./pages/service.tsx").then((m) => m.show(root, `${decodeURIComponent(service[1]!)}/${decodeURIComponent(service[2]!)}`, decodeURIComponent(service[3]!)));
else location.replace("/");
