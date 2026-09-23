package org.kalinka.kalinka

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.Executors

/**
 * Saves a file where the user picks, through the system's Save dialog
 * (ACTION_CREATE_DOCUMENT).
 *
 * The picked document is a content URI, which Dart cannot open, so this
 * opens it and writes the bytes Dart hands over chunk by chunk. Writes run on
 * one background thread, in order; results come back on the main thread. A
 * document picked for a transfer that then fails is deleted with `delete`.
 */
class KalinkaDocumentsPlugin :
    FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {

    companion object {
        private const val CREATE_DOCUMENT_REQUEST = 0x4b4c
    }

    private lateinit var channel: MethodChannel
    // The app's resolver, not the activity's: the grant is the app's, and a
    // transfer outlives an activity recreated under it.
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingCreate: MethodChannel.Result? = null
    private val streams = mutableMapOf<Int, OutputStream>()
    private var nextHandle = 1
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "org.kalinka.kalinka/documents")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        io.execute {
            streams.values.forEach { runCatching { it.close() } }
            streams.clear()
        }
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createDocument" -> createDocument(call, result)
            "openWrite" -> onIo(result) {
                val uri = Uri.parse(call.argument<String>("uri"))
                // Just created, so empty: plain "w", which every provider takes.
                val stream = context.contentResolver.openOutputStream(uri, "w")
                    ?: throw IOException("The document cannot be opened")
                val handle = nextHandle++
                streams[handle] = stream
                handle
            }
            "write" -> onIo(result) {
                val stream = streams[call.argument<Int>("handle")]
                    ?: throw IOException("The document is not open")
                stream.write(call.argument<ByteArray>("bytes"))
                null
            }
            "close" -> onIo(result) {
                streams.remove(call.argument<Int>("handle"))?.let { runCatching { it.close() } }
                null
            }
            "delete" -> onIo(result) {
                runCatching {
                    DocumentsContract.deleteDocument(
                        context.contentResolver,
                        Uri.parse(call.argument<String>("uri")),
                    )
                }
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun createDocument(call: MethodCall, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("no_activity", "Nothing to show the Save dialog over", null)
            return
        }
        if (pendingCreate != null) {
            result.error("busy", "The Save dialog is already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = call.argument<String>("mimeType")
            putExtra(Intent.EXTRA_TITLE, call.argument<String>("filename"))
        }
        pendingCreate = result
        try {
            activity.startActivityForResult(intent, CREATE_DOCUMENT_REQUEST)
        } catch (e: ActivityNotFoundException) {
            pendingCreate = null
            result.error("no_picker", "Nothing on this device can save documents", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CREATE_DOCUMENT_REQUEST) return false
        val result = pendingCreate ?: return true
        pendingCreate = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        result.success(uri?.toString())
        return true
    }

    private fun onIo(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("io", "The document could not be written", null) }
            }
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }
}
