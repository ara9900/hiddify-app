# TikNet VPN Client

This app is customized for **TikNet**: login with panel account, 3 tabs only (Connection, App filter, My account).

## Build

- **App name:** TikNet  
- **Package (Android):** `com.tik.net`  
- **Bundle ID (iOS):** `com.tik.net`

**امضای ثابت (نصب روی نسخهٔ قبلی):** keystore داخل ریپو نیست؛ از **GitHub Secrets** استفاده می‌شود. یک بار keystore را بساز، به base64 تبدیل کن و در ریپو اضافه کن (پایین همین فایل).

## Panel API & config

Panel base URL is resolved automatically (no manual entry on login):

1. `GET https://ara9900.github.io/app-config/config.json` → `api_urls`
2. If GitHub is blocked: `GET https://panel.tikn.ir/static/config.json` → same JSON shape
3. Else cached `api_urls` on device
4. Else hardcoded: `https://panel.tikn.ir`

Host the same JSON in the panel repo at **`app/static/config.json`** (served as `/static/config.json`):

```json
{
  "api_urls": ["https://panel.tikn.ir"]
}
```

Then health check + login: `GET /api/health`, `POST /api/customer/login`.

After login the app:

1. `GET /api/customer/me` — user info (cache)
2. `GET /api/customer/subscription/config` — raw VPN config (Bearer token; panel proxies subscription URL)
3. Imports config into a local Hiddify profile named **TikNet** and sets it active

**Server catalog (admin-managed, app picker):**

- Admin: `/admin/app-servers` — add subscription link or single config; tier (free/normal/vip), country code, VIP-only flag
- App: `GET /api/customer/servers` — list; `GET /api/customer/servers/{id}/config` — raw config
- User selects server on connection tab; default **اشتراک من** uses personal subscription config

The **بروزرسانی** button on «حساب من» runs the same sync + profile apply.

Panel files (separate repo `project vpn with cursor`):

- `app/routers/api.py` — `POST /api/customer/login`, `GET /api/customer/subscription/config`
- `app/static/config.json` — public `api_urls` for app bootstrap
- `app/services/order_service.py` — `subscription_url` on active order

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
