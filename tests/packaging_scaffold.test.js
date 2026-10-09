const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

function exists(relativePath) {
  assert.ok(fs.existsSync(path.join(root, relativePath)), `missing ${relativePath}`);
}

[
  'app/pubspec.yaml',
  'app/lib/app_version.dart',
  'app/lib/main.dart',
  'tools/build_android_apk.sh',
  'tools/build_linux_deb.sh',
  'docker/build-env/Dockerfile',
  'docker/linux-deb/Dockerfile',
  'docker-compose.yml',
  'tools/windows/Wallet-APS.iss',
  '.github/workflows/windows_setup.yml',
  '.github/workflows/release.yml',
  'tools/bump_version.js',
].forEach(exists);

const app = read('app/lib/main.dart');
[
  'Wallet APS',
  'Открыть кошелёк',
  'Создать кошелёк',
  'Банковская карта',
  'Номер карты',
  'CVV',
  'Пароль интернет-банка',
  'Icons.visibility',
  'DateTextInputFormatter',
  'Icons.calendar_month_outlined',
  'дд.мм.гггг',
  'Создать новую категорию',
  'Все пиктограммы',
  'syntheticSpbIconIdForUi',
  'categoryFolderIcon',
  'SpbGradientActionButton',
].forEach((needle) => assert.ok(app.includes(needle), `Flutter app missing ${needle}`));

