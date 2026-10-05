package org.kalinka.kalinka

/**
 * Where the Kalinka server answers, and the URLs that reach it.
 *
 * [scheme] is `http` on a local network, or `https` for a server behind TLS
 * such as the public demo; its sockets follow it as `ws` or `wss`.
 */
internal data class ServerAddress(val scheme: String, val host: String, val port: Int) {
    val webSocketScheme: String get() = if (scheme == "https") "wss" else "ws"

    fun webSocketUrl(path: String): String = "$webSocketScheme://$host:$port$path"

    /** [path] on the server, unless it already names a whole URL. */
    fun resolve(path: String): String {
        if (path.startsWith("http")) return path
        val sep = if (path.startsWith("/")) "" else "/"
        return "$scheme://$host:$port$sep$path"
    }
}
