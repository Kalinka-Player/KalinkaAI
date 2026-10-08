package org.kalinka.kalinka

import android.content.Context
import android.os.VibrationAttributes
import android.os.VibrationEffect.Composition.PRIMITIVE_CLICK
import android.os.VibrationEffect.Composition.PRIMITIVE_QUICK_FALL
import android.os.VibrationEffect.Composition.PRIMITIVE_THUD
import android.os.VibrationEffect.Composition.PRIMITIVE_TICK
import android.os.Vibrator
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
class KalinkaHapticsTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val vibrator: Vibrator get() = context.getSystemService(Vibrator::class.java)

    private fun supporting(vararg primitives: Int) =
        shadowOf(vibrator).setSupportedPrimitives(primitives.toList())

    private fun lastUsage() =
        (shadowOf(vibrator).vibrationAttributesFromLastVibration as VibrationAttributes).usage

    private fun lastPlayed() =
        shadowOf(vibrator).primitiveSegmentsInPrimitiveEffects.orEmpty().map { it.id }

    @Config(sdk = [34])
    @Test fun swipeCommitsPlayTheirCompositionsAsTouchFeedback() {
        supporting(PRIMITIVE_QUICK_FALL, PRIMITIVE_CLICK, PRIMITIVE_TICK, PRIMITIVE_THUD)
        val haptics = KalinkaHaptics.of(context)

        assertTrue(haptics.corkPop())
        assertEquals(VibrationAttributes.USAGE_TOUCH, lastUsage())
        assertEquals(listOf(PRIMITIVE_QUICK_FALL, PRIMITIVE_CLICK), lastPlayed())

        assertTrue(haptics.delete())
        assertEquals(VibrationAttributes.USAGE_TOUCH, lastUsage())
        assertEquals(listOf(PRIMITIVE_TICK, PRIMITIVE_THUD), lastPlayed())
    }

    @Config(sdk = [34])
    @Test fun aMissingPrimitiveReportsNothingPlayedRatherThanStayingSilent() {
        supporting(PRIMITIVE_CLICK, PRIMITIVE_TICK)

        assertFalse(KalinkaHaptics.of(context).corkPop())
        assertFalse(KalinkaHaptics.of(context).delete())
        assertTrue(lastPlayed().isEmpty())
    }

    @Config(sdk = [34])
    @Test fun noVibratorReportsNothingPlayed() {
        supporting(PRIMITIVE_QUICK_FALL, PRIMITIVE_CLICK)
        shadowOf(vibrator).setHasVibrator(false)

        assertFalse(KalinkaHaptics.of(context).corkPop())
        assertFalse(KalinkaHaptics(null).corkPop())
    }

    @Config(sdk = [30])
    @Test fun beforeAndroid12NothingPlaysSoTheCallerFallsBack() {
        assertFalse(KalinkaHaptics.of(context).corkPop())
        assertFalse(KalinkaHaptics(vibrator).delete())
    }
}