assert.ok((app.match(/TemplateIcon\('/g) || []).length >= 100, 'Flutter app should expose at least 100 pictograms');

[
  'Открыть SPB Wallet',
  'Синхронизация',
  'Последняя синхронизация',
  'Конфликты',
  'Подключиться',
].forEach((needle) => assert.equal(app.includes(needle), false, `Flutter app should hide ${needle}`));

assert.match(app, /id:\s*'number'[\s\S]*label:\s*'Номер карты'[\s\S]*type:\s*'custom_secret'[\s\S]*required:\s*true/);
assert.match(app, /id:\s*'cvv'[\s\S]*label:\s*'CVV'[\s\S]*type:\s*'password'[\s\S]*secret:\s*true/);
assert.match(app, /id:\s*'account'[\s\S]*label:\s*'Номер счета'[\s\S]*type:\s*'custom_secret'[\s\S]*required:\s*true/);

const androidScript = read('tools/build_android_apk.sh');
assert.ok(androidScript.includes('BUILD_MODE="${BUILD_MODE:-debug}"'));
assert.ok(androidScript.includes('flutter build apk "--$BUILD_MODE"'));
assert.ok(androidScript.includes('Wallet-APS-android-$BUILD_MODE.apk'));
assert.ok(androidScript.includes('Wallet-APS-android.apk'));

const spbDatabase = read('app/lib/spb_wallet/spb_wallet_database.dart');
assert.ok(spbDatabase.includes('saveCategoryIcon'));
assert.ok(spbDatabase.includes('UPDATE spbwlt_Category SET IconID'));

const debScript = read('tools/build_linux_deb.sh');
assert.ok(debScript.includes('flutter build linux --release'));
assert.ok(debScript.includes('dpkg-deb --build'));
assert.ok(debScript.includes('wallet-aps_${VERSION}_${ARCH}.deb'));
assert.ok(debScript.includes('Wallet-APS-linux-amd64.deb'));

const installer = read('tools/windows/Wallet-APS.iss');
assert.ok(installer.includes('AppPublisherURL=https://github.com/lc200333-cmyk/Wallet-APS'));
assert.ok(installer.includes('UninstallFilesDir={app}\\Uninstall'));
assert.ok(installer.includes('UninstallDisplayIcon={uninstallexe}'));

const workflow = read('.github/workflows/windows_setup.yml');
assert.ok(workflow.includes('windows-latest'));
assert.ok(workflow.includes('flutter build windows --release'));
assert.ok(workflow.includes('Wallet-APS-Setup-*.exe'));

const releaseWorkflow = read('.github/workflows/release.yml');
[
  'name: Release',
  'contents: write',
  'node tools/bump_version.js',
  'docker compose build build-apk',
  'BUILD_MODE=release',
  'docker compose build build-deb',
  'Wallet-APS-Setup.exe',
  'Wallet-APS-android.apk',
  'Wallet-APS-linux-amd64.deb',
  'softprops/action-gh-release',
].forEach((needle) => assert.ok(releaseWorkflow.includes(needle), `release workflow missing ${needle}`));
assert.ok(releaseWorkflow.includes('app/lib/app_version.dart'));

const bumpVersion = read('tools/bump_version.js');
assert.ok(bumpVersion.includes("const dartVersionPath = 'app/lib/app_version.dart'"));
assert.match(read('app/lib/app_version.dart'), /currentAppVersion = '\d+\.\d+\.\d+'/);

const dockerfile = read('docker/build-env/Dockerfile');
[
  'FROM mirror.gcr.io/library/ubuntu:24.04',
  'ANDROID_HOME=/opt/android-sdk',
  'FLUTTER_HOME=/opt/flutter',
  'libgtk-3-dev',
  'ninja-build',
  'cmake',
  'openjdk-17-jdk',
  'nodejs',
  'npm',
  'sdkmanager',
  'platforms;android-36',
  'ndk;28.2.13676358',
  'flutter precache --linux --android',
].forEach((needle) => assert.ok(dockerfile.includes(needle), `Dockerfile missing ${needle}`));

const compose = read('docker-compose.yml');
[
  'version: "3.3"',
  'docker/build-env/Dockerfile',
  'docker/linux-deb/Dockerfile',
  './dist:/workspace/dist',
  'flutter-cache:',
  'flutter-linux-cache:',
  'gradle-cache:',
  'pub-cache:',
  'build-apk:',
  'build-deb:',
  'tools/build_android_apk.sh',
  'tools/build_linux_deb.sh',
].forEach((needle) => assert.ok(compose.includes(needle), `docker-compose missing ${needle}`));

const linuxDebDockerfile = read('docker/linux-deb/Dockerfile');
[
  'FROM mirror.gcr.io/library/ubuntu:20.04',
  'FLUTTER_HOME=/opt/flutter',
  'libgtk-3-dev',
  'libwebp-dev',
  'flutter precache --linux',
].forEach((needle) => assert.ok(linuxDebDockerfile.includes(needle), `Linux deb Dockerfile missing ${needle}`));

const pkg = JSON.parse(read('package.json'));
[
  'docker:build-image',
  'docker:test',
  'docker:apk',
  'docker:apk:fast',
  'docker:apk:release',
  'docker:deb',
  'docker:deb:fast',
  'docker:release',
  'version:bump',
].forEach((script) => assert.ok(pkg.scripts[script], `package script missing ${script}`));
assert.ok(pkg.scripts['docker:apk'].includes('docker-compose run --rm build-apk'));
assert.ok(pkg.scripts['docker:deb'].includes('docker-compose run --rm build-deb'));
assert.ok(pkg.scripts['docker:apk'].includes('docker-compose build build-apk'));
assert.ok(pkg.scripts['docker:deb'].includes('docker-compose build build-deb'));
assert.ok(pkg.scripts['docker:release'].includes('docker-compose run --rm -e BUILD_MODE=release build-apk'));
assert.ok(pkg.scripts['docker:release'].includes('docker-compose run --rm build-deb'));
assert.ok(pkg.scripts['docker:release'].includes('docker-compose build build-apk build-deb'));
assert.ok(pkg.scripts['docker:build-image'].includes('COMPOSE_HTTP_TIMEOUT=300'));
assert.ok(pkg.scripts['docker:test'].includes('COMPOSE_HTTP_TIMEOUT=300'));

console.log('packaging_scaffold.test.js: all tests passed');
