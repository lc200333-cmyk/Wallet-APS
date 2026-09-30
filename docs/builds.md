# Сборки Wallet APS

Эта инструкция нужна для сборки APK и deb без установки Flutter, Android SDK и Rust на хост. На машине должны быть только Docker, `docker-compose` v1 и npm.

## Что получится

Все артефакты складываются в папку `dist/` проекта:

```text
dist/Wallet-APS-android-debug.apk
dist/Wallet-APS-android-release.apk
dist/Wallet-APS-android.apk
dist/wallet-aps_0.1.0_amd64.deb
dist/Wallet-APS-linux-amd64.deb
```

Windows `setup.exe` собирается отдельно через GitHub Actions на Windows runner:

```text
Wallet-APS-Setup-0.1.0.exe
```

## Первый запуск

Из корня проекта:

```bash
npm run docker:build-image
```

Первая сборка образа тяжелая: Flutter, Android SDK, NDK, Rust и Chrome занимают несколько гигабайт и могут ставиться долго. Повторные сборки быстрее за счет Docker cache и named volumes.

Проверить проект внутри контейнера:

```bash
npm run docker:test
```

## Android APK

```bash
npm run docker:apk
```

Ожидаемый результат:

```text
dist/Wallet-APS-android-debug.apk
```

Это debug APK без release-подписи. Его можно ставить на устройство для тестирования.

## Linux deb

```bash
npm run docker:deb
```

Linux `.deb` по умолчанию собирается в Ubuntu 20.04 контейнере. Это сделано специально: бинарник получает более старую glibc и запускается на большем числе Debian/Ubuntu систем. Если собрать desktop-приложение на Ubuntu 24.04, на старой системе можно получить ошибку:

```text
GLIBC_2.34 not found
```

Команда `npm run docker:deb` перед сборкой приложения пересобирает Docker image `build-deb`, поэтому изменения в `docker/linux-deb/Dockerfile` подхватываются автоматически.

Ожидаемый результат:

```text
dist/wallet-aps_0.1.0_amd64.deb
```

Проверить метаданные пакета можно так:

```bash
dpkg -I dist/wallet-aps_0.1.0_amd64.deb
```

После этого переустанови пакет:

```bash
sudo apt install --reinstall ./dist/wallet-aps_0.1.0_amd64.deb
```

## APK и deb одной командой

```bash
npm run docker:release
```

Эта команда запускает Android release APK и Linux deb сборки подряд и складывает оба файла в `dist/`.

Быстрые повторные сборки после небольших изменений, без пересборки Docker image:

```bash
npm run docker:apk:fast
npm run docker:deb:fast
```

Release APK отдельно:

```bash
npm run docker:apk:release
```

## GitHub Releases

На каждый push в `master` workflow `.github/workflows/release.yml` автоматически:

1. поднимает patch-версию;
2. создает commit и tag `vX.Y.Z`;
3. собирает Windows setup, Android APK и Linux deb;
4. публикует файлы в GitHub Release.

Стабильные имена артефактов последнего релиза:

```text
Wallet-APS-Setup.exe
Wallet-APS-android.apk
Wallet-APS-linux-amd64.deb
```

## Как проверить на Linux

Без Android-устройства можно проверить три уровня.

### 1. Проверить файлы без установки

APK - это zip-контейнер. Быстрая проверка, что файл не битый:

```bash
file dist/Wallet-APS-android-debug.apk
unzip -t dist/Wallet-APS-android-debug.apk
```

deb-пакет:

```bash
file dist/wallet-aps_0.1.0_amd64.deb
dpkg -I dist/wallet-aps_0.1.0_amd64.deb
```

### 2. Проверить Linux-приложение

Сначала собери deb:

```bash
npm run docker:deb
```

Потом установи пакет:

```bash
sudo apt install ./dist/wallet-aps_0.1.0_amd64.deb
```

Запусти приложение из меню рабочего стола или командой:

```bash
wallet-aps
```

Удалить установленный пакет:

```bash
sudo apt remove wallet-aps
```

### 3. Проверить APK на Android Emulator

Самый простой вариант - поставить Android Studio и создать виртуальное устройство.

На Ubuntu/Debian обычно нужны KVM-пакеты:

```bash
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
sudo usermod -aG kvm,libvirt "$USER"
```

После этого перелогинься в систему, установи Android Studio, открой `Device Manager`, создай emulator с образом Android x86_64 и запусти его.

Если `adb` не найден, поставь platform-tools:

```bash
sudo apt install adb
```

Установка APK в запущенный emulator:

```bash
adb devices
adb install -r dist/Wallet-APS-android-debug.apk
```

Логи приложения:

```bash
adb logcat
```

Этот APK является debug-сборкой. Он подходит для теста установки и запуска, но не является release APK для публикации в магазине.

## Windows setup.exe

Flutter Windows desktop требует Windows SDK/MSVC, поэтому setup.exe не собирается в Linux Docker.

Путь сборки:

1. Открой GitHub Actions.
2. Запусти workflow `Windows setup`.
3. Дождись завершения job на `windows-latest`.
4. Скачай artifact:

```text
Wallet-APS-Setup-0.1.0.exe
```

Workflow лежит здесь:

```text
.github/workflows/windows_setup.yml
```

## Как устроен Docker

Файлы:

```text
docker/build-env/Dockerfile
docker-compose.yml
```

Контейнер монтирует проект в `/workspace`, а папку артефактов так:

```text
./dist:/workspace/dist
```

Кэши вынесены в named volumes:

```text
flutter-cache
pub-cache
gradle-cache
```

## Частые проблемы

Если Docker daemon не запущен:

```text
Couldn't connect to Docker daemon
```

Запусти Docker и повтори команду.

Если старый `docker-compose` пишет про HTTP timeout, в npm-скриптах уже стоит `COMPOSE_HTTP_TIMEOUT=300`. Если машина очень медленная, можно временно запустить так:

```bash
COMPOSE_HTTP_TIMEOUT=600 npm run docker:apk
```

Если не хватает места на диске, освободи место под Docker images и volumes. Образ большой, это нормально для Flutter + Android SDK + Rust.

Если сборка упала, пришли мне:

```bash
docker --version
docker-compose --version
npm run docker:test
ls -la dist
```

И последние 80-120 строк ошибки из команды, которая упала.
