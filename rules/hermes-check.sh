#!/bin/sh
# The rules' JS bundled as the core is for Hermes (esbuild, then Babel's class transform: client/core-ts/scripts/
# hermes-bundle.ts) and run in Hermes: what it prints, then what Node prints of the same, to compare.
set -e
cd "$(dirname "$0")/../client/core-ts"
out=../../rules/_build/hermes-check.js
npx esbuild ../../rules/hermes-check.mjs --bundle --format=iife --outfile=$out --log-level=warning
node -e "const b=require('@babel/core');const fs=require('fs');fs.writeFileSync(process.argv[1],b.transformSync(fs.readFileSync(process.argv[1],'utf8'),{babelrc:false,configFile:false,compact:true,plugins:['@babel/plugin-transform-classes']}).code)" $out
echo "== hermes"; "${HERMES:-hermes}" $out
echo "== node"; node -e "globalThis.print=console.log; require(process.argv[1])" $PWD/$out
