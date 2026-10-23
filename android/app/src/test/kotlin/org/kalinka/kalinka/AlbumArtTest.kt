package org.kalinka.kalinka

import android.graphics.Bitmap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.ByteArrayOutputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AlbumArtTest {
    private fun png(width: Int, height: Int): ByteArray = ByteArrayOutputStream().also {
        Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, it)
    }.toByteArray()

    @Test fun largeCoverIsDecodedToFitTheLimit() {
        val art = decodeAlbumArt(png(3000, 2000), 960)!!
        assertEquals(960, art.width)
        assertEquals(640, art.height)
    }

    @Test fun smallCoverKeepsItsSize() {
        val art = decodeAlbumArt(png(300, 300), 960)!!
        assertEquals(300, art.width)
        assertEquals(300, art.height)
    }

    @Test fun undecodableBodyGivesNoArt() {
        assertNull(decodeAlbumArt("<html>not found</html>".toByteArray(), 960))
    }

    @Test fun subsamplesByPowersOfTwoWithoutGoingBelowTheLimit() {
        assertEquals(1, artSampleSize(1919, 960))
        assertEquals(2, artSampleSize(1920, 960))
        assertEquals(2, artSampleSize(3000, 960))
        assertEquals(4, artSampleSize(3840, 960))
    }
}
