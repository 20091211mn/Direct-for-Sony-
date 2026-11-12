package com.example.ps4_sender

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ps4sender/keepalive")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                            != PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                        }
                        val i = Intent(this, KeepAliveService::class.java)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, KeepAliveService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
