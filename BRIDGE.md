# Мост «сайт ↔ приложение»

Приложение открывает torgana.ru во встроенном браузере (WKWebView). Сайт узнаёт приложение тремя способами:

- в User-Agent есть `TorganaApp/1.0.0 (iOS)`;
- у `<html>` есть классы `in-app` и `in-app-ios` (ставятся до загрузки стилей);
- есть объект `window.TorganaApp` (`platform`, `version`, `native`, `post(msg)`).

Push сайт не касается: их включает и выключает само приложение (родные экраны «Уведомления»), адрес устройства
уходит на сервер из приложения (`POST /api/push/apns`). С сайта 1.60.0 push в браузер убраны совсем.

Сообщения принимаются **только со страниц torgana.ru** — чужие рамки и страницы входа Яндекс/VK звать приложение не могут.

## Сайт → приложение: `window.TorganaApp.post({...})`

| type | поля | что делает |
|---|---|---|
| `share` | `url`, `text` | системное окно «Поделиться». `url` может быть путём (`/l/123`) |
| `haptic` | `style`: `light` `medium` `heavy` `selection` `success` `warning` `error` | виброотклик |
| `auth.apple` | `nonce` (необязательно, лучше дать с сервера) | окно «Войти с Apple»; ответ — `auth.apple` или `auth.apple.error` |
| `badge` | `count` | число на значке приложения (0 — убрать) |
| `open.external` | `url` | открыть ссылку в Safari / звонилке / почте |
| `app.info` | — | ответ — `app.info` (версия, сборка, iOS) |

## Приложение → сайт: событие `torgana-native`

```js
window.addEventListener('torgana-native', (e) => {
  const m = e.detail;
  switch (m.type) {
    case 'auth.apple':      // { identityToken, authorizationCode?, nonce, user, name?, email? }
      fetch('/api/auth/apple', { method: 'POST', headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(m) }).then(() => location.reload());
      break;
    case 'auth.apple.error': // { code: 'canceled' | 'failed' | 'no_token', message? }
      break;
    case 'share.result':    // { completed, activity }
      break;
  }
});
```

## Что проверяет сервер

**«Войти с Apple»** (`POST /api/auth/apple`):
1. Подпись `identityToken` — по ключам `https://appleid.apple.com/auth/keys` (RS256, `kid` из заголовка).
2. `iss` = `https://appleid.apple.com`, `aud` = `ru.torgana.app`, `exp` не истёк.
3. `nonce` в токене = SHA-256 (hex) от присланного `nonce`. Лучше выдавать `nonce` с сервера и помнить его в сессии.
4. Пользователь — по `sub` (он же `user`). Имя и почта приходят **только при первом входе** — сохранить сразу.
   Почта может быть скрытой (`…@privaterelay.appleid.com`): письма на неё доходят, только если домен
   `torgana.ru` и адрес `no-reply@torgana.ru` добавлены в Apple Developer → Sign in with Apple for Email Communication.

**Push** (APNs, HTTP/2): `https://api.push.apple.com/3/device/<token>` (для `env: development` —
`api.sandbox.push.apple.com`), заголовки `apns-topic: ru.torgana.app`, `apns-push-type: alert`,
`authorization: bearer <JWT ES256 из ключа .p8, kid = Key ID, iss = Team ID>`. Пример тела:

```json
{ "aps": { "alert": { "title": "Новое сообщение", "body": "Иван: Ещё продаёте?" }, "sound": "default", "badge": 3 },
  "url": "/chat/42" }
```

Ответ `410` или `400 BadDeviceToken` — удалить токен из базы.

## Что спрятать на сайте в режиме приложения (`html.in-app`)

- оплату тарифов и продвижения, раздел «Для бизнеса» и страницы `/pay/…` (правила App Store 3.1.1 и 3.1.3) — решено: в приложении их нет;
- кнопку «Поделиться» сайта — заменить вызовом `share`.
