package org.kalinka.kalinka

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import android.util.Log
import androidx.media.session.MediaButtonReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.io.FileDescriptor
import java.io.PrintWriter
import java.net.URL
import java.util.concurrent.TimeUnit

class KalinkaMediaService : Service() {

    companion object {
        private const val TAG = "KalinkaMedia"
        const val CHANNEL_ID = "KAI_MEDIA_CHANNEL"
        const val NOTIFICATION_ID = 1001
        const val ACTION_PLAY = "org.kalinka.kalinka.ACTION_PLAY"
        const val ACTION_PAUSE = "org.kalinka.kalinka.ACTION_PAUSE"
        const val ACTION_NEXT = "org.kalinka.kalinka.ACTION_NEXT"
        const val ACTION_PREV = "org.kalinka.kalinka.ACTION_PREV"

    }

    inner class LocalBinder : Binder() {
        fun getService(): KalinkaMediaService = this@KalinkaMediaService
    }

    private val binder = LocalBinder()
    private var mediaSession: MediaSessionCompat? = null
    private lateinit var routing: KalinkaRouting
    private var outputReady = false
    private var hasCurrentTrack = false
    private val serviceScope = CoroutineScope(Dispatchers.Main + Job())
    private val mainHandler = Handler(Looper.getMainLooper())

    // --- Connection config ---
    private var server = ServerAddress("http", "", 0)
    private var enableOwner: Any? = null
    private var isEnabled = false

    private var notificationVisible = false

    // True while an input plugin plays exclusively, outside the queue (a Qobuz
    // Connect receiver). Its own app shows that playback and should get the
    // volume keys, which only one media session can, so ours stands down.
    private var exclusivePlayback = false

    // --- WebSocket connections ---
    private val okHttpClient = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .build()
    private var queueWs: WebSocket? = null
    private var deviceWs: WebSocket? = null

    // Commands queued while WS is not yet open (e.g. user taps button before first connection).
    private var pendingQueueCommand: String? = null

