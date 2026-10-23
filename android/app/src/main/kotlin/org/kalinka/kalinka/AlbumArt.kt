package org.kalinka.kalinka

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.graphics.scale
import kotlin.math.roundToInt

/**
 * Decodes cover art to fit within [maxEdge] px, subsampling while decoding so
 * a full-size cover never sits in memory.
 */
fun decodeAlbumArt(bytes: ByteArray, maxEdge: Int): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    val longest = maxOf(bounds.outWidth, bounds.outHeight)
    if (longest <= 0) return null
    val options = BitmapFactory.Options().apply { inSampleSize = artSampleSize(longest, maxEdge) }
    val sampled = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
    val scale = maxEdge.toFloat() / maxOf(sampled.width, sampled.height)
    if (scale >= 1f) return sampled
    val scaled = sampled.scale(
        (sampled.width * scale).roundToInt().coerceAtLeast(1),
        (sampled.height * scale).roundToInt().coerceAtLeast(1),
    )
    if (scaled !== sampled) sampled.recycle()
    return scaled
}

/** Largest power of two that subsamples [longestEdge] without going below [maxEdge]. */
internal fun artSampleSize(longestEdge: Int, maxEdge: Int): Int {
    var sample = 1
    while (longestEdge / (sample * 2) >= maxEdge) sample *= 2
    return sample
}
