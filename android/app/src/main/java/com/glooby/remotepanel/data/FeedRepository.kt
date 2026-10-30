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

data class QuoteItem(
    val name: String,
    val symbol: String,
    val price: Double,
    val percent: Double,
    val change: Double,
    val high: Double,
    val low: Double,
    val open: Double,
    val prev: Double,
    val turnover: Double,
    val unit: String,
    val market: String
)

data class PanelState(
    val hello: String = "",
    val weather: WeatherState? = null,
    val dailyNews: List<NewsItem> = emptyList(),
    val stocks: List<QuoteItem> = emptyList(),
    val crypto: List<QuoteItem> = emptyList(),
    val updatedAt: Long = System.currentTimeMillis(),
    val errors: List<String> = emptyList()
)

object FeedRepository {
    private val cache = ConcurrentHashMap<String, Pair<Long, Any>>()
    @Volatile
    var lastState: PanelState = PanelState()
        private set

    private val coinTable = mapOf(
        "btc" to ("BTC-USDT" to "比特币"),
        "eth" to ("ETH-USDT" to "以太坊"),
        "sol" to ("SOL-USDT" to "Solana"),
        "bnb" to ("BNB-USDT" to "币安币"),
        "xrp" to ("XRP-USDT" to "瑞波币"),
        "doge" to ("DOGE-USDT" to "狗狗币"),
        "ada" to ("ADA-USDT" to "艾达币"),
        "trx" to ("TRX-USDT" to "波场"),
        "ltc" to ("LTC-USDT" to "莱特币"),
        "bch" to ("BCH-USDT" to "比特币现金"),
        "dot" to ("DOT-USDT" to "波卡"),
        "avax" to ("AVAX-USDT" to "Avalanche"),
        "link" to ("LINK-USDT" to "Chainlink"),
        "ton" to ("TON-USDT" to "TON"),
    )

