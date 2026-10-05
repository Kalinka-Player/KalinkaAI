package org.kalinka.kalinka

import android.content.Context
import android.os.Build
import android.support.v4.media.session.MediaSessionCompat
import android.util.Log
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import androidx.mediarouter.media.MediaRouterParams
import androidx.mediarouter.media.RouteListingPreference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.io.IOException
import java.io.PrintWriter
import kotlin.coroutines.resumeWithException

/** Lives with KalinkaMediaService, never with the Activity. No new media session,
 * notification, renderer discovery, or audio playback is introduced here. */
internal class KalinkaRouting(
    context: Context,
    private val outputChanged: (Boolean) -> Unit,
) : KalinkaRoutes.Commands {
    private val routerContext = context.applicationContext
    private val router = MediaRouter.getInstance(routerContext)
    private val state get() = KalinkaRoutes.state
    private val client = OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS).build()
    private var scope: CoroutineScope? = null
    private var baseUrl: HttpUrl? = null
    private var generation = 0
    private var pushedTopology = false
    private var volumeJob: Job? = null
    private var selectionJob: Job? = null
    private var pendingVolume: Pair<String, Int>? = null
    private var volumeSyncJob: Job? = null
    private var volumeSyncDirty = false
    private var session: MediaSessionCompat? = null
    private var sessionRouteId: String? = null
    private var selectingId: String? = null
    private var detached = false
    private var hadRemoteRoute = false
    private var lostOutput = false
    private var lastCurrentId: String? = null
    private var ready = false
    private val listener: () -> Unit = { reconcile() }

    private val callback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) { reconcile() }
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) { reconcile() }
        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) { reconcile() }
        override fun onRouteSelected(router: MediaRouter, route: MediaRouter.RouteInfo, reason: Int) {
            selectingId = null
            if (route.supportsControlCategory(KalinkaRouteProvider.CATEGORY)) {
                hadRemoteRoute = true
                lostOutput = false
                detached = false
                // 1.8.1 reuses a VolumeProvider when control type/range match,
                // even if the routing controller changed. Re-associate the SAME
                // session so AndroidX supplies the new routing-controller ID.
                sessionRouteId = null
            } else if (hadRemoteRoute && !lostOutput && state.current != null && state.pendingId == null) {
                // System Stop casting detaches this phone, not shared playback.
                detached = true
            }
            reconcile()
        }
        override fun onRouteDisconnected(
            router: MediaRouter,
            disconnectedRoute: MediaRouter.RouteInfo?,
            requestedRoute: MediaRouter.RouteInfo,
            reason: Int,
        ) {
            selectingId = null
            detached = true // avoid an automatic transfer retry loop
            reconcile()
        }
    }

    fun start(host: String, port: Int) {
        if (Build.VERSION.SDK_INT >= 30) KalinkaRouteObserver.ensureRegistered(context = routerContext)
        stop()
        baseUrl = HttpUrl.Builder().scheme("http").host(host).port(port).build()
        scope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())
        detached = false
        pushedTopology = false
        KalinkaRoutes.commands = this
        router.routerParams = MediaRouterParams.Builder()
            .setMediaTransferReceiverEnabled(true)
            .setMediaTransferRestrictedToSelfProviders(true)
            .setTransferToLocalEnabled(false)
            .setOutputSwitcherEnabled(true).build()
        router.addCallback(
            MediaRouteSelector.Builder().addControlCategory(KalinkaRouteProvider.CATEGORY).build(),
            callback,
            MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY or MediaRouter.CALLBACK_FLAG_UNFILTERED_EVENTS,
        )
        KalinkaRoutes.addListener(listener)
        scope?.launch {
            while (isActive) {
                // Same server-owned list as Flutter, not network discovery. New
                // servers push it over the media service's existing queue WS.
                if (!pushedTopology) refreshRenderers()
                delay(15_000)
            }
        }
        KalinkaRoutes.changed()
    }

    fun stop() {
        generation++
        scope?.cancel()
        scope = null
        volumeJob = null
        selectionJob = null
        pendingVolume = null
        volumeSyncJob = null
        baseUrl = null
        KalinkaRoutes.removeListener(listener)
        router.removeCallback(callback)
        router.setMediaSessionCompat(null)
        // Descriptor removal crosses the platform bridge asynchronously. Drop
        // the selected controller now, before a new connection can mistake its
        // old route (and volume-control ID) for an associated remote output.
        if (router.selectedRoute.supportsControlCategory(KalinkaRouteProvider.CATEGORY)) {
            router.unselect(MediaRouter.UNSELECT_REASON_DISCONNECTED)
        }
        if (KalinkaRoutes.commands === this) {
            KalinkaRoutes.commands = null
            state.clear()
            KalinkaRoutes.changed()
        }
        router.setRouteListingPreference(null)
        session = null
        sessionRouteId = null
        selectingId = null
        hadRemoteRoute = false
        lostOutput = false
        lastCurrentId = null
        ready = false
    }

    fun setSession(value: MediaSessionCompat?) {
        if (session === value) return
        session = value
        sessionRouteId = null
        router.setMediaSessionCompat(null)
        reconcile()
    }

    fun dump(writer: PrintWriter) {
        writer.println("routing: running=${scope != null} ready=$ready detached=$detached hadRemote=$hadRemoteRoute lostOutput=$lostOutput")
        writer.println("routing: current=${state.current?.id} pending=${state.pendingId} selecting=$selectingId")
        writer.println("routing: selected=${router.selectedRoute.id} sessionRoute=$sessionRouteId")
    }

    private fun reconcile() {
        if (scope == null) return
        val current = state.current
        if (hadRemoteRoute && current == null) lostOutput = true
        if (current?.id != lastCurrentId) {
            lastCurrentId = current?.id
            detached = false
            selectingId = null
            volumeJob?.cancel()
            volumeJob = null
            pendingVolume = null
            refreshVolume()
        }
        val selected = router.selectedRoute
        val remote = selected.supportsControlCategory(KalinkaRouteProvider.CATEGORY)
        val selectedId = selected.extras?.getString(KalinkaRouteProvider.RENDERER_ID)
        // Keep the token/notification during a confirmed renderer change while
        // its descriptor crosses the AndroidX/platform bridge asynchronously.
        val newReady = !detached && current != null && remote && (selectedId == current.id || ready)
        if (newReady && session != null && sessionRouteId != selected.id) {
            router.setMediaSessionCompat(null)
            router.setMediaSessionCompat(session)
            sessionRouteId = selected.id
        }
        if (ready != newReady) {
            ready = newReady
            outputChanged(ready)
        }
        updateListing()
        // An existing dynamic session follows controller changes via provider
        // descriptors. Selecting it again would create an extra controller.
        val needsSelection = !remote || (Build.VERSION.SDK_INT < 30 && selectedId != current?.id && state.pendingId == null)
        if (!detached && current != null && needsSelection && selectingId != current.id) {
            val target = outputs().firstOrNull {
                it.extras?.getString(KalinkaRouteProvider.RENDERER_ID) == current.id && it.isEnabled
            }
            if (target != null) {
                selectingId = current.id
                router.selectRoute(target)
            }
        }
    }

    // Below API 30 the compat router binds every package's provider service,
    // so a debug and a release install also see each other's renderers.
    internal fun outputs(): List<MediaRouter.RouteInfo> = router.routes.filter {
        it.supportsControlCategory(KalinkaRouteProvider.CATEGORY) && it.provider.packageName == routerContext.packageName
    }

    private fun updateListing() {
        if (Build.VERSION.SDK_INT < 34) return
        val rows = state.renderers.associateBy { it.id }
        val items = outputs().mapNotNull { route ->
            val row = rows[route.extras?.getString(KalinkaRouteProvider.RENDERER_ID)] ?: return@mapNotNull null
            val item = RouteListingPreference.Item.Builder(route.id)
                .setSelectionBehavior(if (row.available) RouteListingPreference.Item.SELECTION_BEHAVIOR_TRANSFER else RouteListingPreference.Item.SELECTION_BEHAVIOR_NONE)
            if (!row.available) {
                item.setSubText(RouteListingPreference.Item.SUBTEXT_CUSTOM)
                    .setCustomSubtextMessage(if (!row.connected) "Offline" else "Renderer upgrade required")
            }
            row to item.build()
        }.sortedWith(compareByDescending<Pair<KalinkaRenderer, RouteListingPreference.Item>> { it.first.id == state.currentId }
            .thenBy { it.first.name })
        router.setRouteListingPreference(RouteListingPreference.Builder()
            .setSystemOrderingEnabled(false).setItems(items.map { it.second }).build())
    }

    fun queueEvent(json: JSONObject) {
        when (json.optString("event_type")) {
            "renderers_changed" -> {
                pushedTopology = true
                state.updateRenderers(parseRenderers(json.optJSONArray("renderers")))
            }
            "current_renderer_changed" -> state.confirm(json.stringOrNull("renderer_id"))
            "state_changed" -> {
                // Most of these are position updates, not a change of hold.
                if (!updatePlayback(json.optJSONObject("state"))) return
            }
            "replay_event" -> {
                if (json.optString("state_type") != "PlayQueueState") return
                val replay = json.optJSONObject("state") ?: return
                updatePlayback(replay.optJSONObject("playback_state"))
                if (replay.has("renderers") && !replay.isNull("renderers")) {
                    pushedTopology = true
                    state.updateRenderers(parseRenderers(replay.optJSONArray("renderers")))
                    state.confirm(replay.stringOrNull("current_renderer_id"))
                }
            }
            else -> return
        }
        KalinkaRoutes.changed()
    }

    // A partial state leaves the player's state out; it has not changed.
    private fun updatePlayback(playback: JSONObject?): Boolean =
        playback != null && playback.has("state") && state.updatePlayback(playback.optString("state"))

    fun deviceVolume(volume: JSONObject) {
        // These events have no renderer id. A fresh GET after a route change
        // establishes which output their values belong to across the two WSs.
        if (state.current == null) return
        // Mid-burst, an event may predate our newest request; the read that
        // ends the burst sees whatever this one carried.
        if (volumeJob?.isActive == true) return
        if (volumeSyncJob?.isActive == true) {
            volumeSyncDirty = true
            return
        }
        state.applyVolume(parseVolume(volume))
        KalinkaRoutes.changed()
    }

    override fun selectRenderer(id: String) {
        if (selectionJob?.isActive == true) return
        if (!state.requestSelection(id)) return
        val currentGeneration = generation
        volumeJob?.cancel()
        volumeJob = null
        pendingVolume = null
        KalinkaRoutes.changed()
        selectionJob = scope?.launch {
            try {
                val body = JSONObject().put("renderer_id", id).toString()
                request("renderer/active", body)
                // HTTP 200 only acknowledges the pin. Confirm actual playback
                // via the event stream or the same list Flutter reconciles.
                refreshRenderers()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w("KalinkaRouting", "Renderer transfer failed: ${e.message}")
                if (currentGeneration == generation) refreshRenderers()
            } finally {
                if (currentGeneration == generation) {
                    state.finishSelection(id)
                    KalinkaRoutes.changed()
                }
            }
        }
    }

    override fun setVolume(id: String, absolute: Int?, delta: Int) {
        if (selectionJob?.isActive == true) return
        val target = state.requestVolume(id, absolute, delta) ?: return
        pendingVolume = id to target
        if (volumeJob?.isActive == true) return
        val currentGeneration = generation
        volumeJob = scope?.launch {
            // Only one PUT at a time: cancelling/replacing in-flight slider
            // writes could let an older value arrive after the newest value.
            while (pendingVolume != null) {
                delay(50)
                val (rendererId, value) = pendingVolume ?: break
                pendingVolume = null
                if (state.current?.id != rendererId || state.pendingId != null) break
                var accepted = false
                try {
                    request("device/set_volume", "", mapOf("volume" to value.toString()))
                    accepted = true
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.w("KalinkaRouting", "Volume request failed: ${e.message}")
                } finally {
                    if (currentGeneration == generation && state.current?.id == rendererId) {
                        state.volumeRequestFinished(value, accepted)
                    }
                }
            }
            if (currentGeneration == generation && state.current?.id == id) refreshVolume()
        }
    }

    private fun refreshVolume() {
        volumeSyncJob?.cancel()
        val id = state.current?.id ?: return
        val currentGeneration = generation
        val requests = state.volumeRequests
        volumeSyncDirty = false
        volumeSyncJob = scope?.launch {
            try {
                val json = request("device/get_volume")
                // A newer request may have landed after the server answered;
                // the burst it starts ends with its own read.
                if (currentGeneration == generation && state.current?.id == id && state.volumeRequests == requests) {
                    state.applyVolume(parseVolume(json))
                    KalinkaRoutes.changed()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (currentGeneration == generation && state.current?.id == id) {
                    state.clearVolume()
                    KalinkaRoutes.changed()
                }
            }
            // A device event can cross a GET from the other socket. Read once
            // more if it did, rather than losing a change from another client.
            if (volumeSyncDirty && currentGeneration == generation && state.current?.id == id) {
                volumeSyncJob = null
                refreshVolume()
            }
        }
    }

    private suspend fun refreshRenderers() {
        val currentGeneration = generation
        val revision = state.revision
        try {
            val json = request("renderer/list")
            if (currentGeneration != generation || revision != state.revision) return
            val rows = json.optJSONArray("renderers") ?: JSONArray()
            state.updateRenderers(parseRenderers(rows))
            val current = (0 until rows.length()).map { rows.getJSONObject(it) }.firstOrNull { it.optBoolean("active") }
            state.confirm(current?.stringOrNull("renderer_id"))
            KalinkaRoutes.changed()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.d("KalinkaRouting", "Renderer list unavailable: ${e.message}")
        }
    }

    private suspend fun request(path: String, body: String? = null, query: Map<String, String> = emptyMap()): JSONObject {
        val url = checkNotNull(baseUrl).newBuilder().addPathSegments(path).apply {
            query.forEach { (key, value) -> addQueryParameter(key, value) }
        }.build()
        val builder = Request.Builder().url(url)
        if (body != null) builder.put(body.toRequestBody("application/json".toMediaType()))
        return suspendCancellableCoroutine { continuation ->
            val call = client.newCall(builder.build())
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) { continuation.resumeWithException(e) }
                override fun onResponse(call: Call, response: Response) {
                    val result = runCatching {
                        response.use {
                            check(it.isSuccessful) { "${it.code} $path" }
                            val text = it.body?.string().orEmpty()
                            if (text.isBlank()) JSONObject() else JSONObject(text)
                        }
                    }
                    continuation.resumeWith(result)
                }
            })
        }
    }

    companion object {
        internal fun parseRenderers(rows: JSONArray?): List<KalinkaRenderer> =
            (0 until (rows?.length() ?: 0)).map { index ->
                val row = rows!!.getJSONObject(index)
                KalinkaRenderer(row.optString("renderer_id"), row.optString("friendly_name"),
                    row.optString("status") == "connected", row.optBoolean("compatible", true))
            }
        internal fun parseVolume(json: JSONObject) = KalinkaVolume(
            json.optInt("current_volume"), json.optInt("max_volume"), json.optBoolean("supported"))
        private fun JSONObject.stringOrNull(key: String) = if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
    }
}
