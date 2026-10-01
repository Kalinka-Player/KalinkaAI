package org.kalinka.kalinka

import android.content.Context
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter

/** Keeps AndroidX's platform controller bookkeeping alive between connections. */
internal object KalinkaRouteObserver {
    private val callback = object : MediaRouter.Callback() {}
    private var router: MediaRouter? = null

    fun ensureRegistered(context: Context) {
        // AndroidX 1.8.1 removes released controllers only in MR2's async
        // onStop callback. Removing its last callback during disconnect loses
        // that acknowledgement and can reuse a stale controller on reconnect.
        // An empty selector with no discovery flags keeps those acknowledgements
        // flowing without discovering outputs, publishing routes, or networking.
        router = MediaRouter.getInstance(context.applicationContext).also {
            it.addCallback(MediaRouteSelector.EMPTY, callback, 0)
        }
    }
}
