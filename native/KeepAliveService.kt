package com.example.ps4_sender

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/** Foreground service that keeps the phone's mini-server alive and shows the progress. */
class KeepAliveService : Service() {
    companion object {
        @Volatile
        var current: KeepAliveService? = null
    }

    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null
    private var builder: Notification.Builder? = null
    private var manager: NotificationManager? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        current = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager = nm
        val b: Notification.Builder
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel("ps4sender", "PS4 Sender", NotificationManager.IMPORTANCE_LOW)
            )
            b = Notification.Builder(this, "ps4sender")
        } else {
            b = Notification.Builder(this)
        }
        b.setContentTitle("PS4 Sender")
            .setContentText("Sending package to the PS4...")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)

        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            val flag = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
            b.setContentIntent(PendingIntent.getActivity(this, 0, launch, flag))
        }
        builder = b

        val n = b.build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(1, n)
        }
        acquireLocks()
        return START_NOT_STICKY
    }

    /** Updates the ongoing notification with a percentage and a text. */
    fun update(pct: Int, text: String) {
        val b = builder ?: return
        b.setProgress(100, pct.coerceIn(0, 100), false).setContentText(text)
        manager?.notify(1, b.build())
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
        current = null
        try { wake?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        try { wifi?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        wake = null
        wifi = null
        super.onDestroy()
    }
}
