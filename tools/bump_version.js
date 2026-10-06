const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const bump = process.argv[2] || 'patch';

function file(relativePath) {
  return path.join(root, relativePath);
}

function read(relativePath) {
  return fs.readFileSync(file(relativePath), 'utf8');
}

function write(relativePath, content) {
  fs.writeFileSync(file(relativePath), content);
}

function nextVersion(current) {
  const match = current.match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!match) throw new Error(`Unsupported semver: ${current}`);
  const major = Number(match[1]);
  const minor = Number(match[2]);
  const patch = Number(match[3]);
  if (bump === 'major') return `${major + 1}.0.0`;
  if (bump === 'minor') return `${major}.${minor + 1}.0`;
  if (bump === 'patch') return `${major}.${minor}.${patch + 1}`;
  if (/^\d+\.\d+\.\d+$/.test(bump)) return bump;
  throw new Error(`Unsupported bump "${bump}". Use patch, minor, major, or x.y.z.`);
}

const packageJsonPath = 'package.json';
const packageJson = JSON.parse(read(packageJsonPath));
const version = nextVersion(packageJson.version);
packageJson.version = version;
write(packageJsonPath, `${JSON.stringify(packageJson, null, 2)}\n`);

const packageLockPath = 'package-lock.json';
if (fs.existsSync(file(packageLockPath))) {
  const lock = JSON.parse(read(packageLockPath));
  lock.version = version;
  if (lock.packages && lock.packages['']) {
    lock.packages[''].version = version;
  }
  write(packageLockPath, `${JSON.stringify(lock, null, 2)}\n`);
}

const pubspecPath = 'app/pubspec.yaml';
let pubspec = read(pubspecPath);
const pubspecVersion = pubspec.match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)/m);
const buildNumber = pubspecVersion ? Number(pubspecVersion[2]) + 1 : 1;
pubspec = pubspec.replace(/^version:\s*.+$/m, `version: ${version}+${buildNumber}`);
write(pubspecPath, pubspec);

const dartVersionPath = 'app/lib/app_version.dart';
write(
  dartVersionPath,
  read(dartVersionPath).replace(
    /^const currentAppVersion = '[^']+';/m,
    `const currentAppVersion = '${version}';`,
  ),
);

const issPath = 'tools/windows/Wallet-APS.iss';
write(
  issPath,
  read(issPath).replace(
    /^#define MyAppVersion "[^"]+"/m,
    `#define MyAppVersion "${version}"`,
  ),
);

const debScriptPath = 'tools/build_linux_deb.sh';
write(
  debScriptPath,
  read(debScriptPath).replace(/^VERSION="[^"]+"/m, `VERSION="${version}"`),
);

console.log(version);
