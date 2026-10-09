// Entry point that makes `node --test tools/icons/test/` work. Node's test runner treats a directory argument as a
// module path (CommonJS directory resolution finds this index.js), so this file imports every *.test.mjs here; their
// node:test cases report through the runner as usual. `node --test tools/icons/test/*.test.mjs` also works.
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

(async () => {
  for (const f of fs.readdirSync(__dirname).filter((x) => x.endsWith('.test.mjs')).sort()) {
    await import(pathToFileURL(path.join(__dirname, f)).href);
  }
})();
