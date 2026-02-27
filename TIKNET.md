# TikNet VPN Client

This app is customized for **TikNet**: login with panel account, 3 tabs only (Connection, App filter, My account).

## Build

- **App name:** TikNet  
- **Package (Android):** `com.tik.net`  
- **Bundle ID (iOS):** `com.tik.net`

در بیلد گیت‌هاب یک keystore ثابت (با cache) استفاده می‌شود تا هر بیلد با همان امضا ساخته شود و بتوان بدون حذف اپ، نسخهٔ جدید را روی نسخهٔ قبلی نصب کرد.

## Panel API

- Set **Panel URL** on the login screen (e.g. `https://your-panel.com`).
- Login: `POST /api/customer/login` with `username` and `password`.
- After login, the app receives `subscription_url` and loads config automatically.

## Disable TikNet mode

To restore the original Hiddify UI (all tabs, no login), set in `lib/core/model/tiknet_config.dart`:

```dart
const bool tikNetMode = false;
```

Then run `dart run build_runner build` and rebuild.
