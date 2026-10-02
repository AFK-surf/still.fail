// chats.ts as one script for QuickJS: the catalog (every zh file of client/i18n, as the core has them) as CATALOG,
// then the code with its types stripped. node build.mjs <out.js>
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";

const here = new URL(".", import.meta.url).pathname;
const dir = `${here}../../../client/i18n/catalog/zh`;
const catalog = Object.assign({}, ...readdirSync(dir).filter((f) => f.endsWith(".json")).sort().map((f) => JSON.parse(readFileSync(`${dir}/${f}`, "utf8"))));
const code = stripTypeScriptTypes(readFileSync(`${here}chats.ts`, "utf8"));
writeFileSync(process.argv[2], `var CATALOG = ${JSON.stringify(catalog)};\n${code}`);
