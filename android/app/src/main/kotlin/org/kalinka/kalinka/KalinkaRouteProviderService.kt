package org.kalinka.kalinka

import android.content.Context
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Bundle
import android.os.Build
import androidx.mediarouter.media.MediaControlIntent
import androidx.mediarouter.media.MediaRouteDescriptor
import androidx.mediarouter.media.MediaRouteProvider
import androidx.mediarouter.media.MediaRouteProviderDescriptor
import androidx.mediarouter.media.MediaRouteProviderService
import androidx.mediarouter.media.MediaRouter
import java.util.UUID

class KalinkaRouteProviderService : MediaRouteProviderService() {
    private var routes: KalinkaRouteProvider? = null
    override fun onCreateMediaRouteProvider(): MediaRouteProvider =
        KalinkaRouteProvider(this).also { routes = it }

    override fun onDestroy() {
        routes?.dispose()
        super.onDestroy()
    }
}

internal class KalinkaRouteProvider(context: Context) : MediaRouteProvider(context) {
    companion object {
        const val RENDERER_ID = "org.kalinka.kalinka.RENDERER_ID"

        // Per application ID: below API 30 AndroidX binds every package's
        // provider, and a debug install publishes the same renderers.
        fun category(context: Context) = "${context.packageName}.RENDERER"
    }

    // No PLAY/ENQUEUE actions: Kalinka transfers its existing queue; it is
    // not a generic RemotePlaybackClient URL receiver for other apps.
    private val filters = listOf(IntentFilter().apply {
        addCategory(category(context))
        addCategory(MediaControlIntent.CATEGORY_REMOTE_PLAYBACK)
    })
    private val controllers = mutableSetOf<OutputController>()
    private val listener: () -> Unit = { publish() }

    init { KalinkaRoutes.addListener(listener) }
    fun dispose() { KalinkaRoutes.removeListener(listener); controllers.clear() }

    private fun route(row: KalinkaRenderer): MediaRouteDescriptor {
        val state = KalinkaRoutes.state
        // /device volume describes the CURRENT output only. Unknown outputs
        // remain fixed until selected and queried; never invent a 0..100 range.
        val volume = state.volume.takeIf { row.id == state.current?.id }
        return MediaRouteDescriptor.Builder(row.id, row.name.ifBlank { row.id })
            .addControlFilters(filters)
            .setExtras(Bundle().apply { putString(RENDERER_ID, row.id) })
            .setVisibilityRestricted(setOf(context.packageName))
            .setDeviceType(MediaRouter.RouteInfo.DEVICE_TYPE_REMOTE_SPEAKER)
            .setPlaybackType(MediaRouter.RouteInfo.PLAYBACK_TYPE_REMOTE)
            .setPlaybackStream(AudioManager.STREAM_MUSIC)
            .setEnabled(row.available && KalinkaRoutes.commands != null)
            .setDescription(when {
                !row.connected -> "Offline"
                !row.compatible -> "Renderer upgrade required"
                else -> "Kalinka output"
            })
            .setConnectionState(when (row.id) {
                state.pendingId -> MediaRouter.RouteInfo.CONNECTION_STATE_CONNECTING
                state.current?.id -> MediaRouter.RouteInfo.CONNECTION_STATE_CONNECTED
                else -> MediaRouter.RouteInfo.CONNECTION_STATE_DISCONNECTED
            })
            .setVolumeHandling(if (volume?.variable == true && state.playbackActive) MediaRouter.RouteInfo.PLAYBACK_VOLUME_VARIABLE else MediaRouter.RouteInfo.PLAYBACK_VOLUME_FIXED)
            .setVolumeMax(volume?.max ?: 0)
            .setVolume(volume?.current ?: 0)
            .setCanDisconnect(true)
            .build()
    }

    private fun publish() {
        // MR2 before API 34 has no disabled-row presentation (it discards
        // MediaRouteDescriptor.enabled). Do not offer offline/unsupported
        // devices as usable destinations on those versions.
        val rows = KalinkaRoutes.state.renderers.filter {
            Build.VERSION.SDK_INT !in 30..33 || it.available
        }.map(::route)
        descriptor = MediaRouteProviderDescriptor.Builder()
            .setSupportsDynamicGroupRoute(true).addRoutes(rows).build()
        controllers.toList().forEach { it.publish(rows) }
    }

    override fun onCreateDynamicGroupRouteController(
        initialMemberRouteId: String,
        options: RouteControllerOptions,
    ): DynamicGroupRouteController? {
        if (!acceptsClient(options)) return null
        if (KalinkaRoutes.commands == null || KalinkaRoutes.state.renderers.none { it.id == initialMemberRouteId && it.available }) return null
        return OutputController(initialMemberRouteId).also { controllers.add(it) }
    }

