package org.kalinka.kalinka

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.os.Looper
import androidx.mediarouter.media.MediaRouter
import androidx.mediarouter.testing.MediaRouterTestHelper
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowMediaSession
import java.time.Duration
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [KalinkaMediaServiceTest.RecordingMediaSession::class])
class KalinkaMediaServiceTest {
    private lateinit var server: MockWebServer
    private lateinit var service: KalinkaMediaService
    private lateinit var router: MediaRouter
    private lateinit var provider: KalinkaRouteProvider
    @Volatile private var queueSocket: WebSocket? = null
    @Volatile private var deviceSocket: WebSocket? = null
    private val rendererListRequests = AtomicInteger()

    @Before fun setup() {
        RecordingMediaSession.activeOutputs.clear()
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when (request.requestUrl!!.encodedPath) {
                "/renderer/list" -> {
                    rendererListRequests.incrementAndGet()
                    MockResponse().setBody("""{"renderers":[
                        {"renderer_id":"kitchen","friendly_name":"Kitchen","status":"connected","active":true}
                    ]}""")
                }
                "/device/get_volume" -> MockResponse().setBody("""{"current_volume":25,"max_volume":70,"supported":true}""")
                "/queue/ws", "/device/ws" -> MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        if (request.requestUrl!!.encodedPath == "/queue/ws") {
                            queueSocket = webSocket
                            webSocket.send("""{"event_type":"state_changed","state":{
                                "state":"PLAYING","current_track":{"title":"Test track","duration":60}
                            }}""")
                        } else {
                            deviceSocket = webSocket
                        }
                    }
                    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                        webSocket.close(code, reason)
                    }
                })
                else -> MockResponse().setResponseCode(404)
            }
        }
        server.start()
        val context = RuntimeEnvironment.getApplication()
        router = MediaRouter.getInstance(context)
        provider = KalinkaRouteProvider(context)
        router.addProvider(provider)
        service = Robolectric.buildService(KalinkaMediaService::class.java).create().get()
        service.enable(ServerAddress("http", server.hostName, server.port))
        await { shadowOf(service).lastForegroundNotification != null }
    }

    @After fun teardown() {
        service.onDestroy()
        router.removeProvider(provider)
        provider.dispose()
        shadowOf(Looper.getMainLooper()).idle()
        MediaRouterTestHelper.resetMediaRouter()
        server.shutdown()
    }

    private fun await(condition: () -> Boolean) {
        val deadline = System.nanoTime() + 5_000_000_000
        while (!condition() && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(10))
            Thread.sleep(10)
        }
        assertTrue("Timed out waiting for notification routing", condition())
    }

    @Test fun websocketRendererEventsUpdateNotificationRoutesAndStopFallbackPolling() {
        val token = router.mediaSessionToken
        val initialRequests = rendererListRequests.get()
        queueSocket!!.send("""{"event_type":"renderers_changed","renderers":[
            {"renderer_id":"kitchen","friendly_name":"Kitchen","status":"connected"},
            {"renderer_id":"study","friendly_name":"Study","status":"connected"}
        ]}""")
        await { provider.descriptor!!.routes.size == 2 }

        queueSocket!!.send("""{"event_type":"current_renderer_changed","renderer_id":"study"}""")
        await { router.selectedRoute.name == "Study" }
        assertEquals(token, router.mediaSessionToken)

        queueSocket!!.send("""{"event_type":"renderers_changed","renderers":[
            {"renderer_id":"study","friendly_name":"Study","status":"connected"}
        ]}""")
        await { provider.descriptor!!.routes.size == 1 }
        assertEquals("Study", router.selectedRoute.name)
        await { KalinkaRoutes.state.volume?.current == 25 }
        while (server.takeRequest(0, TimeUnit.MILLISECONDS) != null) { }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(16))
        assertNull("WebSocket inventory should disable periodic HTTP polling", server.takeRequest(1, TimeUnit.SECONDS))
        assertEquals(initialRequests, rendererListRequests.get())
        assertEquals(token, router.mediaSessionToken)
    }

    @Test fun playbackNotificationIsPostedOnASilentChannel() {
        val channel = service.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(KalinkaMediaService.CHANNEL_ID)
        assertEquals(NotificationManager.IMPORTANCE_LOW, channel.importance)
        assertNull(channel.sound)
        assertFalse(channel.shouldVibrate())
        assertEquals(KalinkaMediaService.CHANNEL_ID, shadowOf(service).lastForegroundNotification!!.channelId)
    }

    @Test fun theAlertingChannelOfEarlierVersionsIsRemoved() {
        val manager = service.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel("KAI_MEDIA_CHANNEL", "Media Playback", NotificationManager.IMPORTANCE_DEFAULT))
        val upgraded = Robolectric.buildService(KalinkaMediaService::class.java).create().get()
        try {
            assertNull(manager.getNotificationChannel("KAI_MEDIA_CHANNEL"))
        } finally {
            upgraded.onDestroy()
        }
    }

    @Test fun sessionIsRemoteFromItsFirstActivation() {
        assertEquals("Kitchen", router.selectedRoute.name)
        assertTrue(RecordingMediaSession.activeOutputs.isNotEmpty())
        assertTrue("An active session advertised phone playback: ${RecordingMediaSession.activeOutputs}",
            RecordingMediaSession.activeOutputs.all { it == "remote" })
    }

    private fun assertDisconnectedWithoutRetry() {
        await { KalinkaRoutes.commands == null }
        assertNull(router.mediaSessionToken)
        assertTrue(service.getSystemService(NotificationManager::class.java).activeNotifications.isEmpty())
        assertFalse(router.selectedRoute.supportsControlCategory(KalinkaRouteProvider.category(service)))
        while (server.takeRequest(0, TimeUnit.MILLISECONDS) != null) { }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        assertNull("The notification must not reconnect itself", server.takeRequest(1, TimeUnit.SECONDS))
        assertNull(router.mediaSessionToken)
    }

    @Test fun serverClosingQueueRemovesNotificationAndDoesNotReconnect() {
        queueSocket!!.close(1001, "Server shutting down")
        assertDisconnectedWithoutRetry()
    }

    @Test fun serverClosingDeviceRemovesNotificationAndDoesNotReconnect() {
        await { deviceSocket != null }
        deviceSocket!!.close(1001, "Server shutting down")
        assertDisconnectedWithoutRetry()
    }

    @Test fun socketFailureRemovesNotificationUntilExplicitlyEnabledAgain() {
        server.shutdown()
        assertDisconnectedWithoutRetry()
        val dispatcher = server.dispatcher
        server = MockWebServer().also { it.dispatcher = dispatcher; it.start() }
        service.enable(ServerAddress("http", server.hostName, server.port))
        await { router.mediaSessionToken != null }
        assertEquals("Kitchen", router.selectedRoute.name)
        assertEquals(1, service.getSystemService(NotificationManager::class.java).activeNotifications.size)
    }

    @Test fun oldEngineDetachingCannotDisableTheNewEnginesNotification() {
        val oldOwner = Any()
        val newOwner = Any()
        service.enable(ServerAddress("http", server.hostName, server.port), oldOwner)
        val token = router.mediaSessionToken
        service.enable(ServerAddress("http", server.hostName, server.port), newOwner)
        service.disable(oldOwner)
        assertEquals(token, router.mediaSessionToken)
        assertEquals(1, service.getSystemService(NotificationManager::class.java).activeNotifications.size)
        service.disable(newOwner)
        assertNull(router.mediaSessionToken)
        assertTrue(service.getSystemService(NotificationManager::class.java).activeNotifications.isEmpty())
    }

    @Test fun disablingNotificationDeactivatesSessionBeforeDetachingRemoteOutput() {
        RecordingMediaSession.activeOutputs.clear()
        service.disable()
        assertTrue("Detaching exposed local playback on an active session: ${RecordingMediaSession.activeOutputs}",
            RecordingMediaSession.activeOutputs.none { it == "local" })
    }

    @Test fun hidingNotificationDeactivatesSessionBeforeDetachingRemoteOutput() {
        RecordingMediaSession.activeOutputs.clear()
        service.hideNotification()
        assertTrue("Detaching exposed local playback on an active session: ${RecordingMediaSession.activeOutputs}",
            RecordingMediaSession.activeOutputs.none { it == "local" })
    }

    /** Record the output visible when a session is active, at the framework boundary. */
    @Implements(MediaSession::class)
    class RecordingMediaSession : ShadowMediaSession() {
        private var active = false
        private var output = "local"

        @Implementation fun setActive(value: Boolean) {
            active = value
            if (active) activeOutputs.add(output)
        }
        @Implementation fun isActive(): Boolean = active
        @Implementation fun setPlaybackToRemote(volumeProvider: VolumeProvider) {
            output = "remote"
            if (active) activeOutputs.add(output)
        }
        @Implementation fun setPlaybackToLocal(attributes: AudioAttributes) {
            output = "local"
            if (active) activeOutputs.add(output)
        }

        companion object {
            val activeOutputs = mutableListOf<String>()
        }
    }
}
