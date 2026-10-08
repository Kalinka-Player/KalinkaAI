package org.kalinka.kalinka

import android.content.Context
import android.content.ContextWrapper
import android.content.IntentFilter
import android.os.Bundle
import android.os.Looper
import android.support.v4.media.session.MediaSessionCompat
import android.view.KeyEvent
import androidx.media.VolumeProviderCompat
import androidx.mediarouter.media.MediaRouteDescriptor
import androidx.mediarouter.media.MediaRouteProvider
import androidx.mediarouter.media.MediaRouteProviderDescriptor
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
import org.robolectric.util.ReflectionHelpers
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
    private val category get() = KalinkaRouteProvider.category(RuntimeEnvironment.getApplication())
    private val writes = CopyOnWriteArrayList<RecordedRequest>()
    @Volatile private var active = "kitchen"
    @Volatile private var singleRenderer = false
    @Volatile private var volume = 25
    @Volatile private var transferFails = false
    @Volatile private var delayTransfer = false
    @Volatile private var readDelayMs = 0L
    private var ready = false

    @Before fun setup() {
        val context = RuntimeEnvironment.getApplication()
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.requestUrl!!.encodedPath
                if (request.method == "PUT") writes.add(request)
                return when (path) {
                    "/renderer/list" -> MockResponse().setBody(if (singleRenderer) """{"renderers":[
                        {"renderer_id":"kitchen","friendly_name":"Kitchen","status":"connected","active":true}
                    ]}""" else """{"renderers":[
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
                    "/device/get_volume" -> {
                        // Reads now, answers late: a slow network's stale reply.
                        val level = volume
                        Thread.sleep(readDelayMs)
                        MockResponse().setBody("""{"current_volume":$level,"max_volume":70,"supported":true}""")
                    }
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
        routing.start(ServerAddress("http", server.hostName, server.port))
        routing.queueEvent(JSONObject("""{"event_type":"state_changed","state":{"state":"PLAYING"}}"""))
        await { ready && KalinkaRoutes.state.volume?.current == 25 }
    }

    @Test fun onlyAPlayerStateChangesTheHoldAndAReplayCarriesIt() {
        assertTrue(KalinkaRoutes.state.playbackActive)
        routing.queueEvent(JSONObject("""{"event_type":"state_changed","state":{"position":1000}}"""))
        assertTrue(KalinkaRoutes.state.playbackActive)
        routing.queueEvent(JSONObject("""{"event_type":"replay_event","state_type":"PlayQueueState",
            "state":{"playback_state":{"state":"STOPPED"}}}"""))
        assertFalse(KalinkaRoutes.state.playbackActive)
    }

    @After fun teardown() {
        routing.stop()
        router.removeProvider(provider)
        provider.dispose()
        shadowOf(Looper.getMainLooper()).idle()
        MediaRouterTestHelper.resetMediaRouter()
        server.shutdown()
    }

    private fun pause(ms: Long) {
        val deadline = System.nanoTime() + ms * 1_000_000
        while (System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(10))
            Thread.sleep(10)
        }
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

    @Test fun singleRendererAssociatesAnEarlySessionAndReselectingItKeepsRemotePlayback() {
        routing.stop()
        singleRenderer = true
        ready = false
        var remoteVolume: VolumeProviderCompat? = null
        val session = object : MediaSessionCompat(RuntimeEnvironment.getApplication(), "single-output-test") {
            override fun setPlaybackToRemote(provider: VolumeProviderCompat) {
                remoteVolume = provider
                super.setPlaybackToRemote(provider)
            }
            override fun setPlaybackToLocal(stream: Int) {
                remoteVolume = null
                super.setPlaybackToLocal(stream)
            }
        }
        try {
            routing.start(ServerAddress("http", server.hostName, server.port))
            routing.setSession(session)
            routing.queueEvent(JSONObject("""{"event_type":"state_changed","state":{"state":"PLAYING"}}"""))
            await { ready && remoteVolume?.maxVolume == 70 }
            assertEquals("Kitchen", router.selectedRoute.name)
            assertEquals(1, provider.descriptor!!.routes.size)
            val token = router.mediaSessionToken
            assertEquals(session.sessionToken, token)

            repeat(3) {
                router.selectRoute(router.selectedRoute)
                routing.queueEvent(JSONObject("""{"event_type":"current_renderer_changed","renderer_id":"kitchen"}"""))
                shadowOf(Looper.getMainLooper()).idle()
                assertTrue(ready)
                assertNotNull(remoteVolume)
                assertEquals(token, router.mediaSessionToken)
            }
            assertTrue(writes.isEmpty())
        } finally {
            routing.setSession(null)
            session.release()
        }
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

    @Test fun aKeyHoldNeverStepsBackWhileReadsAnswerLate() {
        readDelayMs = 150
        val keys = KalinkaVolumeKeys { _, _ -> }
        repeat(12) { i ->
            assertTrue(keys.dispatch(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_VOLUME_UP, i), true))
            pause(60)
        }
        assertTrue(keys.dispatch(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_VOLUME_UP), true))
        await { KalinkaRoutes.state.volume?.current == 37 }
        val sent = writes.map { it.requestUrl!!.queryParameter("volume")!!.toInt() }
        assertEquals(sent.sorted().distinct(), sent)
        assertEquals(37, sent.last())
    }

    @Test fun sliderAndHardwareRequestsCoalesceAndUseRealRange() {
        val options = MediaRouteProvider.RouteControllerOptions.Builder().build()
        val member = provider.onCreateRouteController("kitchen", options)!!
        member.onSetVolume(30)
        member.onSetVolume(30)
        member.onUpdateVolume(1)
        var indicators = 0
        val keys = KalinkaVolumeKeys { _, _ -> indicators++ }
        assertTrue(keys.dispatch(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_VOLUME_UP), true))
        assertTrue(keys.dispatch(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_VOLUME_UP), true))
        await { writes.size == 1 && KalinkaRoutes.state.volume?.current == 32 }
        assertEquals(1, indicators)
        assertEquals("32", writes.single().requestUrl!!.queryParameter("volume"))
        assertEquals("/device/set_volume", writes.single().requestUrl!!.encodedPath)
        pause(200) // let the burst end with its read; mid-burst events are skipped
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
        routing.start(ServerAddress("http", server.hostName, server.port))
        await { ready && router.selectedRoute.name == "Study" }
        assertTrue(writes.isEmpty())
    }

    @Test fun stoppingReleasesTheSelectedRouteBeforeAnotherConnectionCanUseIt() {
        assertTrue(router.selectedRoute.supportsControlCategory(category))
        routing.stop()
        // Descriptor removal is asynchronous. A new connection must not see
        // the old selection in the meantime and treat it as a ready output.
        assertFalse(router.selectedRoute.supportsControlCategory(category))
        assertNull(router.mediaSessionToken)
        assertTrue(writes.isEmpty())
        routing.start(ServerAddress("http", server.hostName, server.port))
        await { ready && router.selectedRoute.name == "Kitchen" }
        assertTrue(writes.isEmpty())
    }

    @Test fun passiveObserverSurvivesStopsWithoutKeepingDiscoveryOrRoutesAlive() {
        val context = RuntimeEnvironment.getApplication()
        repeat(3) {
            KalinkaRouteObserver.ensureRegistered(context)
            routing.stop()
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(1, ReflectionHelpers.callStaticMethod<Int>(
                MediaRouter::class.java, "getGlobalCallbackCount"))
            assertNull(provider.discoveryRequest)
            assertTrue(provider.descriptor!!.routes.isEmpty())
            assertNull(KalinkaRoutes.commands)
            assertNull(router.mediaSessionToken)
            routing.start(ServerAddress("http", server.hostName, server.port))
            await { ready && router.selectedRoute.name == "Kitchen" }
        }
        assertTrue(writes.isEmpty())
    }

    @Test fun anotherInstallsRoutesForTheSameRenderersAreNeitherSelectedNorListed() {
        val context = RuntimeEnvironment.getApplication()
        routing.stop()
        ready = false
        shadowOf(Looper.getMainLooper()).idle()
        // Registered while ours are gone, so its routes come first in the router.
        val other = OtherInstallProvider(context)
        router.addProvider(other)
        try {
            routing.start(ServerAddress("http", server.hostName, server.port))
            await { ready && router.selectedRoute.name == "Kitchen" }
            val theirs = router.routes.filter { it.provider.packageName == OTHER_PACKAGE }
            assertEquals(2, theirs.size)
            assertTrue(theirs.none { it.supportsControlCategory(category) })
            assertEquals(context.packageName, router.selectedRoute.provider.packageName)
            assertEquals("Kitchen", router.selectedRoute.name)
            assertEquals(0, other.selections)
            assertEquals(listOf("Kitchen", "Study"), routing.outputs().map { it.name })
            assertTrue(routing.outputs().all { it.provider.packageName == context.packageName })
            assertTrue(writes.isEmpty())
        } finally {
            router.removeProvider(other)
        }
    }

    private class OtherInstallProvider(app: Context) : MediaRouteProvider(object : ContextWrapper(app) {
        override fun getPackageName() = OTHER_PACKAGE
    }) {
        var selections = 0

        init {
            val theirCategory = KalinkaRouteProvider.category(context)
            descriptor = MediaRouteProviderDescriptor.Builder().addRoutes(
                listOf("kitchen" to "Kitchen", "study" to "Study").map { (id, name) ->
                    MediaRouteDescriptor.Builder(id, name)
                        .addControlFilter(IntentFilter().apply { addCategory(theirCategory) })
                        .setExtras(Bundle().apply { putString(KalinkaRouteProvider.RENDERER_ID, id) })
                        .setPlaybackType(MediaRouter.RouteInfo.PLAYBACK_TYPE_REMOTE)
                        .build()
                }).build()
        }

        override fun onCreateRouteController(routeId: String): RouteController = object : RouteController() {
            override fun onSelect() { selections++ }
        }
    }

    private companion object {
        const val OTHER_PACKAGE = "org.kalinka.kalinka.other"
    }
}