    override fun onCreateDynamicGroupRouteController(initialMemberRouteId: String): DynamicGroupRouteController? =
        onCreateDynamicGroupRouteController(initialMemberRouteId, RouteControllerOptions.Builder().build())

    // AndroidX uses static controllers before API 30, even when the provider
    // supports dynamic sessions. Selection there is reconciled by KalinkaRouting.
    override fun onCreateRouteController(routeId: String, options: RouteControllerOptions): RouteController? {
        if (!acceptsClient(options)) return null
        return onCreateRouteController(routeId)
    }

    private fun acceptsClient(options: RouteControllerOptions): Boolean {
        // The MR2 bridge creates member controllers with EMPTY options, whose
        // client package is "", not null. Rejecting it leaves a visible slider
        // with no controller to receive onSetRouteVolume.
        val client = options.clientPackageName
        return client.isEmpty() || client == context.packageName
    }

    override fun onCreateRouteController(routeId: String): RouteController? {
        if (KalinkaRoutes.commands == null || KalinkaRoutes.state.renderers.none { it.id == routeId && it.available }) return null
        return object : RouteController() {
            override fun onSelect() {
                // On API 30+ the dynamic controller owns selection; AndroidX
                // also creates these static controllers for its members.
                if (Build.VERSION.SDK_INT < 30) KalinkaRoutes.commands?.selectRenderer(routeId)
            }
            override fun onSetVolume(volume: Int) { KalinkaRoutes.commands?.setVolume(routeId, absolute = volume) }
            override fun onUpdateVolume(delta: Int) { KalinkaRoutes.commands?.setVolume(routeId, delta = delta) }
        }
    }

    /** A single-member dynamic session lets the bridge update its selected
     * renderer and volume in place, after asynchronous controller confirmation.
     * Grouping and member removal are deliberately never advertised. */
    private inner class OutputController(private val initialId: String) : DynamicGroupRouteController() {
        private val sessionId = "kalinka-${UUID.randomUUID()}"
        private var selected = false
        private var lastRoute: MediaRouteDescriptor? = null

        override fun onSelect() {
            selected = true
            KalinkaRoutes.commands?.selectRenderer(initialId)
            publish(KalinkaRoutes.state.renderers.map(::route))
        }

        override fun onUpdateMemberRoutes(routeIds: MutableList<String>?) {
            routeIds?.singleOrNull()?.let { KalinkaRoutes.commands?.selectRenderer(it) }
        }
        override fun onAddMemberRoute(routeId: String) = Unit
        override fun onRemoveMemberRoute(routeId: String) = Unit
        override fun onSetVolume(volume: Int) {
            KalinkaRoutes.state.current?.id?.let { KalinkaRoutes.commands?.setVolume(it, absolute = volume) }
        }
        override fun onUpdateVolume(delta: Int) {
            KalinkaRoutes.state.current?.id?.let { KalinkaRoutes.commands?.setVolume(it, delta = delta) }
        }
        // Release means this Android client detached. It never changes the pin,
        // stops the shared queue, or sends a command to the renderer.
        override fun onRelease() { selected = false; controllers.remove(this) }

        fun publish(rows: List<MediaRouteDescriptor>) {
            if (!selected) return
            val state = KalinkaRoutes.state
            val current = rows.firstOrNull { it.id == state.current?.id }
            val connecting = rows.firstOrNull { it.id == state.pendingId }
            val member = current ?: connecting
            if (member == null) {
                lastRoute?.let {
                    notifyDynamicRoutesChanged(MediaRouteDescriptor.Builder(it).setEnabled(false).build(), emptyList())
                }
                return
            }
            val group = MediaRouteDescriptor.Builder(sessionId, member.name)
                .addControlFilters(filters)
                .setExtras(member.extras)
                .setDeviceType(member.deviceType)
                .setPlaybackType(MediaRouter.RouteInfo.PLAYBACK_TYPE_REMOTE)
                .setPlaybackStream(AudioManager.STREAM_MUSIC)
                .setConnectionState(member.connectionState)
                .setVolumeHandling(member.volumeHandling)
                .setVolumeMax(member.volumeMax).setVolume(member.volume)
                .setCanDisconnect(true).build()
            lastRoute = group
            notifyDynamicRoutesChanged(group, rows.map { row ->
                DynamicRouteDescriptor.Builder(row)
                    .setSelectionState(if (row.id == member.id) {
                        if (current != null) DynamicRouteDescriptor.SELECTED else DynamicRouteDescriptor.SELECTING
                    } else DynamicRouteDescriptor.UNSELECTED)
                    .setIsGroupable(false).setIsUnselectable(false)
                    .setIsTransferable(row.isEnabled && row.id != member.id && state.pendingId == null)
                    .build()
            })
        }
    }
}