    // --- Playback state ---
    private var currentTitle: String = ""
    private var currentArtist: String = ""
    private var currentAlbumArtUrl: String? = null
    private var currentDurationMs: Long = 0
    private var currentPositionMs: Long = 0
    private var currentIsPlaying: Boolean = false
    private var currentPlayerState: String = "STOPPED"  // PLAYING, PAUSED, BUFFERING, STOPPED, ERROR
    private var currentAlbumArt: Bitmap? = null
    private var albumArtJob: Job? = null

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        createNotificationChannel()
        routing = KalinkaRouting(this) { ready ->
            outputReady = ready
            if (isEnabled && ready && hasCurrentTrack && !exclusivePlayback) {
                ensureMediaSession()
                updateMediaSessionMetadata()
                updatePlaybackState()
                postNotification()
            } else if (!ready) {
                hideNotification()
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun dump(fd: FileDescriptor, writer: PrintWriter, args: Array<out String>?) {
        writer.println("enabled=$isEnabled queueSocket=${queueWs != null} deviceSocket=${deviceWs != null}")
        writer.println("playback=$currentPlayerState hasTrack=$hasCurrentTrack exclusive=$exclusivePlayback outputReady=$outputReady")
        writer.println("session=${mediaSession != null} notification=$notificationVisible")
        routing.dump(writer)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")
        // Forward hardware media button events (headphones, etc.) to the session callback.
        mediaSession?.let { MediaButtonReceiver.handleIntent(it, intent) }

        when (intent?.action) {
            ACTION_PLAY -> sendResumeOrPlay()
            ACTION_PAUSE -> sendQueueCommand("""{"command":"pause","paused":true}""")
            ACTION_NEXT -> sendQueueCommand("""{"command":"next"}""")
            ACTION_PREV -> sendQueueCommand("""{"command":"prev"}""")
        }
        return START_NOT_STICKY
    }

    /**
     * Called when the user swipes the app away from recents. Tear everything
     * down so the notification disappears with the task.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "onTaskRemoved")
        disable()
        super.onTaskRemoved(rootIntent)
        stopSelf()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        disable()
        albumArtJob?.cancel()
        serviceScope.cancel()
        super.onDestroy()
    }

    // -------------------------------------------------------------------------
    // Public API (called from KalinkaMediaPlugin)
    // -------------------------------------------------------------------------

    internal fun enable(address: ServerAddress, owner: Any? = null) {
        Log.d(TAG, "enable: $address")
        if (isEnabled && address == server && queueWs != null && deviceWs != null) {
            enableOwner = owner
            return
        }
        // If switching servers, fully tear down first so we don't mix state.
        if (isEnabled && address != server) {
            disable()
        }
        server = address
        enableOwner = owner
        isEnabled = true
        // Reset playback state — fresh session, fresh state.
        resetPlaybackState()
        routing.start(server)
        connectQueueWs()
        connectDeviceWs()
    }

    fun disable(owner: Any? = null) {
        // During Activity/engine replacement the new plugin can bind before
        // the old one detaches. Only the current owner may disable via Flutter.
        // Native connection loss and service teardown always disable.
        if (owner != null && enableOwner !== owner) return
        enableOwner = null
        Log.d(TAG, "disable")
        isEnabled = false
        hideNotification()
        routing.stop()
        closeConnections()
        resetPlaybackState()
    }

    private fun resetPlaybackState() {
        currentTitle = ""
        currentArtist = ""
        currentAlbumArtUrl = null
        currentDurationMs = 0
        currentPositionMs = 0
        currentIsPlaying = false
        currentPlayerState = "STOPPED"
        exclusivePlayback = false
        currentAlbumArt = null
        albumArtJob?.cancel()
        albumArtJob = null
        hasCurrentTrack = false
        outputReady = false
    }

    // -------------------------------------------------------------------------
    // WebSocket connections
    // -------------------------------------------------------------------------

    private fun connectQueueWs() {
        val url = server.webSocketUrl("/queue/ws")
        Log.d(TAG, "connectQueueWs: $url")
        val old = queueWs; queueWs = null; old?.close(1000, null)

        val request = Request.Builder().url(url).build()
        val ws = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "queueWs onOpen")
                mainHandler.post {
                    if (webSocket !== queueWs) return@post
                    pendingQueueCommand?.let { cmd ->
                        Log.d(TAG, "queueWs flushing pendingCommand: $cmd")
                        pendingQueueCommand = null
                        webSocket.send(cmd)
                    }
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.d(TAG, "queueWs message: ${text.take(120)}")
                mainHandler.post { if (webSocket === queueWs) handleQueueEvent(text) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "queueWs onFailure: ${t.message} response=${response?.code}")
                connectionLost(webSocket)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
                connectionLost(webSocket)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "queueWs onClosed: code=$code reason=$reason")
                connectionLost(webSocket)
            }
        })
        queueWs = ws
    }

    private fun connectDeviceWs() {
        val url = server.webSocketUrl("/device/ws")
        Log.d(TAG, "connectDeviceWs: $url")
        val old = deviceWs; deviceWs = null; old?.close(1000, null)

        val request = Request.Builder().url(url).build()
        val ws = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "deviceWs onOpen")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.d(TAG, "deviceWs message: ${text.take(120)}")
                mainHandler.post { if (webSocket === deviceWs) handleDeviceEvent(text) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "deviceWs onFailure: ${t.message} response=${response?.code}")
                connectionLost(webSocket)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
                connectionLost(webSocket)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "deviceWs onClosed: code=$code reason=$reason")
                connectionLost(webSocket)
            }
        })
        deviceWs = ws
    }

    private fun closeConnections() {
        val q = queueWs; queueWs = null; q?.close(1000, null)
        val d = deviceWs; deviceWs = null; d?.close(1000, null)
        pendingQueueCommand = null
    }

    private fun sendQueueCommand(json: String) {
        if (!isEnabled) return
        val ws = queueWs
        if (ws != null) ws.send(json) else pendingQueueCommand = json
    }

    private fun connectionLost(webSocket: WebSocket) {
        mainHandler.post {
            // A callback from a socket we replaced must not disable the new
            // connection. A real loss ends this notification's lifetime; only
            // a new enable from the app may start it again.
            if (isEnabled && (webSocket === queueWs || webSocket === deviceWs)) disable()
        }
    }

    private fun sendResumeOrPlay() {
        if (currentPlayerState == "PAUSED") {
            sendQueueCommand("""{"command":"pause","paused":false}""")
        } else {
            sendQueueCommand("""{"command":"play"}""")
        }
    }

    // -------------------------------------------------------------------------
    // Event handling
    // -------------------------------------------------------------------------

    private fun handleQueueEvent(text: String) {
        try {
            val json = JSONObject(text)
            routing.queueEvent(json)
            val eventType = json.optString("event_type")
            Log.d(TAG, "handleQueueEvent: event_type=$eventType")
            when (eventType) {
                // Already applied by routing.queueEvent above.
                "renderers_changed", "current_renderer_changed" -> Unit
                "playback_control_changed" -> {
                    exclusivePlayback = isExclusive(json.optJSONObject("control"))
                    Log.d(TAG, "playback_control_changed: exclusive=$exclusivePlayback")
                    // Stepping back in waits for the queue's own state, which
                    // the server sends right after.
                    if (exclusivePlayback) hideNotification()
                }
                "state_changed" -> {
                    if (exclusivePlayback) return
                    val state = json.optJSONObject("state") ?: run {
                        Log.w(TAG, "state_changed: missing 'state' field")
                        return
                    }
                    updateFromPlaybackState(state, serverTimeNs = null)
                }
                "replay_event" -> {
                    val stateType = json.optString("state_type")
                    Log.d(TAG, "replay_event: state_type=$stateType")
                    if (stateType == "PlayQueueState") {
                        val outerState = json.optJSONObject("state") ?: run {
                            Log.w(TAG, "replay_event: missing 'state' field")
                            return
                        }
                        exclusivePlayback =
                            isExclusive(outerState.optJSONObject("playback_control"))
                        if (exclusivePlayback) {
                            hideNotification()
                            return
                        }
                        val playbackState = outerState.optJSONObject("playback_state") ?: run {
                            Log.w(TAG, "replay_event: missing 'playback_state' field; keys=${outerState.keys().asSequence().toList()}")
                            return
                        }
                        val serverTimeNs = if (json.has("server_time_ns")) json.getLong("server_time_ns") else null
                        updateFromPlaybackState(playbackState, serverTimeNs)
                    }
                }
                else -> Log.d(TAG, "handleQueueEvent: ignoring event_type=$eventType")
            }
        } catch (e: Exception) {
            Log.e(TAG, "handleQueueEvent exception: $e")
        }
    }

    // Only a mode this service knows takes Kalinka's queue out of play.
    private fun isExclusive(control: JSONObject?): Boolean =
        control?.optString("mode") == "exclusive"

    private fun updateFromPlaybackState(stateJson: JSONObject, serverTimeNs: Long?) {
        val stateStr = stateJson.optString("state", "")
        val newIsPlaying = stateStr == "PLAYING" || stateStr == "BUFFERING"
        currentPlayerState = stateStr
        val trackJson = stateJson.optJSONObject("current_track")
        Log.d(TAG, "updateFromPlaybackState: state=$stateStr isPlaying=$newIsPlaying hasTrack=${trackJson != null} title=${trackJson?.optString("title")}")

        // No current track → notification (and session) must not be present.
        // This covers playqueue cleared, fresh server with no playback, etc.
        hasCurrentTrack = trackJson != null
        if (trackJson == null) {
            hideNotification()
            return
        }

        val reportedPositionMs = stateJson.optLong("position", 0L)
        val adjustedPositionMs = if (serverTimeNs != null && newIsPlaying) {
            val timestampNs = stateJson.optLong("timestamp_ns", 0L)
            val ageMs = ((serverTimeNs - timestampNs) / 1_000_000L).coerceAtLeast(0L)
            reportedPositionMs + ageMs
        } else {
            reportedPositionMs
        }

        currentIsPlaying = newIsPlaying
        currentPositionMs = adjustedPositionMs

        currentTitle = trackJson.optString("title", "")
        currentDurationMs = (trackJson.optDouble("duration", 0.0) * 1000).toLong()
        currentArtist = when {
            !trackJson.isNull("performer") ->
                trackJson.optJSONObject("performer")?.optString("name", "")
                    ?.takeIf { it.isNotEmpty() }
                    ?: trackJson.optJSONObject("album")?.optString("title", "") ?: ""
            !trackJson.isNull("album") ->
                trackJson.optJSONObject("album")?.optString("title", "") ?: ""
            else -> ""
        }

        val newArtUrl = trackJson.optJSONObject("album")
            ?.takeIf { !it.isNull("image") }
            ?.optJSONObject("image")
            ?.optString("small", "")
            ?.takeIf { it.isNotEmpty() }
            ?.let(server::resolve)

        Log.d(TAG, "albumArt: newArtUrl=$newArtUrl currentAlbumArtUrl=$currentAlbumArtUrl changed=${newArtUrl != currentAlbumArtUrl}")
        if (newArtUrl != currentAlbumArtUrl) {
            currentAlbumArtUrl = newArtUrl
            currentAlbumArt = null
            albumArtJob?.cancel()
            if (newArtUrl != null) {
                albumArtJob = serviceScope.launch {
                    Log.d(TAG, "albumArt: loading $newArtUrl")
                    currentAlbumArt = loadBitmapFromUrl(newArtUrl)
                    Log.d(TAG, "albumArt: loaded=${currentAlbumArt != null}")
                    updateMediaSessionMetadata()
                    postNotification()
                }
            }
        }

        ensureMediaSession()
        updateMediaSessionMetadata()
        updatePlaybackState()
        postNotification()
    }

    private fun handleDeviceEvent(text: String) {
        try {
            val json = JSONObject(text)
            val volume = when (json.optString("event_type")) {
                "volume_changed" -> json.optJSONObject("volume")
                "replay_event" -> if (json.optString("state_type") == "ExtDeviceState")
                    json.optJSONObject("state")?.optJSONObject("volume") else null
                else -> null
            } ?: return

            routing.deviceVolume(volume)
        } catch (_: Exception) {}
    }

    // -------------------------------------------------------------------------
    // MediaSession & notification
    // -------------------------------------------------------------------------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Media Playback", NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Kalinka media playback controls"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    /**
     * Lazily create the MediaSession. Tied to notification visibility — torn
     * down in [hideNotification] so that volume keys, lock-screen controls etc.
     * stop routing to us when there's no active playback to control.
     */
    private fun ensureMediaSession() {
        if (!isEnabled || mediaSession != null || !outputReady || exclusivePlayback) return
        Log.d(TAG, "ensureMediaSession: creating")
        val mediaButtonReceiver = ComponentName(this, MediaButtonReceiver::class.java)
        mediaSession = MediaSessionCompat(this, "KaiMediaSession", mediaButtonReceiver, null).apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() { sendResumeOrPlay() }
                override fun onPause() { sendQueueCommand("""{"command":"pause","paused":true}""") }
                override fun onSkipToNext() { sendQueueCommand("""{"command":"next"}""") }
                override fun onSkipToPrevious() { sendQueueCommand("""{"command":"prev"}""") }
                override fun onStop() { sendQueueCommand("""{"command":"stop"}""") }
                override fun onSeekTo(pos: Long) {
                    sendQueueCommand("""{"command":"seek","position_ms":$pos}""")
                }
            })
        }
        // Android observes active sessions independently of the notification.
        // Attach the remote output before exposing this session to SystemUI.
        routing.setSession(mediaSession)
        mediaSession?.isActive = true
    }

    private fun releaseMediaSession() {
        val session = mediaSession ?: return
        Log.d(TAG, "releaseMediaSession")
        // Detaching from MediaRouter resets playback to local. Deactivate first
        // so the active session never advertises the phone as its output.
        session.isActive = false
        routing.setSession(null)
        session.release()
        mediaSession = null
    }

    private fun updateMediaSessionMetadata() {
        val session = mediaSession ?: return
        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, currentDurationMs)
            .apply { currentAlbumArt?.let { putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it) } }
            .build()
        session.setMetadata(metadata)
    }

    private fun updatePlaybackState() {
        val session = mediaSession ?: return
        val state = if (currentIsPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        val playbackState = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_STOP or
                PlaybackStateCompat.ACTION_SEEK_TO
            )
            .setState(state, currentPositionMs, if (currentIsPlaying) 1f else 0f)
            .build()
        session.setPlaybackState(playbackState)
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        fun serviceIntent(action: String, code: Int) = PendingIntent.getService(
            this, code,
            Intent(this, KalinkaMediaService::class.java).apply { this.action = action },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val prevAction = NotificationCompat.Action(
            android.R.drawable.ic_media_previous, "Previous", serviceIntent(ACTION_PREV, 1)
        )
        val playPauseAction = if (currentIsPlaying) {
            NotificationCompat.Action(android.R.drawable.ic_media_pause, "Pause", serviceIntent(ACTION_PAUSE, 2))
        } else {
            NotificationCompat.Action(android.R.drawable.ic_media_play, "Play", serviceIntent(ACTION_PLAY, 3))
        }
        val nextAction = NotificationCompat.Action(
            android.R.drawable.ic_media_next, "Next", serviceIntent(ACTION_NEXT, 4)
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(currentTitle.ifEmpty { "Kalinka" })
            .setContentText(currentArtist)
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(currentAlbumArt)
            .setContentIntent(contentIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .addAction(prevAction)
            .addAction(playPauseAction)
            .addAction(nextAction)
            .apply {
                mediaSession?.let {
                    setStyle(MediaStyle().setMediaSession(it.sessionToken).setShowActionsInCompactView(0, 1, 2))
                }
            }
            .build()
    }

    fun postNotification() {
        // Don't resurrect after disable — async album-art callbacks can land
        // here after the WS dropped and we've already torn down.
        if (!isEnabled || mediaSession == null) return
        Log.d(TAG, "postNotification: title=$currentTitle artist=$currentArtist isPlaying=$currentIsPlaying positionMs=$currentPositionMs durationMs=$currentDurationMs hasArt=${currentAlbumArt != null}")
        startForeground(NOTIFICATION_ID, buildNotification())
        notificationVisible = true
    }

    fun hideNotification() {
        if (!notificationVisible && mediaSession == null) return
        Log.d(TAG, "hideNotification")
        stopForeground(STOP_FOREGROUND_REMOVE)
        notificationVisible = false
        releaseMediaSession()
    }

    private suspend fun loadBitmapFromUrl(url: String): Bitmap? =
        withContext(Dispatchers.IO) {
            try {
                val connection = URL(url).openConnection()
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.connect()
                BitmapFactory.decodeStream(connection.getInputStream())
            } catch (e: Exception) {
                Log.e(TAG, "albumArt: failed to load $url: $e")
                null
            }
        }
}
