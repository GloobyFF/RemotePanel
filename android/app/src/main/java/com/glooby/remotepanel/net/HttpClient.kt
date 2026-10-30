package com.glooby.remotepanel.net

import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

object HttpClient {
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    fun getString(url: String, headers: Map<String, String> = emptyMap()): String {
        val b = Request.Builder().url(url).header("User-Agent", "RemotePanel-Android/1.0")
        headers.forEach { (k, v) -> b.header(k, v) }
        client.newCall(b.build()).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            return resp.body?.string().orEmpty()
        }
    }

    fun getBytes(url: String): ByteArray {
        val req = Request.Builder().url(url).header("User-Agent", "RemotePanel-Android/1.0").build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            return resp.body?.bytes() ?: ByteArray(0)
        }
    }
}
