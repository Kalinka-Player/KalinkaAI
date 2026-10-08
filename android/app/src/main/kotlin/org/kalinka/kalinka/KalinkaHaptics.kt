package org.kalinka.kalinka

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.VibrationEffect.Composition.PRIMITIVE_CLICK
import android.os.VibrationEffect.Composition.PRIMITIVE_QUICK_FALL
import android.os.VibrationEffect.Composition.PRIMITIVE_THUD
import android.os.VibrationEffect.Composition.PRIMITIVE_TICK
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * The two swipe-commit compositions, played as touch feedback so the phone's
 * haptics setting governs them.
 *
 * Each call returns whether the effect was played. It is false below
 * Android 12 and on hardware missing a primitive, where Android would stay
 * silent instead, so the caller can fall back to a standard haptic.
 */
internal class KalinkaHaptics(private val vibrator: Vibrator?) {

    companion object {
        private const val TAG = "KalinkaHaptics"

        fun of(context: Context) = KalinkaHaptics(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(VibratorManager::class.java)?.defaultVibrator
            } else {
                null
            }
        )
    }

    private class Step(val primitive: Int, val scale: Float, val delayMs: Int)

    fun corkPop(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
        play(Step(PRIMITIVE_QUICK_FALL, 1f, 0), Step(PRIMITIVE_CLICK, 0.7f, 50))

    fun delete(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
        play(Step(PRIMITIVE_TICK, 0.4f, 0), Step(PRIMITIVE_THUD, 0.9f, 30))

    @RequiresApi(Build.VERSION_CODES.S)
    private fun play(vararg steps: Step): Boolean {
        val vibrator = vibrator ?: return false
        val primitives = steps.map { it.primitive }.toIntArray()
        if (!vibrator.hasVibrator() || !vibrator.areAllPrimitivesSupported(*primitives)) return false
        val effect = VibrationEffect.startComposition().apply {
            steps.forEach { addPrimitive(it.primitive, it.scale, it.delayMs) }
        }.compose()
        return try {
            vibrateAsTouch(vibrator, effect)
            true
        } catch (e: RuntimeException) {
            Log.w(TAG, "Haptic composition failed", e)
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun vibrateAsTouch(vibrator: Vibrator, effect: VibrationEffect) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
        } else {
            // Android 12 classes sonification vibrations as touch feedback.
            @Suppress("DEPRECATION")
            vibrator.vibrate(
                effect,
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).build()
            )
        }
    }
}
