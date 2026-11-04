// Passes only if node-ci ran setup-command and exported test-env.
const fs = require('node:fs');
const assert = require('node:assert');

assert.strictEqual(process.env.FIXTURE_FLAG, 'a=b c', 'test-env FIXTURE_FLAG was not exported intact');
assert.ok(fs.existsSync('.setup-done'), 'setup-command did not run before the tests');
assert.strictEqual(process.env.GITHUB_PATH_EVIL, undefined, 'unexpected variable present');
console.log('node-app tests passed');
