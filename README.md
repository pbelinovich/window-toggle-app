# Window Toggle

Небольшое приложение для macOS: выравнивает два окна активного приложения через значок в строке меню. Написано на Swift и использует AppKit / Accessibility, без внешних зависимостей.

- Левый клик: выровнять два окна. На одном экране — по половине доступной области; на нескольких — по окну на двух экранах.
- Правый клик: меню выравнивания, обмена местами, расширения окон и разрешений.
- Повторное выравнивание сохраняет расположение после обмена местами.
- Расширение занимает доступную область экрана без системного Full Screen.

Нужны два обычных несвёрнутых окна. Если окон больше, выбираются первые два в порядке Accessibility. Горячих клавиш нет; некоторые приложения ограничивают размеры окон.

## Сборка

Требуются macOS и Xcode Command Line Tools (`xcode-select --install`).

```sh
./scripts/build.sh
"build/Window Toggle.app/Contents/MacOS/WindowToggle" --self-test
open "build/Window Toggle.app"
```

Сборка создаёт локально подписанное приложение в `build/Window Toggle.app`. Подпись ad hoc предназначена для локального использования; приложение не нотарифицировано.

## Установка

Закройте уже запущенный Window Toggle перед заменой приложения.

```sh
mkdir -p "$HOME/Applications"
ditto "build/Window Toggle.app" "$HOME/Applications/Window Toggle.app"
open "$HOME/Applications/Window Toggle.app"
```

Разрешите управление окнами в **System Settings → Privacy & Security → Accessibility → Window Toggle**. Если приложения нет в списке, добавьте `~/Applications/Window Toggle.app` через кнопку `+`.

Для автозапуска добавьте установленное приложение в **System Settings → General → Login Items**. Если автозапуск уже настроен через `local.windowtoggle` в LaunchAgents, повторно добавлять его не нужно.

При пересборке сохраняйте `CFBundleIdentifier` и designated requirement `local.windowtoggle`; скрипт сборки уже задаёт их.

## Проверка

```sh
"build/Window Toggle.app/Contents/MacOS/WindowToggle" --self-test
"build/Window Toggle.app/Contents/MacOS/WindowToggle" --diagnose
"build/Window Toggle.app/Contents/MacOS/WindowToggle" --integration-test
```

`--self-test` проверяет геометрию без управления окнами. `--diagnose` показывает разрешения, экраны и окна активного приложения. `--integration-test` требует Accessibility и создаёт два тестовых окна для проверки выравнивания, обмена и расширения.

## Исходники

- `main.swift` — текущая версия приложения.
- `Info.plist` — метаданные приложения.
- `scripts/build.sh` — сборка и локальная подпись.
- `archive/` — первоначальная версия для Warp и оригинальная инструкция, сохранённые для истории.
