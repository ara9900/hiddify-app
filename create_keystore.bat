@echo off
chcp 65001 >nul
echo ========================================
echo   ساخت keystore برای TikNet (یک بار)
echo ========================================
cd /d "%~dp0"

set KEYSTORE=tiknet.keystore
set ALIAS=tiknet
set PASS=tiknet123

if exist "%KEYSTORE%" (
  echo فایل %KEYSTORE% از قبل وجود دارد. حذفش کن یا اسم دیگری انتخاب کن.
  pause
  exit /b 1
)

echo.
echo در حال ساخت %KEYSTORE% ...
keytool -genkeypair -v -storetype PKCS12 -keystore %KEYSTORE% -alias %ALIAS% -keyalg RSA -keysize 2048 -validity 10000 -storepass %PASS% -keypass %PASS% -dname "CN=TikNet, OU=App, O=TikNet, L=Tehran, ST=Tehran, C=IR"
if errorlevel 1 ( echo خطا در keytool. Java نصب است؟ & pause & exit /b 1 )

echo.
echo ✅ Keystore ساخته شد: %KEYSTORE%
echo.
echo حالا به base64 تبدیل کن و در GitHub Secret با نام ANDROID_KEYSTORE_BASE64 قرار بده.
echo در PowerShell:
echo   [Convert]::ToBase64String([IO.File]::ReadAllBytes('%KEYSTORE%')) ^| Set-Clipboard
echo.
echo پسورد فعلی: %PASS%  ^(در صورت نیاز در Secret با نام ANDROID_KEYSTORE_PASSWORD قرار بده^)
echo.
pause
