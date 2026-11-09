# Торгана для iPhone

Приложение площадки объявлений [torgana.ru](https://torgana.ru) для App Store.
SwiftUI + WKWebView: сайт внутри приложения плюс то, чего у сайта в браузере нет, — push-уведомления Apple,
«Войти с Apple», системное «Поделиться», виброотклик, значок с числом непрочитанных, ссылки torgana.ru
сразу в приложении, пароли из «Связки ключей», экран «Нет соединения», обновление жестом.

- Bundle ID: `ru.torgana.app`, название «Торгана», iPhone, iOS 16+, светлая тема, портрет.
- Mac не нужен: проект собирается на GitHub Actions (`macos-26`, Xcode 26 — с 28 апреля 2026 App Store принимает только сборки Xcode 26 / iOS 26 SDK).
- Файла `.xcodeproj` в репозитории нет — его создаёт [XcodeGen](https://github.com/yonaskolb/XcodeGen) из `project.yml`.

## Устройство

```
project.yml                     описание проекта (XcodeGen)
Torgana/App/                    точка входа, Router (ссылки, push, torgana://), экраны заставки и «Нет соединения»
Torgana/Web/WebController.swift WKWebView, правила переходов, мост window.TorganaApp
Torgana/Native/                 Bridge (команды сайта), PushManager (APNs), AppleSignIn, Haptics
Torgana/Resources/              Info.plist, entitlements, PrivacyInfo.xcprivacy, иконка и цвета
ci/ExportOptions.plist          настройки выгрузки в App Store Connect
.github/workflows/ios.yml       сборка и выгрузка в TestFlight
site/apple-app-site-association файл для сайта (Universal Links)
BRIDGE.md                       что должен уметь сайт: команды, события, проверки на сервере
```

## Сборка

- **Каждый push в `main`** — проверочная сборка под симулятор (без подписи). Ошибки — во вкладке Actions.
- **Выпуск в TestFlight** — тег `V1.0.1` (номер версии берётся из тега) или Actions → iOS → Run workflow → галочка «TestFlight».
  Номер сборки = номер запуска, растёт сам.

На Mac (если появится): `brew install xcodegen && xcodegen generate && open Torgana.xcodeproj`.

## Что сделать в Apple (после активации Apple Developer)

1. **Team ID** — developer.apple.com → Membership details. Вписать в `site/apple-app-site-association` вместо `TEAMID`.
2. **Ключ App Store Connect API** — appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API →
   Team Keys → «+», роль **Admin** (нужна, чтобы сборка сама создавала сертификаты и профили). Скачать `.p8` (даётся один раз),
   записать Key ID и Issuer ID.
3. **Секреты GitHub** — репозиторий → Settings → Secrets and variables → Actions:
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (весь текст файла `.p8`).
4. **Карточка приложения** — App Store Connect → Apps → «+» → New App: iOS, название «Торгана», язык русский,
   Bundle ID `ru.torgana.app` (если его нет в списке — сначала запустить выпуск в TestFlight, сборка создаст App ID сама,
   или создать вручную в Certificates, Identifiers & Profiles с Push Notifications, Sign in with Apple, Associated Domains).
5. **Ключ APNs для сервера** — Certificates, Identifiers & Profiles → Keys → «+» → Apple Push Notifications service.
   `.p8`, Key ID и Team ID — на сервер сайта (не в этот репозиторий).

## Что сделать на сайте

Подробно — в [BRIDGE.md](BRIDGE.md). Коротко:

1. Режим приложения по `html.in-app`: спрятать web-push, «установить на экран», оплату; «Поделиться» → мост.
2. `POST /api/push/apns` — сохранять токены устройств; отправлять push через APNs там же, где сейчас web-push.
3. `POST /api/auth/apple` и кнопка «Войти с Apple» в приложении — обязательна, раз есть вход через Яндекс ID и VK ID (правило 4.8).
4. «Заблокировать пользователя» в чате и профиле (правило 1.2 для пользовательского контента).
5. Выложить `site/apple-app-site-association` по адресу `https://torgana.ru/.well-known/apple-app-site-association`
   (без расширения, `Content-Type: application/json`, без редиректов).

## Перед отправкой на проверку

- Скриншоты iPhone 6,9" (1320×2868 или 1290×2796) — 3–10 штук.
- Ссылка на политику конфиденциальности, анкета «App Privacy», возрастной рейтинг (новая анкета с 2026 г.).
- Тестовый аккаунт для проверяющего (логин/пароль) — в App Review Information.
- В заметках для проверяющего перечислить нативные функции (push, «Войти с Apple», «Поделиться», Universal Links) —
  это снижает риск отказа по правилу 4.2 «сайт в обёртке».
- Иконка `AppIcon.png` — временная (буква «Т» в цветах «Небо и сирень»); заменить настоящим логотипом 1024×1024 без прозрачности.
