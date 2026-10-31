package com.glooby.remotepanel.net

import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.TimeUnit

object HttpClient {
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    fun getString(url: String, headers: Map<String, String> = emptyMap(), proxy: String? = null): String {
        val callClient = proxyClient(proxy)
        val b = Request.Builder().url(url).header("User-Agent", "RemotePanel-Android/1.0")
        headers.forEach { (k, v) -> b.header(k, v) }
        callClient.newCall(b.build()).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            return resp.body?.string().orEmpty().ifBlank { error("空响应") }
        }
    }

    private fun proxyClient(raw: String?): OkHttpClient {
        val spec = raw?.trim().orEmpty()
        if (spec.isEmpty()) return client
        val proxy = parseProxy(spec) ?: return client
        return client.newBuilder().proxy(proxy).build()
    }

    private fun parseProxy(spec: String): Proxy? {
        val lower = spec.lowercase()
        val type = when {
            lower.startsWith("socks") -> Proxy.Type.SOCKS
            lower.startsWith("http://") || lower.startsWith("https://") -> Proxy.Type.HTTP
            else -> Proxy.Type.HTTP
        }
        val rest = spec.substringAfter("://", spec)
        val hostPort = rest.substringBefore("/").substringBefore("@").let {
            if (rest.contains("@")) rest.substringAfterLast("@") else it
        }
        val host = hostPort.substringBefore(":")
        val port = hostPort.substringAfter(":", if (type == Proxy.Type.SOCKS) "1080" else "8080").toIntOrNull()
            ?: return null
        if (host.isBlank()) return null
        val address = InetSocketAddress.createUnresolved(host, port)
        return Proxy(type, address)
    }

    fun getBytes(url: String): ByteArray {
        val req = Request.Builder().url(url).header("User-Agent", "RemotePanel-Android/1.0").build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            return resp.body?.bytes() ?: ByteArray(0)
        }
    }
}
