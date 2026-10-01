package org.kalinka.kalinka

/** Controller facts, independent of Android. All access is on the main thread. */
internal data class KalinkaRenderer(
    val id: String,
    val name: String,
    val connected: Boolean,
    val compatible: Boolean = true,
) {
    val available get() = connected && compatible
}

internal data class KalinkaVolume(val current: Int, val max: Int, val supported: Boolean) {
    val variable get() = supported && max > 0
}

internal class KalinkaRouteState {
    var renderers: List<KalinkaRenderer> = emptyList()
        private set
    var currentId: String? = null
        private set
    var pendingId: String? = null
        private set
    var volume: KalinkaVolume? = null
        private set
    private var requestedVolume: Int? = null
    /** Counts volume requests, so a read can tell whether one overtook it. */
    var volumeRequests = 0L
        private set
    /** The newest requested level, else the reported one. */
    val shownVolume get() = volume?.let { requestedVolume ?: it.current }
    var revision = 0L
        private set
    /** Only playback holds the renderer; its volume means nothing otherwise. */
    var playbackActive = false
        private set
    val current get() = renderers.firstOrNull { it.id == currentId && it.available }
    val volumeControllable get() = volume?.variable == true && playbackActive

    /** @return whether the renderer's hold changed. */
    fun updatePlayback(playerState: String): Boolean {
        val active = playerState in ACTIVE_STATES
        if (active == playbackActive) return false
        playbackActive = active
        return true
    }

    fun updateRenderers(rows: List<KalinkaRenderer>) {
        revision++
        renderers = rows.filter { it.id.isNotEmpty() }.distinctBy { it.id }
        if (current == null) clearVolume()
        if (renderers.none { it.id == pendingId && it.available }) pendingId = null
    }

    fun confirm(id: String?) {
        revision++
        if (currentId != id) clearVolume()
        currentId = id
        // A server event is authoritative, including another client's choice.
        pendingId = null
    }

    /** Only user intent produces a command. Replaying selection is a no-op. */
    fun requestSelection(id: String): Boolean {
        if (id == currentId || pendingId != null || renderers.none { it.id == id && it.available }) {
            return false
        }
        pendingId = id
        requestedVolume = null
        return true
    }

    fun finishSelection(id: String) {
        if (pendingId == id) pendingId = null
    }

    fun applyVolume(value: KalinkaVolume?) {
        volume = value?.let { it.copy(max = it.max.coerceAtLeast(0), current = it.current.coerceIn(0, it.max.coerceAtLeast(0))) }
        // Never discard controller updates for a timed 'echo suppression' window.
        if (requestedVolume == volume?.current) requestedVolume = null
    }

    /** @param accepted the server took the level, so it now reports it; the
     *  next relative change counts from there, not from an older read. */
    fun volumeRequestFinished(value: Int, accepted: Boolean) {
        if (accepted) volume = volume?.let { it.copy(current = value.coerceIn(0, it.max)) }
        if (requestedVolume == value) requestedVolume = null
    }

    fun requestVolume(id: String, absolute: Int? = null, delta: Int = 0): Int? {
        val v = volume ?: return null
        if (id != current?.id || pendingId != null || !volumeControllable) return null
        val base = requestedVolume ?: v.current
        val target = (absolute?.toLong() ?: (base.toLong() + delta)).coerceIn(0, v.max.toLong()).toInt()
        if (target == base) return null
        requestedVolume = target
        volumeRequests++
        return target
    }

    fun clearVolume() {
        volume = null
        requestedVolume = null
    }

    fun clear() {
        renderers = emptyList()
        currentId = null
        pendingId = null
        playbackActive = false
        clearVolume()
        revision++
    }

    private companion object {
        val ACTIVE_STATES = setOf("PLAYING", "BUFFERING", "PAUSED")
    }
}

/** The exported provider never starts networking or Flutter. The existing
 * foreground media service supplies the server's already-discovered topology. */
internal object KalinkaRoutes {
    val state = KalinkaRouteState()
    interface Commands {
        fun selectRenderer(id: String)
        fun setVolume(id: String, absolute: Int? = null, delta: Int = 0)
    }
    var commands: Commands? = null
    private val listeners = mutableSetOf<() -> Unit>()
    fun addListener(listener: () -> Unit) { listeners.add(listener); listener() }
    fun removeListener(listener: () -> Unit) { listeners.remove(listener) }
    fun changed() { listeners.toList().forEach { it() } }
}
