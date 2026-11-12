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
BRIDGE.md                       что должен уметь сайт: команды, события, проверки на сервере
```

## Сборка

- **Каждый push в `main`** — проверочная сборка под симулятор (без подписи). Ошибки — во вкладке Actions.
- **Выпуск в TestFlight** — тег `V1.0.1` (номер версии берётся из тега) или Actions → iOS → Run workflow → галочка «TestFlight».
  Номер сборки = номер запуска, растёт сам.

На Mac (если появится): `brew install xcodegen && xcodegen generate && open Torgana.xcodeproj`.

## Что сделать в Apple (после активации Apple Developer)

1. **Team ID** — developer.apple.com → Membership details. Нужен для секрета `APPLE_TEAM_ID` и ключа push (п. 5).
2. **Ключ App Store Connect API** — appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API →
   Team Keys → «+», роль **Admin** (нужна, чтобы сборка сама создавала сертификаты и профили). Скачать `.p8` (даётся один раз),
   записать Key ID и Issuer ID.
3. **Секреты GitHub** — репозиторий → Settings → Secrets and variables → Actions:
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (весь текст файла `.p8`).
4. **Карточка приложения** — App Store Connect → Apps → «+» → New App: iOS, название «Торгана», язык русский,
   Bundle ID `ru.torgana.app` (если его нет в списке — сначала запустить выпуск в TestFlight, сборка создаст App ID сама,
   или создать вручную в Certificates, Identifiers & Profiles с Push Notifications, Sign in with Apple, Associated Domains).
5. **Ключ APNs для push** — Certificates, Identifiers & Profiles → Keys → «+» → Apple Push Notifications service.
   `.p8`, Key ID и Team ID — на сайте в «Модерация → Настройки → Приложение iPhone» (не в этот репозиторий).
   Там же кнопка «Проверить на моём iPhone». С ключом сайт сам отдаёт файл Universal Links
   `https://torgana.ru/.well-known/apple-app-site-association` (Team ID берётся из ключа).

## Что умеет сайт (torgana, с версии 1.56.0)

Подробно — в [BRIDGE.md](BRIDGE.md).

1. Режим приложения (`window.TorganaApp`): нет оплаты — ни продвижения, ни тарифов, ни раздела «Для бизнеса» (правило 3.1.1);
   нет web-push и «Установить на экран»; «Поделиться» — системное окно iPhone; число на значке.
2. Push через APNs: `POST /api/push/apns` (адрес устройства), `POST /api/push/apns/off`; каждое уведомление уходит и в браузеры, и в приложение.
3. «Войти с Apple»: `POST /api/auth/apple/nonce` → окно Apple → `POST /api/auth/apple` (подпись, aud, одноразовый nonce);
   привязка Apple ID — в «Настройки → Пароль и вход».
4. «Заблокировать пользователя» в чате и профиле — есть с 1.48.0 (правило 1.2).
5. `/.well-known/apple-app-site-association` — сайт отдаёт сам, когда в модерации сохранён ключ Apple.

## Перед отправкой на проверку

- Скриншоты iPhone 6,9" (1320×2868 или 1290×2796) — 3–10 штук.
- Ссылка на политику конфиденциальности, анкета «App Privacy», возрастной рейтинг (новая анкета с 2026 г.).
- Тестовый аккаунт для проверяющего (логин/пароль) — в App Review Information.
- В заметках для проверяющего перечислить нативные функции (push, «Войти с Apple», «Поделиться», Universal Links) —
  это снижает риск отказа по правилу 4.2 «сайт в обёртке».
- Иконка `AppIcon.png` — знак Торганы на фирменном градиенте, 1024×1024 без прозрачности.
