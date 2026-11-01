package com.glooby.remotepanel.data

import com.glooby.remotepanel.net.HttpClient
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Locale

/** Fetch and text helpers shared by the feed parsers. */
object FeedText {
    /** GET through the page's proxy when it is on; if the proxy cannot be reached, retry direct. */
    fun fetch(pageId: String, url: String, headers: Map<String, String> = emptyMap()): String {
        val proxy = if (Prefs.useProxy(pageId)) Prefs.proxy() else null
        if (proxy.isNullOrBlank()) return HttpClient.getString(url, headers)
        return try {
            HttpClient.getString(url, headers, proxy)
        } catch (e: IOException) {
            HttpClient.getString(url, headers)
        }
    }

    private val entity = Regex("&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos|nbsp|#39);")
    private val tags = Regex("<[^>]+>")
    private val spaces = Regex("[\\s\\u3000\\u00A0]+")

    fun decode(raw: String): String {
        var s = raw
        if (s.startsWith("<![CDATA[")) s = s.removePrefix("<![CDATA[").removeSuffix("]]>")
        s = tags.replace(s, " ")
        s = entity.replace(s) { m ->
            when (val e = m.groupValues[1]) {
                "amp" -> "&"; "lt" -> "<"; "gt" -> ">"; "quot" -> "\""; "apos", "#39" -> "'"; "nbsp" -> " "
                else -> {
                    val code = if (e.startsWith("#x") || e.startsWith("#X")) e.drop(2).toIntOrNull(16) else e.drop(1).toIntOrNull()
                    code?.let { String(Character.toChars(it)) } ?: m.value
                }
            }
        }
        return spaces.replace(s, " ").trim()
    }

    /** Inner text of the first <tag>…</tag> in [xml], raw (not decoded). */
    fun slice(xml: String, tag: String): String {
        val open = Regex("<$tag(\\s[^>]*)?>", RegexOption.IGNORE_CASE).find(xml) ?: return ""
        val end = xml.indexOf("</$tag>", open.range.last, ignoreCase = true)
        if (end < 0) return ""
        return xml.substring(open.range.last + 1, end).trim()
    }

    fun attr(tagText: String, name: String): String =
        Regex("""\b$name\s*=\s*["']([^"']*)["']""", RegexOption.IGNORE_CASE).find(tagText)?.groupValues?.get(1).orEmpty()

    private val dateFormats = listOf(
        "EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss Z",
        "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd HH:mm:ss",
    )

    fun parseDate(raw: String): Long {
        val s = raw.trim()
        if (s.isEmpty()) return 0L
        for (f in dateFormats) {
            val t = runCatching { SimpleDateFormat(f, Locale.US).parse(s)?.time }.getOrNull()
            if (t != null) return t
        }
        return 0L
    }

    /** How many characters of [query] appear in [title]; used to pick a relevant topic image. */
    fun overlap(query: String, title: String): Int = query.count { !it.isWhitespace() && title.contains(it) }
}
