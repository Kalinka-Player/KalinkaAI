package org.kalinka.kalinka

import android.content.Intent
import android.media.MediaRoute2ProviderService
import android.os.Looper
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers

/** Exercises the AndroidX provider bridge, without SystemUI or a system binder. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 34])
class KalinkaRouteBridgeTest {
    private lateinit var service: KalinkaRouteProviderService
    private lateinit var bridge: MediaRoute2ProviderService
    private val state get() = KalinkaRoutes.state
    private val selections = mutableListOf<String>()

    @Before fun setup() {
        state.clear()
        state.updateRenderers(listOf(KalinkaRenderer("kitchen", "Kitchen", true)))
        state.confirm("kitchen")
        KalinkaRoutes.commands = object : KalinkaRoutes.Commands {
            override fun selectRenderer(id: String) {
                if (state.requestSelection(id)) selections.add(id)
            }
            override fun setVolume(id: String, absolute: Int?, delta: Int) = Unit
        }
        service = Robolectric.buildService(KalinkaRouteProviderService::class.java).create().get()
        service.onBind(Intent(MediaRoute2ProviderService.SERVICE_INTERFACE))
        // AndroidX keeps the framework service adapter private. All session
        // operations and assertions below use its public framework API.
        val impl: Any = ReflectionHelpers.getField(service, "mImpl")
        bridge = ReflectionHelpers.getField(impl, "mMR2ProviderServiceAdapter")
        shadowOf(Looper.getMainLooper()).idle()
    }

    @After fun teardown() {
        bridge.allSessionInfo.toList().forEach {
            bridge.onReleaseSession(MediaRoute2ProviderService.REQUEST_ID_NONE, it.id)
        }
        service.onDestroy()
        KalinkaRoutes.commands = null
        state.clear()
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test fun singleRendererHasNamedRemoteSessionWithoutTransferTargets() {
        bridge.onCreateSession(MediaRoute2ProviderService.REQUEST_ID_NONE, service.packageName, "kitchen", null)
        shadowOf(Looper.getMainLooper()).idle()
        val session = bridge.allSessionInfo.single()
        assertEquals("Kitchen", session.name)
        assertEquals(listOf("kitchen"), session.selectedRoutes)
        assertTrue(session.transferableRoutes.isEmpty())
        assertTrue(session.selectableRoutes.isEmpty())
        assertTrue(session.deselectableRoutes.isEmpty())
        assertEquals(service.packageName, session.clientPackageName)
        assertTrue(selections.isEmpty())

        state.updatePlayback("PLAYING")
        state.applyVolume(KalinkaVolume(25, 70, true))
        KalinkaRoutes.changed()
        shadowOf(Looper.getMainLooper()).idle()
        val updated = bridge.allSessionInfo.single()
        assertEquals(session.id, updated.id)
        assertEquals("Kitchen", updated.name)
        assertEquals(listOf("kitchen"), updated.selectedRoutes)
        assertEquals(25, updated.volume)
        assertEquals(70, updated.volumeMax)
        assertTrue(selections.isEmpty())
    }

    @Test fun addingAndRemovingAnotherRendererKeepsTheCurrentSession() {
        bridge.onCreateSession(MediaRoute2ProviderService.REQUEST_ID_NONE, service.packageName, "kitchen", null)
        shadowOf(Looper.getMainLooper()).idle()
        val sessionId = bridge.allSessionInfo.single().id
        val kitchen = state.renderers.single()

        state.updateRenderers(listOf(kitchen, KalinkaRenderer("study", "Study", true)))
        KalinkaRoutes.changed()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(listOf("study"), bridge.allSessionInfo.single().transferableRoutes)

        state.updateRenderers(listOf(kitchen))
        KalinkaRoutes.changed()
        bridge.onTransferToRoute(MediaRoute2ProviderService.REQUEST_ID_NONE, sessionId, "kitchen")
        shadowOf(Looper.getMainLooper()).idle()
        val session = bridge.allSessionInfo.single()
        assertEquals(sessionId, session.id)
        assertEquals("Kitchen", session.name)
        assertEquals(listOf("kitchen"), session.selectedRoutes)
        assertTrue(session.transferableRoutes.isEmpty())
        assertTrue(selections.isEmpty())
    }
}
