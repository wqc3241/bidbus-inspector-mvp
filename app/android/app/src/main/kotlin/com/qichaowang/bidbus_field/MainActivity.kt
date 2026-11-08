package com.qichaowang.bidbus_field

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 360 view: 36 evenly spaced frames from the walk-around, frame k at (k - 0.5) / 36 x duration, long side 1600 px
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bidbus/frames").setMethodCallHandler { call, result ->
            if (call.method != "spin") return@setMethodCallHandler result.notImplemented()
            val video = call.argument<String>("video")!!
            val dir = call.argument<String>("dir")!!
            Thread {
                val out = ArrayList<String>()
                val r = MediaMetadataRetriever()
                try {
                    r.setDataSource(video)
                    val ms = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L
                    for (k in 1..36) {
                        val us = ((k - 0.5) / 36 * ms * 1000).toLong()
                        var bmp = if (Build.VERSION.SDK_INT >= 27) r.getScaledFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST, 1600, 1600)
                                  else r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST)
                        if (bmp == null) continue
                        val s = 1600.0 / maxOf(bmp.width, bmp.height)
                        if (s < 1) bmp = Bitmap.createScaledBitmap(bmp, (bmp.width * s).toInt(), (bmp.height * s).toInt(), true)
                        val p = "%s/spin-%02d.jpg".format(dir, k)
                        FileOutputStream(p).use { bmp.compress(Bitmap.CompressFormat.JPEG, 85, it) }
                        out.add(p)
                    }
                } catch (e: Exception) {
                } finally {
                    r.release()
                }
                Handler(Looper.getMainLooper()).post { result.success(out) }
            }.start()
        }
    }
}
