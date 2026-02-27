# TikNet VPN Client

This app is customized for **TikNet**: login with panel account, 3 tabs only (Connection, App filter, My account).

## Build

- **App name:** TikNet  
- **Package (Android):** `com.tik.net`  
- **Bundle ID (iOS):** `com.tik.net`

**امضای ثابت (نصب روی نسخهٔ قبلی):** keystore داخل ریپو نیست؛ از **GitHub Secrets** استفاده می‌شود. یک بار keystore را بساز، به base64 تبدیل کن و در ریپو اضافه کن (پایین همین فایل).

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

---

## تنظیم GitHub Secrets برای امضای APK

یک بار این کارها را انجام بده تا بیلد با keystore ثابت امضا شود (نصب روی نسخهٔ قبلی بدون حذف).

### ۱. ساخت keystore (روی ویندوز)

در پوشهٔ پروژه اجرا کن:

```bat
create_keystore.bat
```

یا دستی با Java نصب‌شده:

```bat
keytool -genkeypair -v -storetype PKCS12 -keystore tiknet.keystore -alias tiknet -keyalg RSA -keysize 2048 -validity 10000 -storepass tiknet123 -keypass tiknet123 -dname "CN=TikNet, OU=App, O=TikNet, L=Tehran, ST=Tehran, C=IR"
```

فایل `tiknet.keystore` ساخته می‌شود. پسوردی که گذاشتی (مثلاً `tiknet123`) را یادداشت کن.

### ۲. تبدیل به Base64

**PowerShell (ویندوز):**
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\tiknet.keystore")) | Set-Clipboard
```
خروجی در کلیپبورد کپی می‌شود.

**یا CMD با certutil:**
```bat
certutil -encode tiknet.keystore tiknet.b64
```
فایل `tiknet.b64` باز کن؛ محتوای بین `-----BEGIN CERTIFICATE-----` و `-----END CERTIFICATE-----` را نادیده بگیر و فقط خطوط base64 وسط را یکجا کپی کن (بدون خط جدید بین خطوط).

**لینوکس / macOS:**
```bash
base64 -i tiknet.keystore | tr -d '\n' | pbcopy   # macOS
base64 -w0 tiknet.keystore | xclip -selection c  # لینوکس با xclip
```

### ۳. اضافه کردن Secret در گیت‌هاب

1. برو به ریپو: **Settings → Secrets and variables → Actions**
2. **New repository secret**
3. نام: `ANDROID_KEYSTORE_BASE64`  
   مقدار: همون رشتهٔ base64 که کپی کردی (یک خط طولانی)
4. ذخیره کن.

اختیاری (اگه پسورد یا alias عوض کردی):

- `ANDROID_KEYSTORE_PASSWORD` = همون پسورد keystore (مثلاً tiknet123)
- `ANDROID_KEYSTORE_ALIAS` = همون alias (مثلاً tiknet)

اگه این دو را نذاری، پیش‌فرض `tiknet123` و `tiknet` استفاده می‌شود.

### ۴. حذف فایل keystore از سیستم

بعد از اضافه کردن secret، فایل `tiknet.keystore` (یا هر نامی که دادی) را از روی سیستم حذف کن یا جایی امن نگه دار؛ داخل ریپو commit نکن.
