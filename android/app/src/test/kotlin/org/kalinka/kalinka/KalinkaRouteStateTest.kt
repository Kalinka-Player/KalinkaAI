package org.kalinka.kalinka

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class KalinkaRouteStateTest {
    private val kitchen = KalinkaRenderer("r-kitchen", "Kitchen", true)
    private val study = KalinkaRenderer("r-study", "Study", true)
    private lateinit var state: KalinkaRouteState

    @Before fun setup() {
        state = KalinkaRouteState()
        state.updateRenderers(listOf(kitchen, study))
        state.confirm(kitchen.id)
        state.applyVolume(KalinkaVolume(30, 80, true))
    }

    @Test fun confirmedSelectionAndRepeatedCallbacksDoNotIssueTransfers() {
        assertFalse(state.requestSelection(kitchen.id))
        assertTrue(state.requestSelection(study.id))
        assertFalse(state.requestSelection(study.id))
        assertEquals(kitchen.id, state.current?.id)
        state.confirm(study.id)
        assertNull(state.pendingId)
        assertFalse(state.requestSelection(study.id))
        assertNull(state.volume)
    }

    @Test fun failedTransferRestoresConfirmedOutputAndClearsConnecting() {
        state.requestSelection(study.id)
        state.finishSelection(study.id)
        assertNull(state.pendingId)
        assertEquals(kitchen.id, state.current?.id)
        assertTrue(state.requestSelection(study.id))
    }

    @Test fun newerExternalSelectionWinsOverOldRequestCompletion() {
        state.requestSelection(study.id)
        state.confirm(study.id)
        state.confirm(kitchen.id)
        state.finishSelection(study.id)
        assertEquals(kitchen.id, state.current?.id)
        assertNull(state.pendingId)
        assertFalse(state.requestSelection(kitchen.id))
    }

    @Test fun unavailableAndIncompatibleRenderersCannotBeSelected() {
        state.updateRenderers(listOf(kitchen, study.copy(connected = false)))
        assertFalse(state.requestSelection(study.id))
        state.updateRenderers(listOf(kitchen, study.copy(compatible = false)))
        assertFalse(state.requestSelection(study.id))
        assertFalse(state.requestSelection("missing"))
    }

    @Test fun disappearingRendererClearsVolumeAndPendingConnection() {
        state.requestSelection(study.id)
        state.updateRenderers(emptyList())
        assertNull(state.current)
        assertNull(state.volume)
        assertNull(state.pendingId)
        assertNull(state.requestVolume(kitchen.id, absolute = 40))
    }

    @Test fun absoluteAndRelativeRequestsClampCoalesceAndAccumulate() {
        assertEquals(31, state.requestVolume(kitchen.id, delta = 1))
        assertEquals(32, state.requestVolume(kitchen.id, delta = 1))
        assertNull(state.requestVolume(kitchen.id, absolute = 32))
        assertEquals(80, state.requestVolume(kitchen.id, delta = Int.MAX_VALUE))
        assertNull(state.requestVolume(kitchen.id, delta = 1))
        assertEquals(0, state.requestVolume(kitchen.id, absolute = -100))
    }

    @Test fun lateEchoDoesNotSendCommandsOrLosePendingVolumeIntent() {
        state.requestVolume(kitchen.id, absolute = 40)
        state.applyVolume(KalinkaVolume(31, 80, true))
        assertEquals(31, state.volume?.current)
        assertNull(state.requestVolume(kitchen.id, absolute = 40))
        state.applyVolume(KalinkaVolume(40, 80, true))
        assertNull(state.requestVolume(kitchen.id, absolute = 40))
        // Another client changes volume immediately, with no suppression timer.
        state.applyVolume(KalinkaVolume(12, 80, true))
        assertEquals(13, state.requestVolume(kitchen.id, delta = 1))
    }

    @Test fun volumeIsRejectedDuringTransferAndForOldOrFixedOutputs() {
        assertNull(state.requestVolume(study.id, absolute = 40))
        state.requestSelection(study.id)
        assertNull(state.requestVolume(kitchen.id, absolute = 40))
        state.confirm(study.id)
        assertNull(state.requestVolume(study.id, absolute = 40))
        state.applyVolume(KalinkaVolume(100, 100, false))
        assertNull(state.requestVolume(study.id, delta = -1))
        state.applyVolume(KalinkaVolume(0, 0, true))
        assertNull(state.requestVolume(study.id, absolute = 50))
    }

    @Test fun malformedRangesAreSafeAndConfirmedValuesAreClamped() {
        state.applyVolume(KalinkaVolume(150, 80, true))
        assertEquals(80, state.volume?.current)
        state.applyVolume(KalinkaVolume(-5, -1, true))
        assertEquals(0, state.volume?.max)
        assertEquals(0, state.volume?.current)
        assertNull(state.requestVolume(kitchen.id, delta = 1))
    }

    @Test fun reconnectAndTopologyEventsInvalidateOldSnapshots() {
        val revision = state.revision
        state.confirm(study.id)
        assertTrue(state.revision > revision)
        state.clear()
        assertTrue(state.renderers.isEmpty())
        assertNull(state.currentId)
        assertNull(state.volume)
        assertNull(state.pendingId)
    }
}
