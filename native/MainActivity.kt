package com.example.ps4_sender

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

class MainActivity : FlutterActivity() {
    private val pickCode = 4242
    private var pendingPick: MethodChannel.Result? = null
    private val channels = HashMap<String, FileChannel>()
    private val descriptors = ArrayList<ParcelFileDescriptor>()

    @Synchronized
    private fun channelFor(uri: String): FileChannel {
        channels[uri]?.let { return it }
        val pfd = contentResolver.openFileDescriptor(Uri.parse(uri), "r")
            ?: throw IllegalStateException("cannot open file")
        descriptors.add(pfd)
        val ch = FileInputStream(pfd.fileDescriptor).channel
        channels[uri] = ch
        return ch
    }

    @Synchronized
    private fun releaseFiles() {
        for (c in channels.values) { try { c.close() } catch (_: Exception) {} }
        for (d in descriptors) { try { d.close() } catch (_: Exception) {} }
        channels.clear()
        descriptors.clear()
    }

    override fun onDestroy() {
        releaseFiles()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val r = pendingPick
        pendingPick = null
        if (r == null) return
        if (resultCode != RESULT_OK || data == null) {
            r.success(ArrayList<Map<String, Any>>())
            return
        }
        val uris = ArrayList<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (k in 0 until clip.itemCount) uris.add(clip.getItemAt(k).uri)
        }
        val single = data.data
        if (uris.isEmpty() && single != null) uris.add(single)

        val out = ArrayList<Map<String, Any>>()
        for (u in uris) {
            var name = "file"
            var size = 0L
            try {
                contentResolver.query(u, null, null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        val si = c.getColumnIndex(OpenableColumns.SIZE)
                        if (ni >= 0) name = c.getString(ni) ?: "file"
                        if (si >= 0 && !c.isNull(si)) size = c.getLong(si)
                    }
                }
                if (size <= 0L) {
                    contentResolver.openFileDescriptor(u, "r")?.use { size = it.statSize }
                }
            } catch (_: Exception) {}
            out.add(mapOf("uri" to u.toString(), "name" to name, "size" to size))
        }
        r.success(out)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "ps4sender/keepalive")
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
                        // Like the original app: ask once to be exempt from battery optimization.
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (Build.VERSION.SDK_INT >= 23 && !pm.isIgnoringBatteryOptimizations(packageName)) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } catch (_: Exception) {}
                        }
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, KeepAliveService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, "ps4sender/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        pendingPick = result
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        }
                        startActivityForResult(i, pickCode)
                    }
                    "read" -> {
                        val uri = call.argument<String>("uri")
                        val offset = call.argument<Number>("offset")?.toLong() ?: 0L
                        val length = call.argument<Number>("length")?.toInt() ?: 0
                        if (uri == null || length <= 0) {
                            result.error("arg", "bad arguments", null)
                        } else {
                            Thread {
                                try {
                                    val ch = channelFor(uri)
                                    val buf = ByteBuffer.allocate(length)
                                    var pos = offset
                                    while (buf.hasRemaining()) {
                                        val n = ch.read(buf, pos)
                                        if (n <= 0) break
                                        pos += n
                                    }
                                    val bytes = buf.array().copyOf(buf.position())
                                    runOnUiThread { result.success(bytes) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("read", e.message, null) }
                                }
                            }.start()
                        }
                    }
                    "release" -> {
                        releaseFiles()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(messenger, "ps4sender/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cacheDir" -> result.success(cacheDir.absolutePath)
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("arg", "path missing", null)
                        } else {
                            try {
                                if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                                    startActivity(
                                        Intent(
                                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                            Uri.parse("package:$packageName")
                                        )
                                    )
                                    result.success("needs_permission")
                                } else {
                                    val uri = FileProvider.getUriForFile(
                                        this, "$packageName.fileprovider", File(path)
                                    )
                                    val i = Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(uri, "application/vnd.android.package-archive")
                                        addFlags(
                                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                                Intent.FLAG_ACTIVITY_NEW_TASK
                                        )
                                    }
                                    startActivity(i)
                                    result.success("started")
                                }
                            } catch (e: Exception) {
                                result.error("install", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
