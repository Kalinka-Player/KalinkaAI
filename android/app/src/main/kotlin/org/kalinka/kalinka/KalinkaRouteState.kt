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
    var revision = 0L
        private set
    val current get() = renderers.firstOrNull { it.id == currentId && it.available }

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

    fun volumeRequestFinished(value: Int) {
        if (requestedVolume == value) requestedVolume = null
    }

    fun requestVolume(id: String, absolute: Int? = null, delta: Int = 0): Int? {
        val v = volume ?: return null
        if (id != current?.id || pendingId != null || !v.variable) return null
        val base = requestedVolume ?: v.current
        val target = (absolute?.toLong() ?: (base.toLong() + delta)).coerceIn(0, v.max.toLong()).toInt()
        if (target == base) return null
        requestedVolume = target
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
        clearVolume()
        revision++
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
