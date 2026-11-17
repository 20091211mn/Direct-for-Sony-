package com.example.ps4_sender

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Reads the admin's notices and shows a system notification for each new one. */
object NoticeChecker {
    const val PREFS = "ps4sender_native"

    private fun fetch(url: String): String? {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = 15000
            c.readTimeout = 20000
            c.setRequestProperty("User-Agent", "pkg-sender")
            if (c.responseCode != 200) return null
            return c.inputStream.bufferedReader().use { it.readText() }
        } finally {
            c.disconnect()
        }
    }

    private fun millis(date: String): Long =
        try {
            val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            f.timeZone = TimeZone.getTimeZone("UTC")
            f.parse(date.substring(0, 19))?.time ?: 0L
        } catch (e: Exception) {
            0L
        }

    private fun installedBuild(ctx: Context): Long {
        val info = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
        return if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    }

    /** True when the system lets this app post notifications. */
    fun canNotify(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.areNotificationsEnabled()
    }

    /** Checks the notices and records the result. Returns a short text for the settings page. */
    fun runAndRecord(ctx: Context): String {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val result = try {
            val shown = check(ctx)
            "ok: $shown new"
        } catch (e: Exception) {
            "error: ${e.message}"
        }
        prefs.edit().putLong("last_run", System.currentTimeMillis()).putString("last_result", result).apply()
        return result
    }

    /** Returns how many notifications were shown. Throws when the notices cannot be read. */
    private fun check(ctx: Context): Int {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val repo = prefs.getString("repo", null) ?: throw IllegalStateException("repository not set")
        val ar = prefs.getBoolean("ar", true)
        val raw = fetch(
            "https://raw.githubusercontent.com/$repo/main/store/announcements.json" +
                "?t=${System.currentTimeMillis()}"
        )
        if (raw == null) {
            // 404 = nothing published yet; anything else is reported by the caller.
            return 0
        }
        val items = JSONObject(raw).optJSONArray("items") ?: return 0

        val seen = HashSet<String>(prefs.getStringSet("seen", HashSet<String>()) ?: HashSet<String>())
        val firstInstall = ctx.packageManager.getPackageInfo(ctx.packageName, 0).firstInstallTime
        val installed = installedBuild(ctx)
        var shown = 0
        for (i in 0 until items.length()) {
            val o = items.getJSONObject(i)
            val id = o.optString("id")
            if (id.isEmpty() || seen.contains(id)) continue
            seen.add(id)
            // Published before this app was installed: remember it, do not notify.
            val posted = millis(o.optString("date"))
            if (posted in 1 until firstInstall) continue
            val build = o.optLong("build", 0)
            if (o.optString("type") == "update" && build in 1..installed) continue
            if (shown < 3) {
                if (show(ctx, o.optString("title", "PKG Sender"), body(o), o.optString("type") == "update", ar, 100 + shown)) {
                    shown++
                }
            }
        }
        prefs.edit().putStringSet("seen", seen).apply()
        return shown
    }

    private fun body(o: JSONObject): String {
        val sb = StringBuilder(o.optString("body"))
        val features = o.optJSONArray("features")
        if (features != null) {
            for (k in 0 until features.length()) {
                if (sb.isNotEmpty()) sb.append('\n')
                sb.append("• ").append(features.optString(k))
            }
        }
        return sb.toString()
    }

    /** A test notification, to find out whether notifications reach the panel. */
    fun test(ctx: Context): Boolean {
        val ar = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("ar", true)
        return show(
            ctx,
            "PKG Sender",
            if (ar) "هذا إشعار تجريبي. إذا رأيته فالإشعارات تعمل." else "This is a test notification. If you see it, notifications work.",
            false, ar, 199
        )
    }

    private fun show(ctx: Context, title: String, text0: String, isUpdate: Boolean, ar: Boolean, nid: Int): Boolean {
        if (!canNotify(ctx)) return false
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val b: Notification.Builder
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    "ps4sender_news",
                    if (ar) "أخبار وتحديثات" else "News and updates",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
            b = Notification.Builder(ctx, "ps4sender_news")
        } else {
            b = Notification.Builder(ctx)
        }
        val text = if (text0.isEmpty()) (if (ar) "اضغط للتفاصيل" else "Tap for details") else text0
        b.setContentTitle(title)
            .setContentText(text.lines().first())
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(
                if (isUpdate) android.R.drawable.stat_sys_download_done
                else android.R.drawable.ic_dialog_info
            )
            .setAutoCancel(true)
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        if (launch != null) {
            val flag = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
            b.setContentIntent(PendingIntent.getActivity(ctx, 0, launch, flag))
        }
        nm.notify(nid, b.build())
        return true
    }
}
