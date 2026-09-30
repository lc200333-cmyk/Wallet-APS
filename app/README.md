# Flutter App

Здесь лежит production-направление Flutter-приложения из `plans/01_stack_and_architecture.md`.

Текущая среда разработки может не иметь Flutter SDK, поэтому platform directories (`android/`, `linux/`, `windows/`) создаются сборочными скриптами через:

```bash
flutter create --platforms=linux,android,windows .
```

## Запуск

```bash
flutter pub get
flutter run -d linux
```

## Сборки

Из корня репозитория:

```bash
npm run build:apk
npm run build:deb
```

Windows `setup.exe` собирается через `.github/workflows/windows_setup.yml`.

Flutter UI уже содержит русские экраны, встроенные шаблоны, выбор пиктограмм, цветовые кружки и eye-кнопки для секретных полей.
