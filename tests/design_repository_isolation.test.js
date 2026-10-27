const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repository = 'lc200333-cmyk/Wallet-APS-Design';
const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
if (process.env.GITHUB_REPOSITORY) {
  assert.equal(process.env.GITHUB_REPOSITORY, repository,
    'Experimental workflows must never run in the main repository');
}
for (const file of ['ci.yml', 'release.yml', 'windows_setup.yml', 'release_cleanup.yml']) {
  const text = read(`.github/workflows/${file}`);
  const jobText = text.split(/^jobs:\r?$/m)[1];
  assert.ok(jobText, `${file}: missing jobs`);
  const blocks = jobText.split(/^  ([a-z][a-z0-9-]*):\r?$/m);
  assert.ok(blocks.length >= 3, `${file}: no jobs checked`);
  for (let i = 1; i < blocks.length; i += 2) {
    assert.ok(blocks[i + 1].includes(`if: github.repository == '${repository}'`),
      `${file}/${blocks[i]} must be restricted to the design repository`);
  }
  assert.ok(!text.includes('repository: lc200333-cmyk/Wallet-APS\n'));
}
for (const file of ['release.yml', 'release_cleanup.yml']) {
  const text = read(`.github/workflows/${file}`);
  assert.ok(text.includes('GH_REPO: ${{ github.repository }}'));
  assert.ok(text.includes('GH_TOKEN: ${{ github.token }}'));
  assert.ok(!text.includes('secrets.PAT'));
}
assert.ok(read('AGENTS.md').includes('Non-negotiable repository boundary'));
console.log('design_repository_isolation.test.js: all tests passed');
