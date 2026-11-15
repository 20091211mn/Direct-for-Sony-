package com.example.ps4_sender

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Runs every few hours (JobScheduler) even when the app is closed and shows a
 * system notification for each new notice published by the admin app.
 */
class CheckJobService : JobService() {

    override fun onStartJob(params: JobParameters?): Boolean {
        Thread {
            try {
                check()
            } catch (_: Exception) {
            } finally {
                jobFinished(params, false)
            }
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean = false

    private fun fetch(url: String): String? {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = 15000
            c.readTimeout = 20000
            c.setRequestProperty("User-Agent", "ps4-sender")
            if (c.responseCode != 200) return null
            return c.inputStream.bufferedReader().use { it.readText() }
        } finally {
            c.disconnect()
        }
    }

    private fun installedBuild(): Long {
        val info = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    }

    private fun check() {
        val prefs = getSharedPreferences("ps4sender_native", Context.MODE_PRIVATE)
        val repo = prefs.getString("repo", null) ?: return
        val ar = prefs.getBoolean("ar", true)
        val raw = fetch(
            "https://raw.githubusercontent.com/$repo/main/store/announcements.json" +
                "?t=${System.currentTimeMillis()}"
        ) ?: return
        val items = JSONObject(raw).optJSONArray("items") ?: return

        val seen = HashSet<String>(prefs.getStringSet("seen", HashSet<String>()) ?: HashSet<String>())
        if (!prefs.getBoolean("seeded", false)) {
            // First run: remember what already exists, do not flood the user.
            for (i in 0 until items.length()) seen.add(items.getJSONObject(i).optString("id"))
            prefs.edit().putStringSet("seen", seen).putBoolean("seeded", true).apply()
            return
        }

        val installed = installedBuild()
        var shown = 0
        for (i in 0 until items.length()) {
            val o = items.getJSONObject(i)
            val id = o.optString("id")
            if (id.isEmpty() || seen.contains(id)) continue
            seen.add(id)
            val build = o.optLong("build", 0)
            val isUpdate = o.optString("type") == "update"
            if (isUpdate && build in 1..installed) continue // already installed
            if (shown < 3) {
                show(o, ar, 100 + shown)
                shown++
            }
        }
        prefs.edit().putStringSet("seen", seen).apply()
    }

    private fun show(o: JSONObject, ar: Boolean, nid: Int) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val b: Notification.Builder
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    "ps4sender_news",
                    if (ar) "أخبار وتحديثات" else "News and updates",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
            b = Notification.Builder(this, "ps4sender_news")
        } else {
            b = Notification.Builder(this)
        }

        val title = o.optString("title", "PS4 Sender")
        val body = StringBuilder(o.optString("body"))
        val features = o.optJSONArray("features")
        if (features != null) {
            for (k in 0 until features.length()) {
                if (body.isNotEmpty()) body.append('\n')
                body.append("• ").append(features.optString(k))
            }
        }
        val text = if (body.isEmpty()) (if (ar) "اضغط للتفاصيل" else "Tap for details") else body.toString()

        b.setContentTitle(title)
            .setContentText(text.lines().first())
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(
                if (o.optString("type") == "update") android.R.drawable.stat_sys_download_done
                else android.R.drawable.ic_dialog_info
            )
            .setAutoCancel(true)

        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            val flag = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
            b.setContentIntent(PendingIntent.getActivity(this, 0, launch, flag))
        }
        nm.notify(nid, b.build())
    }
}
