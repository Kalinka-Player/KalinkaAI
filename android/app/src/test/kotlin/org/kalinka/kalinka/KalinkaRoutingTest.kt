package org.kalinka.kalinka

import android.os.Looper
import android.support.v4.media.session.MediaSessionCompat
import android.view.KeyEvent
import androidx.media.VolumeProviderCompat
import androidx.mediarouter.media.MediaRouteProvider
import androidx.mediarouter.media.MediaRouter
import androidx.mediarouter.testing.MediaRouterTestHelper
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.concurrent.CopyOnWriteArrayList
import java.time.Duration

/** Exercises async server operations through a real AndroidX compat router.
 * The platform MediaRouter2 binder/system UI still needs a device test. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class KalinkaRoutingTest {
    private lateinit var server: MockWebServer
    private lateinit var routing: KalinkaRouting
    private lateinit var provider: KalinkaRouteProvider
    private lateinit var router: MediaRouter
    private val writes = CopyOnWriteArrayList<RecordedRequest>()
    @Volatile private var active = "kitchen"
    @Volatile private var volume = 25
    @Volatile private var transferFails = false
    @Volatile private var delayTransfer = false
    private var ready = false

    @Before fun setup() {
        val context = RuntimeEnvironment.getApplication()
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.requestUrl!!.encodedPath
                if (request.method == "PUT") writes.add(request)
                return when (path) {
                    "/renderer/list" -> MockResponse().setBody("""{"renderers":[
                        {"renderer_id":"kitchen","friendly_name":"Kitchen","status":"connected","active":${active == "kitchen"}},
                        {"renderer_id":"study","friendly_name":"Study","status":"connected","active":${active == "study"}}
                    ]}""")
                    "/renderer/active" -> {
                        if (delayTransfer) Thread.sleep(200)
                        if (transferFails) MockResponse().setResponseCode(409).setBody("{}") else {
                            active = JSONObject(request.body.clone().readUtf8()).getString("renderer_id")
                            MockResponse().setBody("{}")
                        }
                    }
                    "/device/get_volume" -> MockResponse().setBody("""{"current_volume":$volume,"max_volume":70,"supported":true}""")
                    "/device/set_volume" -> {
                        volume = request.requestUrl!!.queryParameter("volume")!!.toInt()
                        MockResponse().setBody("{}")
                    }
                    else -> MockResponse().setResponseCode(404)
                }
            }
        }
        server.start()
        router = MediaRouter.getInstance(context)
        provider = KalinkaRouteProvider(context)
        router.addProvider(provider) // test-only; production discovers the service
        routing = KalinkaRouting(context) { ready = it }
        routing.start(server.hostName, server.port)
        await { ready && KalinkaRoutes.state.volume?.current == 25 }
    }

    @After fun teardown() {
        routing.stop()
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
        assertTrue("Timed out: current=${KalinkaRoutes.state.currentId}, pending=${KalinkaRoutes.state.pendingId}, selected=${router.selectedRoute}, writes=${writes.map { it.path }}", condition())
    }

    @Test fun systemTransferUsesExistingEndpointOnceAndKeepsMediaSession() {
        var remoteVolume: VolumeProviderCompat? = null
        val session = object : MediaSessionCompat(RuntimeEnvironment.getApplication(), "routing-test") {
            override fun setPlaybackToRemote(provider: VolumeProviderCompat) {
                remoteVolume = provider
                super.setPlaybackToRemote(provider)
            }
        }
        val token = session.sessionToken
        routing.setSession(session)
        assertEquals(70, remoteVolume!!.maxVolume)
        val target = router.routes.first { it.name == "Study" }
        router.selectRoute(target)
        await { KalinkaRoutes.state.currentId == "study" && router.selectedRoute.name == "Study" }
        assertEquals(token, session.sessionToken)
        assertNotNull(remoteVolume)
        assertEquals(listOf("/renderer/active"), writes.map { it.requestUrl!!.encodedPath })
        assertEquals("study", JSONObject(writes[0].body.clone().readUtf8()).getString("renderer_id"))
        assertEquals(0, writes.count { it.requestUrl!!.encodedPath.startsWith("/queue") })
        routing.setSession(null)
        session.release()
    }

    @Test fun anotherClientAndFlutterEventsMoveAndroidWithoutAnyWrite() {
        active = "study"
        routing.queueEvent(JSONObject("""{"event_type":"current_renderer_changed","renderer_id":"study"}"""))
        await { router.selectedRoute.name == "Study" }
        assertTrue(writes.isEmpty())
        assertTrue(ready)
        routing.queueEvent(JSONObject("""{"event_type":"current_renderer_changed","renderer_id":"study"}"""))
        assertTrue(writes.isEmpty())
    }

    @Test fun refusedTransferKeepsOldDestinationAndClearsTransientState() {
        transferFails = true
        router.selectRoute(router.routes.first { it.name == "Study" })
        await { writes.size == 1 && KalinkaRoutes.state.pendingId == null }
        assertEquals("kitchen", KalinkaRoutes.state.currentId)
        assertEquals("Kitchen", router.selectedRoute.name)
        assertTrue(ready)
        assertEquals(1, writes.size)
    }

    @Test fun repeatedSelectionWhileHttpIsPendingIsCoalesced() {
        delayTransfer = true
        repeat(5) { routing.selectRenderer("study") }
        await { KalinkaRoutes.state.currentId == "study" }
        assertEquals(1, writes.size)
    }

    @Test fun sliderAndHardwareRequestsCoalesceAndUseRealRange() {
        val options = MediaRouteProvider.RouteControllerOptions.Builder().build()
        val member = provider.onCreateRouteController("kitchen", options)!!
        member.onSetVolume(30)
        member.onSetVolume(30)
        member.onUpdateVolume(1)
        var indicators = 0
        val keys = KalinkaVolumeKeys { indicators++ }
        assertTrue(keys.dispatch(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_VOLUME_UP), true))
        assertTrue(keys.dispatch(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_VOLUME_UP), true))
        await { writes.size == 1 && KalinkaRoutes.state.volume?.current == 32 }
        assertEquals(1, indicators)
        assertEquals("32", writes.single().requestUrl!!.queryParameter("volume"))
        assertEquals("/device/set_volume", writes.single().requestUrl!!.encodedPath)
        routing.deviceVolume(JSONObject("""{"current_volume":12,"max_volume":70,"supported":true}"""))
        await { router.selectedRoute.volume == 12 }
        assertEquals(1, writes.size)
    }

    @Test fun stopCastingDetachesWithoutStoppingOrRepinningSharedPlayback() {
        router.unselect(MediaRouter.UNSELECT_REASON_STOPPED)
        await { !ready }
        assertEquals("kitchen", KalinkaRoutes.state.currentId)
        assertTrue(writes.isEmpty())
        routing.deviceVolume(JSONObject("""{"current_volume":12,"max_volume":70,"supported":true}"""))
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(ready)
        assertTrue(writes.isEmpty())
    }

    @Test fun rendererDisappearanceAndServerFallbackDoNotBecomeUserDetach() {
        active = "study"
        routing.queueEvent(JSONObject("""{"event_type":"renderers_changed","renderers":[
            {"renderer_id":"study","friendly_name":"Study","status":"connected"}
        ]}"""))
        routing.queueEvent(JSONObject("""{"event_type":"current_renderer_changed","renderer_id":"study"}"""))
        await { ready && router.selectedRoute.name == "Study" }
        assertTrue(writes.isEmpty())
    }

    @Test fun reconnectSeedsRoutesAgainWithoutReissuingSelection() {
        routing.stop()
        assertNull(KalinkaRoutes.state.currentId)
        active = "study"
        routing.start(server.hostName, server.port)
        await { ready && router.selectedRoute.name == "Study" }
        assertTrue(writes.isEmpty())
    }
}
