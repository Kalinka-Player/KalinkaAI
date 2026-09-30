package org.kalinka.kalinka

import android.view.KeyEvent
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 34])
class KalinkaVolumeKeysTest {
    private val state get() = KalinkaRoutes.state
    private val requests = mutableListOf<Int>()
    private var indicators = 0
    private val keys = KalinkaVolumeKeys { indicators++ }
    private fun down(code: Int = KeyEvent.KEYCODE_VOLUME_UP, repeat: Int = 0) =
        KeyEvent(0, 0, KeyEvent.ACTION_DOWN, code, repeat)
    private fun up(code: Int = KeyEvent.KEYCODE_VOLUME_UP) = KeyEvent(KeyEvent.ACTION_UP, code)

    @Before fun setup() {
        state.clear()
        state.updateRenderers(listOf(KalinkaRenderer("speaker", "Speaker", true)))
        state.confirm("speaker")
        state.applyVolume(KalinkaVolume(25, 70, true))
        KalinkaRoutes.commands = object : KalinkaRoutes.Commands {
            override fun selectRenderer(id: String) = Unit
            override fun setVolume(id: String, absolute: Int?, delta: Int) {
                assertEquals("speaker", id)
                state.requestVolume(id, absolute, delta)?.let { requests.add(it) }
            }
        }
    }

    @After fun teardown() {
        KalinkaRoutes.commands = null
        state.clear()
    }

    @Test fun foregroundPressHoldAndReleaseAdjustRemoteVolumeOncePerDown() {
        assertTrue(keys.dispatch(down(), true))
        assertTrue(keys.dispatch(down(repeat = 1), true))
        assertTrue(keys.dispatch(up(), true))
        assertTrue(keys.dispatch(down(KeyEvent.KEYCODE_VOLUME_DOWN), true))
        assertTrue(keys.dispatch(up(KeyEvent.KEYCODE_VOLUME_DOWN), true))
        assertEquals(listOf(26, 27, 26), requests)
        assertEquals(3, indicators)
    }

    @Test fun limitStillShowsIndicatorWithoutWritingAndFixedOutputDoesNotChangePhoneVolume() {
        state.applyVolume(KalinkaVolume(70, 70, true))
        assertTrue(keys.dispatch(down(), true))
        assertTrue(keys.dispatch(up(), true))
        assertEquals(1, indicators)
        assertTrue(requests.isEmpty())
        state.applyVolume(KalinkaVolume(70, 70, false))
        assertTrue(keys.dispatch(down(), true))
        assertTrue(keys.dispatch(up(), true))
        assertEquals(1, indicators)
        assertTrue(requests.isEmpty())
    }

    @Test fun backgroundAndUnconnectedKeysRemainWithAndroid() {
        assertFalse(keys.dispatch(down(), false))
        assertFalse(keys.dispatch(up(), false))
        assertFalse(keys.dispatch(down(KeyEvent.KEYCODE_POWER), true))
        state.clear()
        assertFalse(keys.dispatch(down(), true))
        assertTrue(requests.isEmpty())
        assertEquals(0, indicators)
    }

    @Test fun disappearanceDuringPressStillConsumesRelease() {
        assertTrue(keys.dispatch(down(), true))
        state.clear()
        assertTrue(keys.dispatch(up(), false))
        assertFalse(keys.dispatch(up(), false))
        assertEquals(listOf(26), requests)
    }
}
