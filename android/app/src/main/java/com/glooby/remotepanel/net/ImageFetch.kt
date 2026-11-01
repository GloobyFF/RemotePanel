package com.glooby.remotepanel.net

import android.content.Context
import com.bumptech.glide.Glide
import com.bumptech.glide.Priority
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.HttpException
import com.bumptech.glide.load.Options
import com.bumptech.glide.load.data.DataFetcher
import com.bumptech.glide.load.model.GlideUrl
import com.bumptech.glide.load.model.ModelLoader
import com.bumptech.glide.load.model.ModelLoaderFactory
import com.bumptech.glide.load.model.MultiModelLoaderFactory
import com.glooby.remotepanel.data.Prefs
import okhttp3.Call
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.io.InputStream

/**
 * Glide image downloads over OkHttp: browser User-Agent, Referer where a CDN checks it,
 * and one retry through the configured proxy when the direct connection fails.
 */
object ImageFetch {
    fun install(context: Context) {
        Glide.get(context).registry.replace(GlideUrl::class.java, InputStream::class.java, Factory())
    }

    private fun referer(host: String): String? = when {
        host.endsWith("hdslb.com") -> "https://www.bilibili.com/"
        host.endsWith("qhimgs1.com") -> "https://image.so.com/"
        else -> null
    }

    private class Factory : ModelLoaderFactory<GlideUrl, InputStream> {
        override fun build(multiFactory: MultiModelLoaderFactory): ModelLoader<GlideUrl, InputStream> = Loader()
        override fun teardown() = Unit
    }

    private class Loader : ModelLoader<GlideUrl, InputStream> {
        override fun buildLoadData(model: GlideUrl, width: Int, height: Int, options: Options) =
            ModelLoader.LoadData(model, Fetcher(model))

        override fun handles(model: GlideUrl): Boolean = true
    }

    private class Fetcher(private val url: GlideUrl) : DataFetcher<InputStream> {
        @Volatile private var call: Call? = null
        @Volatile private var response: Response? = null
        @Volatile private var cancelled = false

        override fun loadData(priority: Priority, callback: DataFetcher.DataCallback<in InputStream>) {
            val target = url.toStringUrl()
            val host = target.substringAfter("://").substringBefore('/').lowercase()
            val req = Request.Builder().url(target).header("User-Agent", HttpClient.BROWSER_UA).apply {
                referer(host)?.let { header("Referer", it) }
            }.build()
            try {
                val resp = try {
                    execute(req, null)
                } catch (e: IOException) {
                    val proxy = Prefs.proxy()
                    if (cancelled || proxy.isBlank()) throw e
                    execute(req, proxy)
                }
                response = resp
                val body = resp.body
                if (!resp.isSuccessful || body == null) {
                    callback.onLoadFailed(HttpException(resp.message, resp.code))
                    return
                }
                callback.onDataReady(body.byteStream())
            } catch (e: Exception) {
                callback.onLoadFailed(e)
            }
        }

        private fun execute(req: Request, proxy: String?): Response {
            val c = HttpClient.via(HttpClient.images, proxy).newCall(req)
            call = c
            return c.execute()
        }

        override fun cleanup() {
            runCatching { response?.close() }
        }

        override fun cancel() {
            cancelled = true
            call?.cancel()
        }

        override fun getDataClass(): Class<InputStream> = InputStream::class.java
        override fun getDataSource(): DataSource = DataSource.REMOTE
    }
}
