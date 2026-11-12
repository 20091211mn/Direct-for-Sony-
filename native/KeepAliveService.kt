package com.example.ps4_sender

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/** Foreground service that keeps the phone's mini-server alive while the app is in background. */
class KeepAliveService : Service() {
    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder: Notification.Builder
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel("ps4sender", "PS4 Sender", NotificationManager.IMPORTANCE_LOW)
            )
            builder = Notification.Builder(this, "ps4sender")
        } else {
            builder = Notification.Builder(this)
        }
        val n = builder
            .setContentTitle("PS4 Sender")
            .setContentText("Sending package to the PS4...")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(1, n)
        }
        acquireLocks()
        return START_NOT_STICKY
    }

    private fun acquireLocks() {
        if (wake == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ps4sender:keepalive").apply {
                setReferenceCounted(false)
                acquire(4 * 60 * 60 * 1000L)
            }
        }
        if (wifi == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifi = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "ps4sender:wifi").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    override fun onDestroy() {
        try { wake?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        try { wifi?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        wake = null
        wifi = null
        super.onDestroy()
    }
}
