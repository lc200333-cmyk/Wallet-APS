const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const fingerprint = read('tools/design_android_certificate.sha256').trim();
assert.match(fingerprint, /^[a-f0-9]{64}$/);
const gradle = read('app/android/app/build.gradle.kts');
assert.ok(gradle.includes('signingConfigs.getByName("designRelease")'));
assert.ok(!gradle.includes('signingConfigs.getByName("debug")'));
assert.ok(gradle.includes('!hasDesignSigning'));
assert.ok(gradle.includes('debug fallback is forbidden'));
assert.ok(gradle.includes('keyAlias = "wallet-aps-design"'));

const workflow = read('.github/workflows/release.yml');
assert.ok(workflow.includes('secrets.DESIGN_ANDROID_KEYSTORE_BASE64'));
assert.ok(workflow.includes('secrets.DESIGN_ANDROID_KEYSTORE_PASSWORD'));
assert.ok(workflow.includes('--volume "$DESIGN_SIGNING_DIR:/run/design-signing:ro"'));
assert.ok(workflow.includes('-e DESIGN_ANDROID_KEYSTORE_PASSWORD build-apk'));
assert.ok(!workflow.includes('-e DESIGN_ANDROID_KEYSTORE_PASSWORD='));
assert.ok(workflow.indexOf('docker compose build build-apk') <
  workflow.indexOf('base64 --decode > "$DESIGN_SIGNING_DIR/keystore.p12"'));
assert.ok(workflow.includes('trap \'rm -f -- "$DESIGN_SIGNING_DIR/keystore.p12"; rmdir'));
assert.ok(!read('.github/workflows/ci.yml').includes('secrets.DESIGN_ANDROID_'));
for (const excluded of ['.codex', '**/*.p12', '**/*.dpapi']) {
  assert.ok(read('.dockerignore').split(/\r?\n/).includes(excluded));
}
const builder = read('tools/build_android_apk.sh');
assert.ok(builder.indexOf('Design release requires its persistent signing key') <
  builder.indexOf('flutter pub get'));
assert.ok(builder.indexOf('verify_design_apk.sh') < builder.indexOf('cp "$APP_DIR/build/'));

// These are shell contract tests with a mock verifier, NOT real APK verification.
const bash = process.platform === 'win32'
  ? path.join(process.env.ProgramFiles || 'C:/Program Files', 'Git/bin/bash.exe')
  : 'bash';
const posix = (value) => process.platform === 'win32'
  ? path.resolve(value).replace(/\\/g, '/').replace(/^([A-Za-z]):/, (_, c) => `/${c.toLowerCase()}`)
  : value;
const prefix = path.join(os.tmpdir(), 'wallet-aps-design-signing-test-');
const temporary = fs.mkdtempSync(prefix);
try {
  const sdk = path.join(temporary, 'sdk');
  const verifier = path.join(sdk, 'build-tools/36.0.0/apksigner');
  fs.mkdirSync(path.dirname(verifier), { recursive: true });
  const apk = path.join(temporary, 'synthetic.apk');
  fs.writeFileSync(apk, 'synthetic test input, not a real APK');
  const runVerifier = (report, exit = 0, sdkPath = posix(sdk)) => {
    fs.writeFileSync(verifier, `#!/usr/bin/env bash\nprintf '%s\\n' '${report}'\nexit ${exit}\n`);
    fs.chmodSync(verifier, 0o700);
    return spawnSync(bash, [posix(path.join(root, 'tools/verify_design_apk.sh')), posix(apk)], {
      encoding: 'utf8', env: { ...process.env, ANDROID_HOME: sdkPath },
    });
  };
  const good = `Signer #1 certificate SHA-256 digest: ${fingerprint.toUpperCase()}`;
  const accepted = runVerifier(good);
  assert.equal(accepted.status, 0, accepted.stderr || String(accepted.error));
  assert.ok(accepted.stdout.includes('Verified persistent Design signing certificate'));
  assert.notEqual(runVerifier(`Signer #1 certificate SHA-256 digest: ${'0'.repeat(64)}`).status, 0);
  assert.notEqual(runVerifier(`${good}\nSigner #2 certificate SHA-256 digest: ${fingerprint}`).status, 0);
  assert.notEqual(runVerifier(good, 7).status, 0, 'Invalid APK must not pass even with the expected cert text');
  assert.notEqual(runVerifier('', 0).status, 0, 'Missing signer must fail');
  assert.notEqual(runVerifier(good, 0, '').status, 0, 'Missing SDK must fail');

  for (const credentials of [
    { DESIGN_ANDROID_KEYSTORE_PATH: '', DESIGN_ANDROID_KEYSTORE_PASSWORD: '' },
    { DESIGN_ANDROID_KEYSTORE_PATH: posix(path.join(temporary, 'missing.p12')), DESIGN_ANDROID_KEYSTORE_PASSWORD: 'synthetic-test-password' },
  ]) {
    const result = spawnSync(bash, [posix(path.join(root, 'tools/build_android_apk.sh'))], {
      encoding: 'utf8', env: { ...process.env, BUILD_MODE: 'release', ...credentials },
    });
    assert.notEqual(result.status, 0, 'Release must fail before building without its keystore');
    assert.ok(!`${result.stdout}${result.stderr}`.includes('synthetic-test-password'));
  }
} finally {
  const target = path.resolve(temporary);
  assert.equal(path.dirname(target), path.resolve(os.tmpdir()));
  assert.ok(target.startsWith(path.resolve(prefix)));
  fs.rmSync(target, { recursive: true, force: true });
}
console.log('design_android_signing.test.js: static and mock shell contract tests passed');
