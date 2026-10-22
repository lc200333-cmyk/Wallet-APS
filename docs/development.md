# Development

Use [architecture](architecture.md) for code ownership and
[testing](testing.md) for checks. End-user instructions remain in the root
README and `docs/user-guide/`; Docker packaging details remain in [builds](builds.md).

## Baseline and setup

1. Inspect `git status --short`, `git branch -av` and `git log -5 --oneline`.
   Do not mix the old local HEAD, cached remote and unsaved user work.
2. Use Flutter **3.44.7 / Dart 3.12.2**, matching the locally verified SDK and
   new CI pin. The manifest's Dart lower bound is not proof older SDKs compile.
3. Install Node 22 for packaging checks; there are no npm runtime dependencies
   in the current package manifest. Use `npm ci` if dependencies are later added.
4. In `app/`, run `flutter pub get --enforce-lockfile`. Do not run pub upgrade.
   Review any generated changes; do not stage them automatically.
5. Run `flutter doctor -v` and install the platform prerequisites it reports.

Windows requires Visual Studio C++ desktop tools, Windows SDK and CMake.
Android uses Java 17, SDK platform 36 and the Flutter-selected NDK (existing
Docker provisions 28.2.13676358); inspect Gradle files before changing tools.
Linux requires clang, cmake, ninja, pkg-config, GTK 3, lzma and native SQLite.
The existing Linux packaging image targets Ubuntu 20.04 for glibc compatibility.

From `app/`:

```sh
flutter run -d windows
flutter run -d linux
flutter devices
flutter run -d <android-device-id>
flutter build windows --release --no-pub
flutter build linux --release --no-pub
flutter build apk --debug --no-pub
```

Use only the target supported by your host. CI build artifacts are validation
outputs, not approved releases. Android release currently uses debug signing.
Never install or overwrite a user's vault to perform a smoke test.

Existing `npm run docker:*` scripts use POSIX shell syntax and docker-compose
v1; run them in a suitable Linux shell. Existing GitHub release jobs use Compose
v2. Do not run `flutter create .`, branding generation or version bump scripts as
routine setup: they can rewrite tracked native sources/assets/version files.

If SDK cache access is denied, use an authorized writable SDK/cache or request
the required tool access; do not label the failure as a code defect. Sync conflict
copies under `lib/` can be analyzed as source; resolve them with their owner,
not by adding blanket analyzer exclusions.
