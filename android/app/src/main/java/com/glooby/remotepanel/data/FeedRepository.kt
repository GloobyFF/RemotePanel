package com.glooby.remotepanel.data

import com.glooby.remotepanel.net.HttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap

data class NewsItem(
    val title: String,
    val summary: String,
    val link: String,
    val imageUrl: String
)

data class WeatherState(
    val city: String,
    val temperature: String,
    val description: String,
    val wind: String,
    val weekly: List<Triple<String, String, String>> // day, hi/lo, desc
)

data class PanelState(
    val hello: String = "",
    val weather: WeatherState? = null,
    val dailyNews: List<NewsItem> = emptyList(),
    val updatedAt: Long = System.currentTimeMillis(),
    val errors: List<String> = emptyList()
)

object FeedRepository {
    private val cache = ConcurrentHashMap<String, Pair<Long, Any>>()
    @Volatile
    var lastState: PanelState = PanelState()
        private set

    suspend fun refresh(): PanelState = withContext(Dispatchers.IO) {
        coroutineScope {
            val errors = mutableListOf<String>()
            val weatherDef = async {
                runCatching { fetchWeather() }.onFailure { errors += "天气: ${it.message}" }.getOrNull()
            }
            val newsDef = async {
                runCatching { fetchDailyNews() }.onFailure { errors += "新闻: ${it.message}" }.getOrNull()
            }
            val hello = buildHello()
            val state = PanelState(
                hello = hello,
                weather = weatherDef.await(),
                dailyNews = newsDef.await().orEmpty(),
                errors = errors.toList()
            )
            lastState = state
            state
        }
    }

    private fun buildHello(): String {
        val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
        val greet = when {
            hour in 5..10 -> "早上好"
            hour in 11..16 -> "中午好"
            else -> "晚上好"
        }
        return "$greet\n家庭信息屏 · RemotePanel"
    }

    private fun weatherText(code: Int): String = when (code) {
        0 -> "晴"
        1 -> "大部晴"
        2 -> "局部多云"
        3 -> "阴"
        45, 48 -> "雾"
        51, 53, 55 -> "毛毛雨"
        61 -> "小雨"
        63 -> "雨"
        65 -> "大雨"
        71 -> "小雪"
        73 -> "雪"
        75 -> "大雪"
        80, 81 -> "阵雨"
        82 -> "强阵雨"
        95, 96, 99 -> "雷暴"
        else -> "天气"
    }

    private fun fetchWeather(): WeatherState {
        val city = Prefs.sourceUrl("weather").ifBlank { "Shanghai" }
        val cached = cache["weather"]
        if (cached != null && System.currentTimeMillis() - cached.first < 6 * 3600_000L) {
            return cached.second as WeatherState
        }
        val geoUrl =
            "https://geocoding-api.open-meteo.com/v1/search?name=${enc(city)}&count=1&language=zh&format=json"
        val geo = JSONObject(HttpClient.getString(geoUrl))
        val results = geo.optJSONArray("results") ?: error("找不到城市 $city")
        val hit = results.getJSONObject(0)
        val lat = hit.getDouble("latitude")
        val lon = hit.getDouble("longitude")
        val name = hit.optString("name", city)
        val forecast =
            "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto"
        val json = JSONObject(HttpClient.getString(forecast))
        val cur = json.getJSONObject("current")
        val daily = json.getJSONObject("daily")
        val times = daily.getJSONArray("time")
        val codes = daily.getJSONArray("weather_code")
        val maxes = daily.getJSONArray("temperature_2m_max")
        val mins = daily.getJSONArray("temperature_2m_min")
        val weekly = mutableListOf<Triple<String, String, String>>()
        for (i in 0 until minOf(7, times.length())) {
            val day = times.getString(i)
            val desc = weatherText(codes.getInt(i))
            val range = "${mins.getDouble(i).toInt()}° / ${maxes.getDouble(i).toInt()}°"
            weekly += Triple(day, range, desc)
        }
        val state = WeatherState(
            city = name,
            temperature = "${cur.getDouble("temperature_2m").toInt()}°",
            description = weatherText(cur.getInt("weather_code")),
            wind = "风 ${cur.getDouble("wind_speed_10m").toInt()} km/h",
            weekly = weekly
        )
        cache["weather"] = System.currentTimeMillis() to state
        return state
    }

    private fun fetchDailyNews(): List<NewsItem> {
        val url = Prefs.sourceUrl("daily-news")
        if (url.isBlank()) return emptyList()
        val cached = cache["daily"]
        if (cached != null && System.currentTimeMillis() - cached.first < 2 * 3600_000L) {
            @Suppress("UNCHECKED_CAST")
            return cached.second as List<NewsItem>
        }
        val xml = HttpClient.getString(url)
        val items = parseRss(xml, 10)
        cache["daily"] = System.currentTimeMillis() to items
        return items
    }

    private fun parseRss(xml: String, limit: Int): List<NewsItem> {
        val out = mutableListOf<NewsItem>()
        var cursor = 0
        val lower = xml
        while (out.size < limit && cursor < lower.length) {
            var start = lower.indexOf("<item", cursor, ignoreCase = true)
            var endTag = "</item>"
            if (start < 0) {
                start = lower.indexOf("<entry", cursor, ignoreCase = true)
                endTag = "</entry>"
            }
            if (start < 0) break
            val end = lower.indexOf(endTag, start, ignoreCase = true)
            if (end < 0) break
            val block = xml.substring(start, end + endTag.length)
            val title = decode(sliceTag(block, "title"))
            var summary = decode(sliceTag(block, "description"))
            if (summary.isEmpty()) summary = decode(sliceTag(block, "summary"))
            var link = sliceTag(block, "link").trim()
            if (link.contains("<")) link = ""
            if (link.isEmpty()) {
                val m = Regex("""<link[^>]+href="([^"]+)"""", RegexOption.IGNORE_CASE).find(block)
                link = m?.groupValues?.getOrNull(1).orEmpty()
            }
            val img = Regex(
                """<(?:enclosure|media:content|media:thumbnail)[^>]+url="([^"]+)"""",
                RegexOption.IGNORE_CASE
            ).find(block)?.groupValues?.getOrNull(1).orEmpty()
            if (title.isNotBlank()) {
                out += NewsItem(title, summary, link, img)
            }
            cursor = end + endTag.length
        }
        return out
    }

    private fun sliceTag(xml: String, tag: String): String {
        val open = Regex("""<$tag(\s[^>]*)?>""", RegexOption.IGNORE_CASE).find(xml) ?: return ""
        val close = "</$tag>"
        val end = xml.indexOf(close, open.range.last, ignoreCase = true)
        if (end < 0) return ""
        var body = xml.substring(open.range.last + 1, end)
        if (body.startsWith("<![CDATA[")) {
            body = body.removePrefix("<![CDATA[").removeSuffix("]]>")
        }
        return body
    }

    private fun decode(text: String): String {
        var s = text
        s = s.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
            .replace("&quot;", "\"").replace("&#39;", "'").replace("&nbsp;", " ")
        s = Regex("<[^>]+>").replace(s, " ")
        s = Regex("\\s+").replace(s, " ").trim()
        return s
    }

    private fun enc(s: String): String =
        URLEncoder.encode(s, StandardCharsets.UTF_8.name())
}
