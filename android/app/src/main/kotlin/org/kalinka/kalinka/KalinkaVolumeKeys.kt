package org.kalinka.kalinka

import android.view.KeyEvent

/** Foreground keys go to the same remote-volume command path as SystemUI. */
internal class KalinkaVolumeKeys(private val onActivity: (level: Int, max: Int) -> Unit) {
    private val pressed = mutableSetOf<Int>()

    fun dispatch(event: KeyEvent, foreground: Boolean): Boolean {
        val delta = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> 1
            KeyEvent.KEYCODE_VOLUME_DOWN -> -1
            else -> return false
        }
        // Consume the matching release even if the output disappeared while
        // held. Returning to Android here would flash its local volume panel.
        if (event.action == KeyEvent.ACTION_UP) return pressed.remove(event.keyCode)
        if (event.action != KeyEvent.ACTION_DOWN || !foreground) return false
        val state = KalinkaRoutes.state
        val id = state.current?.id ?: return false
        if (!state.playbackActive) return false
        val commands = KalinkaRoutes.commands ?: return false
        pressed.add(event.keyCode)
        if (state.volumeControllable && state.pendingId == null && !event.isCanceled) {
            commands.setVolume(id, delta = delta)
            // The UI shows the requested level at once, not after the server's
            // echo; and also at the limits, where no echo follows.
            val volume = state.volume
            val level = state.shownVolume
            if (volume != null && level != null) onActivity(level, volume.max)
        }
        // Fixed/unknown remote outputs must not change the phone's volume.
        return true
    }
}
