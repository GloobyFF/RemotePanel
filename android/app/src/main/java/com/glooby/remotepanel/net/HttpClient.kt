package com.glooby.remotepanel.net

import okhttp3.Dns
import okhttp3.MediaType.Companion.toMediaType
import java.net.Inet4Address
import java.net.InetAddress
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

object HttpClient {
    const val BROWSER_UA =
        "Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"

    /**
     * Try IPv4 addresses first. On networks with broken IPv6 (seen on the emulator: v6 connects time
     * out after 10 s), dual-stack CDNs otherwise stall each image before falling back to v4.
     */
    private val ipv4First = object : Dns {
        override fun lookup(hostname: String): List<InetAddress> =
            Dns.SYSTEM.lookup(hostname).sortedBy { if (it is Inet4Address) 0 else 1 }
    }

    private val client: OkHttpClient = OkHttpClient.Builder()
        .dns(ipv4First)
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .callTimeout(40, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    /** Shorter timeouts for images so one dead host does not tie up Glide's threads. */
    val images: OkHttpClient = client.newBuilder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(25, TimeUnit.SECONDS)
        .build()

    private val proxied = ConcurrentHashMap<String, OkHttpClient>()

    fun getString(url: String, headers: Map<String, String> = emptyMap(), proxy: String? = null): String {
        val b = Request.Builder().url(url).header("User-Agent", BROWSER_UA)
        headers.forEach { (k, v) -> b.header(k, v) }
        via(client, proxy).newCall(b.build()).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            return resp.body?.string().orEmpty().ifBlank { error("空响应") }
        }
    }

    fun postJson(url: String, body: String, headers: Map<String, String> = emptyMap(), proxy: String? = null): String {
        val b = Request.Builder().url(url)
            .header("User-Agent", BROWSER_UA)
            .post(body.toRequestBody("application/json".toMediaType()))
        headers.forEach { (k, v) -> b.header(k, v) }
        via(client, proxy).newCall(b.build()).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            return resp.body?.string().orEmpty()
        }
    }

    fun getBytes(url: String): ByteArray {
        val req = Request.Builder().url(url).header("User-Agent", BROWSER_UA).build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            return resp.body?.bytes() ?: ByteArray(0)
        }
    }

    /** [base] routed through [spec] (socks5h://host:port or http://host:port); [base] itself when blank. */
    fun via(base: OkHttpClient, spec: String?): OkHttpClient {
        val s = spec?.trim().orEmpty()
        if (s.isEmpty()) return base
        val p = parseProxy(s) ?: return base
        val key = "${System.identityHashCode(base)}|$s"
        return proxied.getOrPut(key) { base.newBuilder().proxy(p).build() }
    }

    private fun parseProxy(spec: String): Proxy? {
        val lower = spec.lowercase()
        val type = if (lower.startsWith("socks")) Proxy.Type.SOCKS else Proxy.Type.HTTP
        val rest = spec.substringAfter("://", spec)
        val hostPort = rest.substringBefore("/").let { if (it.contains("@")) it.substringAfterLast("@") else it }
        val host = hostPort.substringBefore(":")
        val port = hostPort.substringAfter(":", if (type == Proxy.Type.SOCKS) "1080" else "8080").toIntOrNull()
            ?: return null
        if (host.isBlank()) return null
        return Proxy(type, InetSocketAddress.createUnresolved(host, port))
    }
}
