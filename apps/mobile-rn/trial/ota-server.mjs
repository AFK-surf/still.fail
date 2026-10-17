// A minimal expo-updates server (protocol 1) for the trial: serves the newest `expo export` in dist/ to runtime "1".
//   node ota-server.mjs <app dir> [port]
import { createHash, randomUUID } from "node:crypto";
import { readFileSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join } from "node:path";

const [dir, port = "8090"] = process.argv.slice(2);
const dist = join(dir, "dist");
const types = { ".png": "image/png", ".jpg": "image/jpeg", ".ttf": "font/ttf", ".otf": "font/otf", ".js": "application/javascript", ".hbc": "application/javascript" };
const hash = (b) => createHash("sha256").update(b).digest("base64url");
const md5 = (b) => createHash("md5").update(b).digest("hex");

// The app's public config (`expo config --type public`, written by the export script): expo-constants and expo-linking
// read it from the update's manifest, without it the new bundle throws at start.
const config = () => JSON.parse(readFileSync(join(dist, "expo-config.json"), "utf8"));

function manifest(platform, host) {
  const meta = JSON.parse(readFileSync(join(dist, "metadata.json"), "utf8")).fileMetadata[platform];
  const file = (path, ext, contentType) => {
    const b = readFileSync(join(dist, path));
    return { hash: hash(b), key: md5(b), fileExtension: `.${ext}`, contentType, url: `http://${host}/file/${path}` };
  };
  const built = statSync(join(dist, "metadata.json")).mtime.toISOString();
  const launchAsset = file(meta.bundle, "bundle", "application/javascript");
  // The same bundle is the same update: its id from its content, so a device on it is told there is nothing newer.
  const k = launchAsset.key;
  return {
    id: `${k.slice(0, 8)}-${k.slice(8, 12)}-4${k.slice(13, 16)}-8${k.slice(17, 20)}-${k.slice(20, 32)}`,
    createdAt: built,
    runtimeVersion: "1",
    launchAsset,
    assets: meta.assets.map((a) => file(a.path, a.ext, types[`.${a.ext}`] ?? "application/octet-stream")),
    metadata: {},
    extra: { expoClient: config() },
  };
}

createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  try {
    if (url.pathname === "/manifest") {
      const platform = req.headers["expo-platform"] ?? url.searchParams.get("platform") ?? "android";
      const current = req.headers["expo-current-update-id"];
      const m = manifest(platform, req.headers.host);
      const boundary = "b" + randomUUID().replace(/-/g, "");
      const body = [
        `--${boundary}\r\ncontent-disposition: form-data; name="manifest"\r\ncontent-type: application/json; charset=utf-8\r\n\r\n${JSON.stringify(m)}\r\n`,
        `--${boundary}\r\ncontent-disposition: form-data; name="extensions"\r\ncontent-type: application/json\r\n\r\n${JSON.stringify({ assetRequestHeaders: {} })}\r\n`,
        `--${boundary}--\r\n`,
      ].join("");
      console.log(new Date().toISOString(), "manifest", platform, "current", current ?? "-");
      res.writeHead(200, { "expo-protocol-version": "1", "expo-sfv-version": "0", "cache-control": "private, max-age=0", "content-type": `multipart/mixed; boundary=${boundary}` });
      res.end(body);
      return;
    }
    if (url.pathname.startsWith("/file/")) {
      const b = readFileSync(join(dist, url.pathname.slice(6)));
      console.log(new Date().toISOString(), "file", url.pathname, b.length);
      res.writeHead(200, { "content-type": types[extname(url.pathname)] ?? "application/octet-stream" });
      res.end(b);
      return;
    }
    res.writeHead(404).end();
  } catch (e) {
    console.log("error", e);
    res.writeHead(500).end(String(e));
  }
}).listen(Number(port), () => console.log("ota on", port));
