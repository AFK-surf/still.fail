// The admin's console as an app of its own, on its own host (admin.still.fail). Its origin gives it its own client core
// and so its own signed-in accounts: signing in here signs in nowhere else. It signs in on the web's sign-in pages
// (login/, no core: /auth/callback the web's, /login its own, signin.tsx), which hand the account to the console's core
// (pages/core.ts); the console (app.tsx) is loaded only past them.
import "../styles/index.ts";
import "@fontsource-variable/inter";
import { isSignIn, show } from "../login/page.tsx";
import { AdminSignIn } from "./signin.tsx";

const root = document.getElementById("app")!;
const path = location.pathname.replace(/\/+$/, "");
if (isSignIn(path)) show(root, path, <AdminSignIn />);
else void import("./app.tsx").then((m) => m.show(root));
