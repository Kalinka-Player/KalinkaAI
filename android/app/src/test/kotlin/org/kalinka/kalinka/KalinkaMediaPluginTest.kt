package org.kalinka.kalinka

import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.ServiceConnection
import android.os.Looper
import androidx.mediarouter.testing.MediaRouterTestHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class KalinkaMediaPluginTest {
    private lateinit var context: BindingContext
    private lateinit var plugin: KalinkaMediaPlugin

    @Before fun setup() {
        context = BindingContext(RuntimeEnvironment.getApplication())
        plugin = KalinkaMediaPlugin()
        ReflectionHelpers.setField(plugin, "context", context)
    }

    @After fun teardown() {
        call("disableNotification")
        shadowOf(Looper.getMainLooper()).idle()
        MediaRouterTestHelper.resetMediaRouter()
    }

    private fun call(method: String): Any? {
        var answer: Any? = null
        plugin.onMethodCall(MethodCall(method, mapOf("host" to "localhost", "port" to 8000)),
            object : MethodChannel.Result {
                override fun success(result: Any?) { answer = result }
                override fun error(code: String, message: String?, details: Any?) { fail(message) }
                override fun notImplemented() { fail("Method not implemented") }
            })
        return answer
    }

    @Test fun swipeHapticsAnswerWhetherTheyPlayedSoDartCanFallBack() {
        assertEquals(false, call("hapticCorkPop"))
        assertEquals(false, call("hapticDelete"))
    }

    @Test fun disableCancelsPendingBindingAndItsQueuedEnable() {
        call("enableNotification")
        call("disableNotification")
        assertEquals(1, context.binds)
        assertEquals(1, context.unbinds)

        val service = Robolectric.buildService(KalinkaMediaService::class.java).create().get()
        try {
            // Even a late delivery after unbind must not execute the old enable.
            context.connection!!.onServiceConnected(ComponentName(context, KalinkaMediaService::class.java),
                service.onBind(null))
            assertNull(KalinkaRoutes.commands)
        } finally {
            service.onDestroy()
        }
    }

    @Test fun repeatedEnableWhileBindingDoesNotRegisterDuplicateConnections() {
        repeat(3) { call("enableNotification") }
        assertEquals(1, context.binds)
        call("disableNotification")
        assertEquals(1, context.unbinds)
        call("enableNotification")
        assertEquals(2, context.binds)
    }

    private class BindingContext(base: Context) : ContextWrapper(base) {
        var binds = 0
        var unbinds = 0
        var connection: ServiceConnection? = null
        override fun bindService(intent: Intent, connection: ServiceConnection, flags: Int): Boolean {
            binds++
            this.connection = connection
            return true
        }
        override fun unbindService(connection: ServiceConnection) { unbinds++ }
    }
}
