// `@stillfail/ui/<file>` (web/ui/package.json) to the package's source, for every build of the web (vite.*.config.ts):
// the builds read it where it is (the root package.json links it into node_modules, for Node and the types).
import { fileURLToPath } from "node:url";

export const uiAlias = { find: /^@stillfail\/ui\//, replacement: fileURLToPath(new URL("src/", import.meta.url)) };
