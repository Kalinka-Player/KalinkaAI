package org.kalinka.kalinka

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val mediaPlugin = KalinkaMediaPlugin()
    private var resumed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(mediaPlugin)
        flutterEngine.plugins.add(KalinkaDocumentsPlugin())
    }

    override fun onResume() {
        super.onResume()
        resumed = true
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        mediaPlugin.dispatchVolumeKey(event, resumed && hasWindowFocus()) || super.dispatchKeyEvent(event)
}
