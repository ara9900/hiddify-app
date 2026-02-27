# TikNet VPN Client

This app is customized for **TikNet**: login with panel account, 3 tabs only (Connection, App filter, My account).

## تست سریع قبل از بیلد (Run locally)

برای تست روی سیستم یا گوشی بدون گرفتن APK هر بار:

### پیش‌نیاز
- **Flutter** همون نسخهٔ پروژه (مثلاً 3.38.x). اگه نسخهٔ سیستم قدیمیه، با [FVM](https://fvm.app) می‌تونی نسخهٔ درست رو نصب کنی:
  ```bash
  fvm install 3.38.5
  fvm use 3.38.5
  ```
- برای **اندروید**: گوشی با USB دیباگ روشن، یا یک امولاتور (مثلاً از Android Studio).

### یک‌بار آماده‌سازی
```bash
cd "d:\hiddify with cursor"
git submodule update --init --recursive
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run slang
```

### اجرا
- **روی گوشی با کابل:** گوشی رو وصل کن، بعد:
  ```bash
  flutter run
  ```
- **روی امولاتور اندروید:** امولاتور رو اجرا کن، بعد همون `flutter run`.
- **لیست دستگاه‌ها:** `flutter devices` تا ببینی کدوم دستگاه در دسترسه؛ بعد مثلاً:
  ```bash
  flutter run -d <device_id>
  ```
- **روی ویندوز (دسکتاپ):** اگه فقط می‌خوای UI رو ببینی بدون گوشی:
  ```bash
  flutter run -d windows
  ```

وقتی اپ با `flutter run` بالا اومد، با **r** (Hot Reload) و **R** (Hot Restart) می‌تونی تغییرات رو فوری ببینی بدون بیلد دوباره.

اسکریپت `run_local.bat` هم همون کارها رو به صورت خودکار انجام می‌ده.

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
