package com.glooby.remotepanel.data

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

object Prefs {
    private const val NAME = "remotepanel"
    private lateinit var sp: SharedPreferences

    fun init(context: Context) {
        sp = context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)
    }

    fun dwellOverride(): Int = sp.getInt("dwellOverride", 0)
    fun setDwellOverride(v: Int) = sp.edit().putInt("dwellOverride", v.coerceIn(0, 3600)).apply()

    fun pageEnabled(id: String, default: Boolean = true): Boolean {
        val key = "page.enabled.$id"
        return if (sp.contains(key)) sp.getBoolean(key, default) else default
    }

    fun setPageEnabled(id: String, enabled: Boolean) =
        sp.edit().putBoolean("page.enabled.$id", enabled).apply()

    fun pageDwell(id: String, default: Int): Int {
        val v = sp.getInt("page.dwell.$id", 0)
        return if (v > 0) v else default
    }

    fun setPageDwell(id: String, dwell: Int) {
        if (dwell > 0) sp.edit().putInt("page.dwell.$id", dwell.coerceIn(8, 3600)).apply()
        else sp.edit().remove("page.dwell.$id").apply()
    }

    fun sourceUrl(id: String): String {
        val saved = sp.getString("source.url.$id", null)?.trim().orEmpty()
        if (saved.isNotEmpty()) return saved
        return PageCatalog.sourceDefaults()[id].orEmpty()
    }

    fun setSourceUrl(id: String, url: String) =
        sp.edit().putString("source.url.$id", url.trim()).apply()

    fun loadWebPages(): List<WebPageConfig> {
        val raw = sp.getString("webPages", null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    if (size >= WebPageConfig.MAX) break
                    val o = arr.optJSONObject(i) ?: continue
                    add(WebPageConfig.fromJson(o, i))
                }
            }
        }.getOrDefault(emptyList())
    }

    fun saveWebPages(pages: List<WebPageConfig>) {
        val arr = JSONArray()
        pages.take(WebPageConfig.MAX).forEachIndexed { i, p ->
            arr.put(p.normalized(i).toJson())
        }
        sp.edit().putString("webPages", arr.toString()).apply()
    }

    fun findWebPage(id: String): WebPageConfig? = loadWebPages().firstOrNull { it.id == id }

    /** Enabled roster in rotate order. */
    fun enabledRoster(): List<PageDef> {
        val out = mutableListOf<PageDef>()
        for (p in PageCatalog.builtins()) {
            if (pageEnabled(p.id)) {
                out += p.copy(defaultDwell = pageDwell(p.id, p.defaultDwell))
            }
        }
        for (w in loadWebPages()) {
            if (w.enabled && w.url.isNotBlank()) {
                out += PageDef(
                    id = w.id,
                    title = w.title,
                    defaultDwell = w.dwell,
                    kind = PageDef.Kind.WEB
                )
            }
        }
        if (out.isEmpty()) {
            val first = PageCatalog.builtins().first()
            out += first
        }
        return out
    }

    fun effectiveDwell(def: PageDef): Int {
        val ov = dwellOverride()
        if (ov > 0) return ov.coerceAtLeast(8)
        return pageDwell(def.id, def.defaultDwell).coerceAtLeast(8)
    }
}

data class WebPageConfig(
    val id: String,
    val title: String,
    val url: String,
    val dwell: Int,
    val enabled: Boolean
) {
    fun normalized(indexHint: Int): WebPageConfig {
        val cleanId = if (id.startsWith("web-")) id else newId()
        val cleanTitle = title.trim().ifEmpty { "网页 ${indexHint + 1}" }
        var cleanUrl = url.trim()
        if (cleanUrl.startsWith("webcal://")) cleanUrl = "https://" + cleanUrl.removePrefix("webcal://")
        val cleanDwell = dwell.coerceIn(8, 3600).let { if (it <= 0) 60 else it }
        val cleanEnabled = enabled && cleanUrl.isNotBlank()
        return copy(id = cleanId, title = cleanTitle, url = cleanUrl, dwell = cleanDwell, enabled = cleanEnabled)
    }

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("title", title)
        .put("url", url)
        .put("dwell", dwell)
        .put("enabled", enabled)

    companion object {
        const val MAX = 8
        fun newId(): String = "web-${System.currentTimeMillis()}"
        fun fromJson(o: JSONObject, indexHint: Int): WebPageConfig =
            WebPageConfig(
                id = o.optString("id"),
                title = o.optString("title"),
                url = o.optString("url"),
                dwell = o.optInt("dwell", 60),
                enabled = o.optBoolean("enabled", false)
            ).normalized(indexHint)
    }
}
