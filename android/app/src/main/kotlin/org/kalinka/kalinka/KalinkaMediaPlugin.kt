package org.kalinka.kalinka

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.VibrationEffect.Composition.DELAY_TYPE_PAUSE
import android.os.VibrationEffect.Composition.PRIMITIVE_CLICK
import android.os.VibrationEffect.Composition.PRIMITIVE_QUICK_FALL
import android.os.VibrationEffect.Composition.PRIMITIVE_TICK
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.KeyEvent
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class KalinkaMediaPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    companion object {
        private const val TAG = "KalinkaMedia"
    }

    private lateinit var methodChannel: MethodChannel
    private val volumeKeys = KalinkaVolumeKeys { level, max ->
        methodChannel.invokeMethod("volumeActivity", mapOf("level" to level, "max" to max))
    }

    fun dispatchVolumeKey(event: KeyEvent, foreground: Boolean): Boolean =
        volumeKeys.dispatch(event, foreground)

    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var mediaService: KalinkaMediaService? = null
    private var serviceBound = false
    private var bindingRegistered = false

    // Pending enable call that arrived before the service finished binding.
    private var pendingEnable: Pair<String, Int>? = null

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            Log.d(TAG, "onServiceConnected")
            if (!bindingRegistered) return
            val localBinder = binder as? KalinkaMediaService.LocalBinder ?: run {
                Log.e(TAG, "onServiceConnected: binder is not LocalBinder ($binder)")
                return
            }
            mediaService = localBinder.getService()
            serviceBound = true
            pendingEnable?.let { (host, port) ->
                Log.d(TAG, "onServiceConnected: flushing pendingEnable host=$host port=$port")
                pendingEnable = null
                mediaService?.enable(host, port, this@KalinkaMediaPlugin)
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "onServiceDisconnected")
            mediaService = null
            serviceBound = false
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "org.kalinka.kalinka/media_session")
        methodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        unbindAndStop()
        context = null
    }

    // --- MethodCallHandler ---

    @RequiresApi(Build.VERSION_CODES.BAKLAVA)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "enableNotification" -> {
                val args = call.arguments as? Map<*, *>
                val rawPort = args?.get("port")
                Log.d(TAG, "enableNotification: rawPort=$rawPort (${rawPort?.javaClass?.simpleName})")
                val host = args?.get("host") as? String ?: ""
                val port = when (rawPort) {
                    is Int -> rawPort
                    is Long -> rawPort.toInt()
                    else -> 0
                }
                Log.d(TAG, "enableNotification: host=$host port=$port serviceBound=$serviceBound")
                if (host.isNotEmpty() && port > 0) {
                    if (!serviceBound) {
                        pendingEnable = Pair(host, port)
                        startAndBindService()
                    } else {
                        mediaService?.enable(host, port, this)
                    }
                } else {
                    Log.w(TAG, "enableNotification: skipped (host='$host' port=$port)")
                }
                result.success(null)
            }
            "disableNotification" -> {
                Log.d(TAG, "disableNotification: serviceBound=$serviceBound")
                unbindAndStop()
                result.success(null)
            }
            "hapticCorkPop" -> {
                hapticCorkPop()
                result.success(null)
            }
            "hapticDelete" -> {
                hapticDelete()
                result.success(null)
            }
            "hapticTick" -> {
                hapticTick()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun hapticTick() {
        val ctx = context ?: return
        val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ctx.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            ctx.getSystemService(Vibrator::class.java)
        }

        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                val effect = VibrationEffect.startComposition()
                    .addPrimitive(PRIMITIVE_TICK)
                    .compose()
                vibrator.vibrate(effect)
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                val effect = VibrationEffect.createOneShot(15, 80)
                vibrator.vibrate(effect)
            }
            else -> {
                vibrator.vibrate(15)
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.BAKLAVA)
    @Suppress("DEPRECATION")
    private fun hapticCorkPop() {
        val ctx = context ?: return
        val vibrator: Vibrator =
            ctx.getSystemService(VibratorManager::class.java).defaultVibrator

        when {
            true -> {
                val effect = VibrationEffect.startComposition()
                    .addPrimitive(PRIMITIVE_QUICK_FALL)
                    .addPrimitive(PRIMITIVE_CLICK, 0.7F, 50, DELAY_TYPE_PAUSE)
                    .compose()
                vibrator.vibrate(effect)
            }
            true -> {
                val effect = VibrationEffect.createWaveform(
                    longArrayOf(0, 5, 5, 15, 10),
                    intArrayOf(0, 180, 220, 80, 0),
                    -1
                )
                vibrator.vibrate(effect)
            }
            else -> {
                vibrator.vibrate(30)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun hapticDelete() {
        val ctx = context ?: return
        val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ctx.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            ctx.getSystemService(Vibrator::class.java)
        }

        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                val effect = VibrationEffect.startComposition()
                    .addPrimitive(PRIMITIVE_TICK, 0.4f, 0)
                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_THUD, 0.9f, 30)
                    .compose()
                vibrator.vibrate(effect)
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                val effect = VibrationEffect.createWaveform(
                    longArrayOf(0, 8, 20, 30),
                    intArrayOf(0, 80, 0, 220),
                    -1
                )
                vibrator.vibrate(effect)
            }
            else -> {
                vibrator.vibrate(30)
            }
        }
    }

    private fun startAndBindService() {
        val ctx = context ?: run { Log.e(TAG, "startAndBindService: context is null"); return }
        if (bindingRegistered) return
        Log.d(TAG, "startAndBindService")
        requestNotificationPermissionIfNeeded()
        // BindService only — the service stays alive while bound, lifts itself
        // into the foreground (with notification) once a current track is known,
        // and tears the foreground state down when there isn't one. Skipping
        // startForegroundService avoids the 5-second startForeground deadline
        // and the placeholder notification it forces.
        val intent = Intent(ctx, KalinkaMediaService::class.java)
        bindingRegistered = ctx.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
    }

    private fun unbindAndStop() {
        // Disconnect can arrive before onServiceConnected. Cancel both the
        // binding and its queued enable so a late callback cannot resurrect it.
        pendingEnable = null
        mediaService?.disable(this)
        mediaService = null
        serviceBound = false
        val ctx = context ?: return
        if (bindingRegistered) {
            bindingRegistered = false
            ctx.unbindService(serviceConnection)
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val activity = activityBinding?.activity ?: return
            if (ContextCompat.checkSelfPermission(
                    activity,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    9001
                )
            }
        }
    }

    // --- ActivityAware ---

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }
}
