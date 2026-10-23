// The same core answer for the web, Android and mbui renderer checks. Regenerate after changing the math protocol.
import { readFileSync, writeFileSync } from "node:fs";
import { markdown } from "../src/markdown.ts";

const text = String.raw`Inline \(E=mc^2\) stays with the words.

Fraction \(\frac{1}{2}\) and \(a+\text{你好}\) keep the baseline.

$$
\frac{-b\pm\sqrt{b^2-4ac}}{2a}
$$

$$
\begin{pmatrix}a&b\\c&d\end{pmatrix}
$$

$$
\sum_{k=1}^{n} x_k = x_1 + x_2 + x_3 + x_4 + x_5 + x_6 + x_7 + x_8 + x_9 + x_{10}
$$

Invalid \(\unknowncommand{x}\) stays readable. Code: \`$x$\`.
`.replaceAll("\\`", "`");
const content = JSON.stringify({ text, md: markdown(text) }, null, 2) + "\n";
// Native builds copy just the MoonBit module's sources into a platform-specific directory.
// Keep its test input inside those sources, checked against the same core answer.
const targets = ["../../fixtures/math.json", "../../../apps/mbui/src/sf/math.json"];
for (const path of targets) {
  const target = new URL(path, import.meta.url);
  if (process.argv.includes("--check")) {
    if (readFileSync(target, "utf8") !== content) throw new Error(`The math fixture at ${path} is stale; run scripts/math-fixture.ts`);
  } else writeFileSync(target, content);
}
console.log("Shared formula fixture matches the core");
