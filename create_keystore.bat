@echo off
REM در صورت حذف یا نیاز به keystore جدید، این اسکریپت را اجرا کن (نیاز به نصب Java/JDK).
cd /d "%~dp0"
if not exist ".github" mkdir .github
keytool -genkeypair -v -storetype PKCS12 -keystore .github/tiknet-release.keystore -alias tiknet -keyalg RSA -keysize 2048 -validity 10000 -storepass tiknet123 -keypass tiknet123 -dname "CN=TikNet, OU=App, O=TikNet, L=Tehran, ST=Tehran, C=IR"
echo.
echo Done. Commit .github/tiknet-release.keystore to the repo.
pause
