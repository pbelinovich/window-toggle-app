Window Toggle

Левый клик по значку: выровнять два окна активного приложения.
Один экран: слева и справа по половине доступной области.
Два и более экранов: по одному окну на двух экранах во всю доступную область.
Повторный клик только выравнивает; отката к исходной раскладке нет.
После обмена местами выравнивание сохраняет текущее расположение окон.

Правый клик — меню:
• Выровнять два окна.
• Поменять окна местами — обмен текущими положениями и размерами.
• Расширить окна — на двух мониторах по одному окну на весь доступный экран;
  на одном мониторе оба окна занимают доступную область, друг за другом.
• Разрешение на управление окнами.
• Завершить.

Операции меняют обычные размеры окон, без перехода в системный Full Screen.
Нужны два несвёрнутых окна активного приложения; приложение должно поддерживать Accessibility.
Если окон больше двух, выбираются первые два в порядке Accessibility.
Размер значка: 14×14. Горячих клавиш нет. Автозапуск включён.

Разрешение: System Settings → Privacy & Security → Accessibility → Window Toggle.
Если приложения нет: + → Cmd+Shift+G → ~/Applications/Window Toggle.app → Open → включить.
Приложение: ~/Applications/Window Toggle.app
Исходник: ~/Library/Application Support/Window Toggle/main.swift
Автозапуск: ~/Library/LaunchAgents/local.windowtoggle.plist
Отключение автозапуска: launchctl bootout gui/$(id -u)/local.windowtoggle

При пересборке сохранять CFBundleIdentifier local.windowtoggle и явное designated requirement.
Команда подписи: codesign --force --sign - --identifier local.windowtoggle --requirements '=designated => identifier "local.windowtoggle"' "$HOME/Applications/Window Toggle.app"
