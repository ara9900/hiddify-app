@echo off
REM تست سریع TikNet بدون بیلد APK - روی گوشی (کابل) یا امولاتور
cd /d "%~dp0"

echo [1/4] Submodules...
git submodule update --init --recursive 2>nul
if errorlevel 1 echo Warning: submodule init failed, continuing...

echo [2/4] Pub get...
call flutter pub get
if errorlevel 1 ( echo Pub get failed. & pause & exit /b 1 )

echo [3/4] Code gen (build_runner + slang)...
call dart run build_runner build --delete-conflicting-outputs 2>nul
call dart run slang 2>nul
echo (اگر خطای SDK داد، Flutter رو به نسخه 3.38 ارتقا بده یا از FVM استفاده کن)

echo [4/4] Run on device...
echo.
echo دستگاه‌های موجود:
call flutter devices
echo.
call flutter run

pause
