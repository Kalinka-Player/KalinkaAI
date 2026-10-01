package org.kalinka.kalinka

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Looper
import androidx.mediarouter.media.MediaControlIntent
import androidx.mediarouter.media.MediaRouteProvider
import androidx.mediarouter.media.MediaRouter
import org.json.JSONArray
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

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 34])
class KalinkaRouteProviderTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private lateinit var provider: KalinkaRouteProvider
    private val selections = mutableListOf<String>()
    private val volumes = mutableListOf<Triple<String, Int?, Int>>()
    private val state get() = KalinkaRoutes.state

    @Before fun setup() {
        state.clear()
        state.updateRenderers(listOf(
            KalinkaRenderer("speaker-1", "Kitchen", true),
            KalinkaRenderer("speaker-2", "Study", true),
            KalinkaRenderer("offline", "Attic", false),
            KalinkaRenderer("old", "Old renderer", true, compatible = false),
        ))
        state.confirm("speaker-1")
        state.applyVolume(KalinkaVolume(25, 70, true))
        state.updatePlayback("PLAYING")
        KalinkaRoutes.commands = object : KalinkaRoutes.Commands {
            override fun selectRenderer(id: String) {
                if (state.requestSelection(id)) selections.add(id)
            }
            override fun setVolume(id: String, absolute: Int?, delta: Int) {
                volumes.add(Triple(id, absolute, delta))
            }
        }
        provider = KalinkaRouteProvider(context)
    }

    @After fun teardown() {
        provider.dispose()
        KalinkaRoutes.commands = null
        state.clear()
    }

    private fun controller(id: String = "speaker-1") = provider.onCreateDynamicGroupRouteController(
        id, MediaRouteProvider.RouteControllerOptions.Builder().setClientPackageName(context.packageName).build(),
    )!!

    @Test fun manifestExportsBothProviderInterfacesAndEnablesTransfer() {
        val component = ComponentName(context, KalinkaRouteProviderService::class.java)
        val info = context.packageManager.getServiceInfo(component, 0)
        assertTrue(info.exported)
        val media = context.packageManager.getServiceInfo(ComponentName(context, KalinkaMediaService::class.java), 0)
        assertEquals(media.processName, info.processName)
        for (action in listOf("android.media.MediaRouteProviderService", "android.media.MediaRoute2ProviderService")) {
            assertTrue(context.packageManager.queryIntentServices(Intent(action).setPackage(context.packageName), 0)
                .any { it.serviceInfo.name == component.className })
        }
        val receiver = context.packageManager.getReceiverInfo(ComponentName(context,
            "androidx.mediarouter.media.MediaTransferReceiver"), PackageManager.GET_META_DATA)
        assertFalse(receiver.exported)
    }

    @Test fun descriptorsCarryRendererIdentityAndOnlyKnownVolumeCapabilities() {
        val rows = provider.descriptor!!.routes
        assertEquals(4, rows.size)
        assertEquals("Kitchen", rows[0].name)
        assertEquals("speaker-1", rows[0].extras!!.getString(KalinkaRouteProvider.RENDERER_ID))
        assertEquals(MediaRouter.RouteInfo.DEVICE_TYPE_REMOTE_SPEAKER, rows[0].deviceType)
        assertTrue(rows[0].controlFilters.any { it.hasCategory(KalinkaRouteProvider.CATEGORY) })
        assertTrue(rows[0].controlFilters.any { it.hasCategory(MediaControlIntent.CATEGORY_REMOTE_PLAYBACK) })
        assertEquals(70, rows[0].volumeMax)
        assertEquals(25, rows[0].volume)
        assertEquals(MediaRouter.RouteInfo.PLAYBACK_VOLUME_VARIABLE, rows[0].volumeHandling)
        assertEquals(MediaRouter.RouteInfo.PLAYBACK_VOLUME_FIXED, rows[1].volumeHandling)
        assertEquals(0, rows[1].volumeMax)
        assertFalse(rows[2].isEnabled)
        assertFalse(rows[3].isEnabled)
    }

    @Test fun routeAndMemberCallbacksNeverDuplicateTransferOrStopSharedPlayback() {
        val output = controller("speaker-2")
        output.onSelect()
        output.onUpdateMemberRoutes(mutableListOf("speaker-2"))
        assertEquals(listOf("speaker-2"), selections)
        state.confirm("speaker-2")
        KalinkaRoutes.changed()
        val member = provider.onCreateRouteController("speaker-2")!!
        member.onSelect()
        output.onUnselect(MediaRouter.UNSELECT_REASON_STOPPED)
        output.onRelease()
        member.onRelease()
        assertEquals(listOf("speaker-2"), selections)
        assertEquals("speaker-2", state.currentId)
        assertTrue(volumes.isEmpty())
    }

    @Test fun volumeCallbacksTargetCurrentOutputAndControllerEventsUpdateDescriptors() {
        val output = controller()
        output.onSelect()
        output.onSetVolume(30)
        output.onUpdateVolume(-1)
        assertEquals(listOf(Triple("speaker-1", 30, 0), Triple("speaker-1", null, -1)), volumes)
        state.confirm("speaker-2")
        state.applyVolume(KalinkaVolume(18, 50, true))
        KalinkaRoutes.changed()
        output.onSetVolume(20)
        assertEquals(Triple("speaker-2", 20, 0), volumes.last())
        assertTrue(selections.isEmpty())
        assertEquals(18, provider.descriptor!!.routes[1].volume)
        state.applyVolume(KalinkaVolume(50, 50, false))
        KalinkaRoutes.changed()
        assertEquals(MediaRouter.RouteInfo.PLAYBACK_VOLUME_FIXED, provider.descriptor!!.routes[1].volumeHandling)
    }

    @Test fun volumeIsFixedWhilePlaybackDoesNotHoldTheRenderer() {
        KalinkaRoutes.changed()
        assertEquals(MediaRouter.RouteInfo.PLAYBACK_VOLUME_VARIABLE, provider.descriptor!!.routes[0].volumeHandling)
        assertEquals(MediaRouter.RouteInfo.PLAYBACK_VOLUME_FIXED, provider.descriptor!!.routes[1].volumeHandling)
        state.updatePlayback("STOPPED")
        KalinkaRoutes.changed()
        assertEquals(MediaRouter.RouteInfo.PLAYBACK_VOLUME_FIXED, provider.descriptor!!.routes[0].volumeHandling)
    }

    @Test fun failedTransferAndDisappearanceClearPublishedConnectingState() {
        val output = controller("speaker-2")
        output.onSelect()
        KalinkaRoutes.changed()
        assertEquals(MediaRouter.RouteInfo.CONNECTION_STATE_CONNECTING, provider.descriptor!!.routes[1].connectionState)
        state.finishSelection("speaker-2")
        KalinkaRoutes.changed()
        assertEquals(MediaRouter.RouteInfo.CONNECTION_STATE_DISCONNECTED, provider.descriptor!!.routes[1].connectionState)
        assertEquals(MediaRouter.RouteInfo.CONNECTION_STATE_CONNECTED, provider.descriptor!!.routes[0].connectionState)
        state.clear()
        KalinkaRoutes.changed()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(provider.descriptor!!.routes.isEmpty())
    }

    @Test fun foreignClientsCannotCreateKalinkaControllers() {
        val options = MediaRouteProvider.RouteControllerOptions.Builder().setClientPackageName("other.app").build()
        assertNull(provider.onCreateDynamicGroupRouteController("speaker-1", options))
        assertNull(provider.onCreateRouteController("speaker-1", options))
        assertTrue(selections.isEmpty())
    }

    @Test fun emptyBridgeOptionsCreateMemberVolumeControllersBeforeAndAfterTransfer() {
        // MR2 supplies EMPTY options for a dynamic session's member. Its
        // package name is an empty string, even for our own app's session.
        val options = MediaRouteProvider.RouteControllerOptions.Builder().build()
        assertEquals("", options.clientPackageName)
        val first = provider.onCreateRouteController("speaker-1", options)!!
        first.onSetVolume(32)
        first.onUpdateVolume(-1)
        assertEquals(listOf(Triple("speaker-1", 32, 0), Triple("speaker-1", null, -1)), volumes)

        state.confirm("speaker-2")
        KalinkaRoutes.changed()
        val second = provider.onCreateRouteController("speaker-2", options)!!
        second.onSetVolume(19)
        assertEquals(Triple("speaker-2", 19, 0), volumes.last())
        assertTrue(selections.isEmpty())
        assertNotNull(provider.onCreateDynamicGroupRouteController("speaker-2"))
    }

    @Test fun parsesExistingControllerWireFormatIncludingFixedVolume() {
        val rows = KalinkaRouting.parseRenderers(JSONArray("""[
            {"renderer_id":"r-kitchen","friendly_name":"Kitchen","status":"connected","active":true},
            {"renderer_id":"r-old","friendly_name":"Old","status":"connected","compatible":false}
        ]"""))
        assertEquals("r-kitchen", rows[0].id)
        assertTrue(rows[0].available)
        assertFalse(rows[1].available)
        assertFalse(KalinkaRouting.parseVolume(JSONObject("""{"current_volume":100,"max_volume":100,"supported":false}""")).variable)
    }
}
