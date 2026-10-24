export PATH=/opt/homebrew/bin:$PATH
node client/core-ts/scripts/shapes.ts; echo "shapes: $?"
(node_modules/.bin/tsgo -p web/tsconfig.json 2>&1 | head -5; echo "web tsgo done")
