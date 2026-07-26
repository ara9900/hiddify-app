package com.hiddify.hiddify

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import android.util.Base64
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.hiddify.hiddify.Application.Companion.packageManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMethodCodec
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream


class PlatformSettingsHandler : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private lateinit var ignoreRequestResult: MethodChannel.Result

    companion object {
        const val channelName = "com.hiddify.app/platform"

        const val REQUEST_IGNORE_BATTERY_OPTIMIZATIONS = 44
        val gson = Gson()

        enum class Trigger(val method: String) {
            IsIgnoringBatteryOptimizations("is_ignoring_battery_optimizations"),
            RequestIgnoreBatteryOptimizations("request_ignore_battery_optimizations"),
            GetInstalledPackages("get_installed_packages"),
            GetPackagesIcon("get_package_icon"),
            InstallApk("install_apk"),
            GetNetworkDiagnostics("get_network_diagnostics"),
            OpenSystemSettings("open_system_settings"),
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val taskQueue = flutterPluginBinding.binaryMessenger.makeBackgroundTaskQueue()
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            channelName,
            StandardMethodCodec.INSTANCE,
            taskQueue
        )
        channel!!.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) {
            ignoreRequestResult.success(resultCode == Activity.RESULT_OK)
            return true
        }
        return false
    }

    data class AppItem(
        @SerializedName("package-name") val packageName: String,
        @SerializedName("name") val name: String,
        @SerializedName("is-system-app") val isSystemApp: Boolean
    )

    @SuppressLint("BatteryLife")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            Trigger.IsIgnoringBatteryOptimizations.method -> {
                result.runCatching {
                    success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Application.powerManager.isIgnoringBatteryOptimizations(Application.application.packageName)
                        } else {
                            true
                        }
                    )
                }
            }

            Trigger.RequestIgnoreBatteryOptimizations.method -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    return result.success(true)
                }
                val intent = Intent(
                    android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${Application.application.packageName}")
                )
                ignoreRequestResult = result
                activity?.startActivityForResult(intent, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            }

            Trigger.GetInstalledPackages.method -> {
                GlobalScope.launch {
                    result.runCatching {
                        val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            PackageManager.GET_PERMISSIONS or PackageManager.MATCH_UNINSTALLED_PACKAGES
                        } else {
                            @Suppress("DEPRECATION")
                            PackageManager.GET_PERMISSIONS or PackageManager.GET_UNINSTALLED_PACKAGES
                        }
                        val installedPackages =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.getInstalledPackages(
                                    PackageManager.PackageInfoFlags.of(
                                        flag.toLong()
                                    )
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getInstalledPackages(flag)
                            }
                        val list = mutableListOf<AppItem>()
                        installedPackages.forEach {
                            if (it.packageName != Application.application.packageName &&
                                (it.requestedPermissions?.contains(Manifest.permission.INTERNET) == true
                                        || it.packageName == "android")
                            ) {
                                list.add(
                                    AppItem(
                                        it.packageName,
                                        it.applicationInfo?.loadLabel(packageManager).toString(),
                                        (it.applicationInfo?.flags?.and(ApplicationInfo.FLAG_SYSTEM) == 1)
                                    )
                                )
                            }
                        }
                        list.sortBy { it.name }
                        success(gson.toJson(list))
                    }
                }
            }

            Trigger.GetPackagesIcon.method -> {
                result.runCatching {
                    val args = call.arguments as Map<*, *>
                    val packageName =
                        args["packageName"] as String
                    val drawable = packageManager.getApplicationIcon(packageName)
                    val bitmap = Bitmap.createBitmap(
                        drawable.intrinsicWidth,
                        drawable.intrinsicHeight,
                        Bitmap.Config.ARGB_8888
                    )
                    val canvas = Canvas(bitmap)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                    val byteArrayOutputStream = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
                    val base64: String =
                        Base64.encodeToString(byteArrayOutputStream.toByteArray(), Base64.NO_WRAP)
                    success(base64)
                }
            }

            Trigger.InstallApk.method -> {
                val act = activity
                if (act == null) {
                    result.error("no_activity", "Activity not available", null)
                    return
                }
                val args = call.arguments as? Map<*, *>
                val path = args?.get("path") as? String
                if (path.isNullOrBlank()) {
                    result.error("invalid_path", "APK path missing", null)
                    return
                }
                val apk = File(path)
                if (!apk.exists()) {
                    result.error("not_found", "APK file not found", null)
                    return
                }
                val uri = FileProvider.getUriForFile(
                    act,
                    "${act.packageName}.fileProvider",
                    apk,
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                act.startActivity(intent)
                result.success(true)
            }

            Trigger.GetNetworkDiagnostics.method -> {
                result.runCatching {
                    success(collectNetworkDiagnostics())
                }
            }

            Trigger.OpenSystemSettings.method -> {
                val act = activity ?: Application.application
                val args = call.arguments as? Map<*, *>
                val target = (args?.get("target") as? String)?.trim().orEmpty()
                val opened = openSystemSettings(act, target)
                result.success(opened)
            }

            else -> result.notImplemented()
        }
    }

    private fun collectNetworkDiagnostics(): Map<String, Any?> {
        val ctx = Application.application
        val resolver = ctx.contentResolver
        val autoTime = Settings.Global.getInt(resolver, Settings.Global.AUTO_TIME, 0) == 1
        val autoTimeZone = Settings.Global.getInt(resolver, Settings.Global.AUTO_TIME_ZONE, 0) == 1
        val airplane = Settings.Global.getInt(resolver, Settings.Global.AIRPLANE_MODE_ON, 0) == 1

        var privateDnsMode = "unknown"
        var privateDnsSpecifier: String? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            privateDnsMode = Settings.Global.getString(resolver, "private_dns_mode") ?: "off"
            privateDnsSpecifier = Settings.Global.getString(resolver, "private_dns_specifier")
        }

        var hasInternet = false
        var validated = false
        var isVpn = false
        var isWifi = false
        var isCellular = false
        var isEthernet = false
        var dnsServers = emptyList<String>()

        try {
            val cm = Application.connectivity
            val network = cm.activeNetwork
            if (network != null) {
                val caps = cm.getNetworkCapabilities(network)
                if (caps != null) {
                    hasInternet = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                    isVpn = caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                    isWifi = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                    isCellular = caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
                    isEthernet = caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                }
                val link = cm.getLinkProperties(network)
                dnsServers = link?.dnsServers?.mapNotNull { it.hostAddress } ?: emptyList()
            }
        } catch (_: Exception) {
        }

        var alwaysOnVpnApp: String? = null
        var alwaysOnVpnLockdown: Boolean? = null
        try {
            alwaysOnVpnApp = Settings.Secure.getString(resolver, "always_on_vpn_app")
            alwaysOnVpnLockdown = Settings.Secure.getInt(resolver, "always_on_vpn_lockdown", 0) == 1
        } catch (_: Exception) {
        }

        val ignoringBattery = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Application.powerManager.isIgnoringBatteryOptimizations(ctx.packageName)
        } else {
            true
        }

        return mapOf(
            "autoTime" to autoTime,
            "autoTimeZone" to autoTimeZone,
            "airplaneMode" to airplane,
            "privateDnsMode" to privateDnsMode,
            "privateDnsSpecifier" to privateDnsSpecifier,
            "hasInternet" to hasInternet,
            "validated" to validated,
            "isVpn" to isVpn,
            "isWifi" to isWifi,
            "isCellular" to isCellular,
            "isEthernet" to isEthernet,
            "dnsServers" to dnsServers,
            "alwaysOnVpnApp" to alwaysOnVpnApp,
            "alwaysOnVpnLockdown" to alwaysOnVpnLockdown,
            "ignoringBatteryOptimizations" to ignoringBattery,
        )
    }

    private fun openSystemSettings(ctx: android.content.Context, target: String): Boolean {
        return try {
            val intent = when (target) {
                "date" -> Intent(Settings.ACTION_DATE_SETTINGS)
                "vpn" -> Intent("android.net.vpn.SETTINGS").takeIf {
                    it.resolveActivity(ctx.packageManager) != null
                } ?: Intent(Settings.ACTION_SETTINGS)
                "apn" -> Intent(Settings.ACTION_APN_SETTINGS)
                "private_dns", "wireless" -> Intent(Settings.ACTION_WIRELESS_SETTINGS)
                "battery" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).takeIf {
                    it.resolveActivity(ctx.packageManager) != null
                } ?: Intent(Settings.ACTION_SETTINGS)
                "airplane" -> Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS).takeIf {
                    it.resolveActivity(ctx.packageManager) != null
                } ?: Intent(Settings.ACTION_WIRELESS_SETTINGS)
                else -> Intent(Settings.ACTION_SETTINGS)
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}