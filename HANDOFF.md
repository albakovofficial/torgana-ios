# Торгана для iPhone — передача в новый чат (9 ноября 2026)

## Что решено
- Отдельный репозиторий: `albakovofficial/torgana-ios` (владелец создаёт сам на GitHub; из чата создать нельзя).
- Подход: нативная оболочка на SwiftUI + WKWebView с сайтом torgana.ru и нативными функциями, которых нет у сайта в браузере
  (иначе Apple отклоняет «сайт в обёртке», правило 4.2): push через APNs, «Войти с Apple», системное «Поделиться»,
  виброотклик, Universal Links (ссылки torgana.ru открываются в приложении), экран «Нет соединения», обновление жестом.
- Сборка без Mac: GitHub Actions на `macos-26` (Xcode 26 — обязателен для App Store с апреля 2026), проект из `project.yml` (XcodeGen).
  Для выгрузки в TestFlight — ключ App Store Connect API в секретах GitHub (после активации аккаунта Apple Developer).
- Bundle ID: `ru.torgana.app`, имя «Торгана», только iPhone, iOS 16+, только светлая тема, портрет.

## Важно про Apple и Россию (проверено 9 ноября 2026)
- С 1 апреля 2026 Apple не принимает оплату в России: покупки в приложениях и подписки недоступны (кроме остатка на балансе Apple Account).
  Бесплатные приложения это не затрагивает (в статьях об этом прямо не сказано).
- Значит, в приложении — без покупок: тарифы и продвижение не продаём и не показываем кнопок оплаты/ссылок на оплату (правило 3.1.1/3.1.3);
  купленное на сайте работает и в приложении. Решение владельца ещё не получено — спросить.

## Что нужно сделать на сайте (репозиторий torgana, выпуск — только после «выпускай»)
1. Режим приложения: по метке `TorganaApp/x.y (iOS)` в User-Agent и классу `html.in-app` — прятать web-push, «установить на экран», оплату;
   «Поделиться» → `window.TorganaApp.post({type:'share', url, text})`.
2. Push через APNs: `lib/apns.js` (HTTP/2 + JWT ES256 из ключа .p8, без зависимостей), таблица токенов устройств,
   `POST /api/push/apns {token, env}`, отправка везде, где сейчас web-push (`alerts.notify`, `notifyAdmins`). Поле `url` в payload.
3. «Войти с Apple» (правило 4.8 — раз есть Яндекс ID и VK ID): `POST /api/auth/apple {identityToken, name, email}`,
   проверка подписи по ключам Apple (JWKS, RS256), aud = `ru.torgana.app`, nonce.
4. Блокировка пользователей (правило 1.2 для пользовательского контента): «Заблокировать» в чате и профиле — сообщения от него не приходят.
   Жалобы и модерация уже есть; удаление аккаунта самим пользователем уже есть (5.1.1(v)).
5. `/.well-known/apple-app-site-association` с `TEAMID.ru.torgana.app` (Team ID — после активации аккаунта).

## Что уже написано (этот архив)
- `project.yml`, `Torgana/Resources/Info.plist`, `Torgana.entitlements` (push, associated domains, Sign in with Apple).
- `Torgana/App/TorganaApp.swift` (Router: ссылки, push, torgana://), `AppDelegate.swift`, `RootView.swift` (заставка, «Нет соединения»).
- `Torgana/Web/WebController.swift` — WKWebView, мост `window.TorganaApp`, события `torgana-native`, правила переходов
  (свои страницы и вход Яндекс/VK — внутри, чужие — в Safari), обновление жестом, alert/confirm.
- Дописано 9 ноября 2026 (второй чат): `Native/Bridge.swift`, `Native/PushManager.swift`, `Native/AppleSignIn.swift`,
  иконка (временная) и Logo, цвета, `PrivacyInfo.xcprivacy`, `.github/workflows/ios.yml` (+ выгрузка в TestFlight),
  `ci/ExportOptions.plist`, `site/apple-app-site-association`, `BRIDGE.md`, `README.md`.
  Исправлено: ссылка из push при холодном запуске больше не перебивается главной; окна входа Яндекс/VK из target=_blank
  открываются внутри; `aps-environment` = development (Xcode сам меняет на production при выгрузке); пароли из «Связки ключей».
- Собиралось только в GitHub Actions — проверить первый запуск.

## Сделано 12 ноября 2026
- Сайт 1.56.0: режим приложения без оплаты, push через APNs (ключ — в «Модерация → Настройки → Приложение iPhone»),
  «Войти с Apple», файл Universal Links отдаёт сайт. Иконка — знак Торганы на фирменном градиенте.

## Дальше
1. Дописать недостающие файлы, отправить в `torgana-ios`, собрать на GitHub Actions (симулятор, без подписи) и исправить ошибки сборки.
2. Серверная часть (пункты выше) в репозитории torgana.
3. После активации Apple Developer: App ID, ключ APNs (.p8), ключ App Store Connect API, Team ID → секреты; сборка в TestFlight.
4. Карточка App Store: описание, скриншоты, политика конфиденциальности, «App Privacy», возрастной рейтинг, данные для проверяющего (тестовый вход).
