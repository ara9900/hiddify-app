# Pull TikNet diagnostic log from connected device (debuggable or rooted run-as).
$pkg = "com.tik.net"
$serial = if ($env:ADB_SERIAL) { $env:ADB_SERIAL } else { "RFCX50QTACA" }
Write-Host "Device: $serial"
adb -s $serial logcat -d -s flutter | Select-Object -Last 120 | Out-File -FilePath "build-output\device-flutter-log.txt" -Encoding utf8
Write-Host "Saved build-output\device-flutter-log.txt"
Write-Host "In app: حساب من -> گزارش تشخیصی -> کپی/اشتراک"
