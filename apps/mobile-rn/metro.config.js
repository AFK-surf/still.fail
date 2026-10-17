// The app takes the UI's logic from still.fail's web app as it is (web/src: the core's client, its React hooks, the
// prefs, the doing list; web/ui/src: the words) and puts its own in place of the few modules that are the browser's
// (src/shims): one copy of that logic for the web, the phone web and this app.
const { getDefaultConfig } = require("expo/metro-config");
const path = require("path");

const app = __dirname;
const root = path.resolve(app, "../..");
const config = getDefaultConfig(app);

config.watchFolders = [path.join(root, "web/src"), path.join(root, "web/ui/src"), path.join(root, "client/i18n"), path.join(root, "client/core-ts/src"), path.join(root, "design")];

const shims = {
  [path.join(root, "web/src/channel.ts")]: "channel.ts",
  [path.join(root, "web/src/core/built.ts")]: "built.ts",
  [path.join(root, "web/src/telemetry.ts")]: "telemetry.ts",
  [path.join(root, "web/src/i18n.ts")]: "../i18n.ts",
  [path.join(root, "web/src/core/worker.ts")]: "worker.ts",
};
const ui = "@stillfail/ui/";

const inApp = (file) => file.startsWith(app + path.sep);
const bare = (name) => !name.startsWith(".") && !path.isAbsolute(name);

config.resolver.resolveRequest = (context, name, platform) => {
  if (name.startsWith(ui)) return { type: "sourceFile", filePath: path.join(root, "web/ui/src", name.slice(ui.length)) };
  // A package asked for from a file outside the app is the app's own (one React), not one beside that file.
  const from = bare(name) && !inApp(context.originModulePath) ? { ...context, originModulePath: path.join(app, "index.ts") } : context;
  const found = from.resolveRequest(from, name, platform);
  const shim = found.type === "sourceFile" ? shims[found.filePath] : undefined;
  return shim ? { type: "sourceFile", filePath: path.join(app, "src/shims", shim) } : found;
};

module.exports = config;