    suspend fun refresh(): PanelState = withContext(Dispatchers.IO) {
        coroutineScope {
            val errors = mutableListOf<String>()
            val weatherDef = async {
                runCatching { fetchWeather() }.onFailure { errors += "天气: ${it.message}" }.getOrNull()
            }
            val newsDef = async {
                runCatching { fetchDailyNews() }.onFailure { errors += "新闻: ${it.message}" }.getOrNull()
            }
            val stocksDef = async {
                runCatching { fetchStocks() }.onFailure { errors += "股票: ${it.message}" }.getOrNull()
            }
            val cryptoDef = async {
                runCatching { fetchCrypto() }.onFailure { errors += "加密: ${it.message}" }.getOrNull()
            }
            val hello = buildHello()
            val state = PanelState(
                hello = hello,
                weather = weatherDef.await(),
                dailyNews = newsDef.await().orEmpty(),
                stocks = stocksDef.await().orEmpty(),
                crypto = cryptoDef.await().orEmpty(),
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

    private fun splitSymbols(raw: String, limit: Int): List<String> =
        raw.split(Regex("[,，\\s;；]+"))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .take(limit)

    private fun stockSecid(token: String): Pair<String, String>? {
        var s = token.lowercase().trim().replace(".", "")
        val market: String
        val code: String
        when {
            s.startsWith("sh") -> {
                market = "1"; code = s.removePrefix("sh")
            }
            s.startsWith("sz") || s.startsWith("bj") -> {
                market = "0"; code = s.drop(2)
            }
            s.length == 6 && s.all { it.isDigit() } -> {
                market = if (s[0] == '6' || s[0] == '5' || s[0] == '9') "1" else "0"
                code = s
            }
            else -> return null
        }
        if (code.length != 6 || !code.all { it.isDigit() }) return null
        return "$market.$code" to code
    }

    private fun fetchStocks(): List<QuoteItem> {
        val cached = cache["stocks"]
        if (cached != null && System.currentTimeMillis() - cached.first < 30 * 60_000L) {
            @Suppress("UNCHECKED_CAST")
            return cached.second as List<QuoteItem>
        }
        val spec = Prefs.sourceUrl("stocks-cn").ifBlank { "600519,300750,600036,601318,002594" }
        val secids = mutableListOf<String>()
        val codes = mutableListOf<String>()
        for (token in splitSymbols(spec, 8)) {
            val pair = stockSecid(token) ?: continue
            secids += pair.first
            codes += pair.second
        }
        if (secids.isEmpty()) error("没有认出股票代码")
        val url =
            "https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&fields=f2,f3,f4,f6,f12,f14,f15,f16,f17,f18&secids=${secids.joinToString(",")}"
        val json = JSONObject(HttpClient.getString(url))
        val diff = json.optJSONObject("data")?.optJSONArray("diff")
            ?: error("没有解析到行情")
        val byCode = mutableMapOf<String, QuoteItem>()
        for (i in 0 until diff.length()) {
            val row = diff.optJSONObject(i) ?: continue
            val code = row.optString("f12")
            if (code.isBlank()) continue
            byCode[code] = QuoteItem(
                name = row.optString("f14").ifBlank { code },
                symbol = code,
                price = row.optDouble("f2"),
                percent = row.optDouble("f3"),
                change = row.optDouble("f4"),
                high = row.optDouble("f15"),
                low = row.optDouble("f16"),
                open = row.optDouble("f17"),
                prev = row.optDouble("f18"),
                turnover = row.optDouble("f6"),
                unit = "元",
                market = "stock"
            )
        }
        val items = codes.mapNotNull { byCode[it] }
        if (items.isEmpty()) error("没有解析到行情")
        cache["stocks"] = System.currentTimeMillis() to items
        return items
    }

    private fun fetchCrypto(): List<QuoteItem> {
        val cached = cache["crypto"]
        if (cached != null && System.currentTimeMillis() - cached.first < 30 * 60_000L) {
            @Suppress("UNCHECKED_CAST")
            return cached.second as List<QuoteItem>
        }
        val spec = Prefs.sourceUrl("crypto").ifBlank { "btc,eth,sol,bnb,xrp" }
        val wanted = mutableListOf<Triple<String, String, String>>() // inst, name, symbol
        for (token in splitSymbols(spec, 8)) {
            val key = token.lowercase()
            val known = coinTable[key]
            if (known != null) {
                wanted += Triple(known.first, known.second, key.uppercase())
            } else {
                val inst = if (key.contains("-")) key.uppercase() else "${key.uppercase()}-USDT"
                val symbol = inst.substringBefore("-")
                wanted += Triple(inst, symbol, symbol)
            }
        }
        if (wanted.isEmpty()) error("没有认出币种")
        val json = JSONObject(
            HttpClient.getString("https://www.okx.com/api/v5/market/tickers?instType=SPOT")
        )
        val rows = json.optJSONArray("data") ?: error("没有解析到行情")
        val byId = mutableMapOf<String, JSONObject>()
        for (i in 0 until rows.length()) {
            val row = rows.optJSONObject(i) ?: continue
            val inst = row.optString("instId")
            if (inst.isNotBlank()) byId[inst] = row
        }
        val items = mutableListOf<QuoteItem>()
        for ((inst, name, symbol) in wanted) {
            val row = byId[inst] ?: continue
            val last = row.optString("last").toDoubleOrNull() ?: 0.0
            val open = row.optString("open24h").toDoubleOrNull() ?: 0.0
            val change = last - open
            val percent = if (open > 0) change / open * 100.0 else 0.0
            items += QuoteItem(
                name = name,
                symbol = symbol,
                price = last,
                percent = percent,
                change = change,
                high = row.optString("high24h").toDoubleOrNull() ?: 0.0,
                low = row.optString("low24h").toDoubleOrNull() ?: 0.0,
                open = open,
                prev = open,
                turnover = row.optString("volCcy24h").toDoubleOrNull() ?: 0.0,
                unit = "USDT",
                market = "crypto"
            )
        }
        if (items.isEmpty()) error("没有解析到行情")
        cache["crypto"] = System.currentTimeMillis() to items
        return items
    }
}
