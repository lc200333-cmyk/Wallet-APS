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
const installer = read('tools/windows/Wallet-APS.iss');
assert.ok(installer.includes('#define MyAppName "Wallet APS Design"'));
assert.ok(installer.includes('AppId={{A48D2FEA-EA47-49EF-A311-60C3761EA817}'));
assert.ok(!installer.includes('94F89A42-1716-4D1F-8752-A3A3F89B1123'));
const runner = read('app/windows/runner/main.cpp');
assert.ok(runner.includes('L"WalletAPSDesign.swl"'));
assert.ok(!runner.includes('classes + L".swl", nullptr'));
assert.ok(read('app/android/app/build.gradle.kts').includes(
  'applicationId = "com.lc200333cmyk.walletaps.design"'));
assert.ok(read('app/linux/CMakeLists.txt').includes(
  'set(APPLICATION_ID "com.lc200333cmyk.walletaps.design")'));
const deb = read('tools/build_linux_deb.sh');
for (const text of ['Package: wallet-aps-design', '/opt/WalletAPSDesign/',
  'applications/wallet-aps-design.desktop', '/usr/bin/wallet-aps-design']) {
  assert.ok(deb.includes(text), `Linux install isolation missing ${text}`);
}
const app = read('app/lib/main.dart');
assert.ok(!app.includes('/Wallet-APS/releases'));
assert.ok(app.includes('designSupportDirectory(await getApplicationSupportDirectory())'));
assert.ok(read('app/lib/design_distribution.dart').includes(
  'https://github.com/lc200333-cmyk/Wallet-APS-Design/releases'));
console.log('design_repository_isolation.test.js: all tests passed');
