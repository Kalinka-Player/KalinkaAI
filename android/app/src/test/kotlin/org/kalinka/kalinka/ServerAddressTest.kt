package org.kalinka.kalinka

import org.junit.Assert.assertEquals
import org.junit.Test

class ServerAddressTest {
    private val lan = ServerAddress("http", "nas.local", 8000)
    private val demo = ServerAddress("https", "demo.test", 443)

    @Test fun socketsFollowTheServerScheme() {
        assertEquals("ws://nas.local:8000/queue/ws", lan.webSocketUrl("/queue/ws"))
        assertEquals("wss://demo.test:443/device/ws", demo.webSocketUrl("/device/ws"))
    }

    @Test fun artworkPathsResolveOnTheServerAndWholeUrlsStayAsTheyAre() {
        assertEquals("http://nas.local:8000/art/1.jpg", lan.resolve("/art/1.jpg"))
        assertEquals("https://demo.test:443/art/1.jpg", demo.resolve("art/1.jpg"))
        assertEquals("https://cdn.test/a.jpg", demo.resolve("https://cdn.test/a.jpg"))
    }
}
