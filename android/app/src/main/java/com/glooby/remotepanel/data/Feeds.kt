package com.glooby.remotepanel.data

import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.Calendar
import java.util.TimeZone

/** WMO weather codes → Chinese text and an emoji glyph. */
object Wmo {
    fun text(code: Int): String = when (code) {
        0 -> "晴"; 1 -> "晴间多云"; 2 -> "多云"; 3 -> "阴"
        45, 48 -> "雾"
        51, 53, 55, 56, 57 -> "毛毛雨"
        61 -> "小雨"; 63 -> "中雨"; 65 -> "大雨"; 66, 67 -> "冻雨"
        71 -> "小雪"; 73 -> "中雪"; 75 -> "大雪"; 77 -> "雪粒"
        80, 81 -> "阵雨"; 82 -> "强阵雨"; 85, 86 -> "阵雪"
        95 -> "雷阵雨"; 96, 99 -> "雷暴冰雹"
        else -> "--"
    }

    fun icon(code: Int): String = when (code) {
        0 -> "☀️"; 1 -> "🌤️"; 2 -> "⛅"; 3 -> "☁️"
        45, 48 -> "🌫️"
        51, 53, 55, 56, 57, 61, 63, 80, 81 -> "🌦️"
        65, 66, 67, 82 -> "🌧️"
        71, 73, 75, 77, 85, 86 -> "🌨️"
        95, 96, 99 -> "⛈️"
        else -> "🌡️"
    }

    fun windDir(deg: Int): String = arrayOf("北", "东北", "东", "东南", "南", "西南", "西", "西北")[Math.floorMod(((deg + 22.5) / 45).toInt(), 8)]
}

object Feeds {
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    fun weather(): WeatherState? {
        if (!Prefs.pageEnabled("weather") && !Prefs.pageEnabled("hello")) return null
        val city = Prefs.sourceUrl("weather").ifBlank { "Shanghai" }.takeUnless { it.startsWith("http") } ?: "Shanghai"
        return FeedCache.get("weather", 60 * 60_000L) {
            val geo = FeedCache.get("geo:$city", 30L * 24 * 3600_000L) {
                val j = JSONObject(FeedText.fetch("weather", "https://geocoding-api.open-meteo.com/v1/search?name=${enc(city)}&count=1&language=zh&format=json"))
                val hit = j.optJSONArray("results")?.optJSONObject(0) ?: error("找不到城市 $city")
                Triple(hit.getDouble("latitude"), hit.getDouble("longitude"), hit.optString("name", city))
            } ?: error("城市 $city 暂时查不到")
            val url = "https://api.open-meteo.com/v1/forecast?latitude=${geo.first}&longitude=${geo.second}" +
                "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,surface_pressure" +
                "&hourly=temperature_2m,weather_code,precipitation_probability" +
                "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max" +
                "&timezone=auto&forecast_days=7"
            parseWeather(JSONObject(FeedText.fetch("weather", url)), geo.third)
        }
    }

    private fun parseWeather(json: JSONObject, city: String): WeatherState {
        val cur = json.getJSONObject("current")
        val hourly = json.getJSONObject("hourly")
        val times = hourly.getJSONArray("time")
        val nowHour = cur.optString("time").take(13)
        var start = 0
        for (i in 0 until times.length()) if (times.getString(i).take(13) == nowHour) { start = i; break }
        val hours = buildList {
            val t = hourly.getJSONArray("temperature_2m")
            val c = hourly.getJSONArray("weather_code")
            val p = hourly.optJSONArray("precipitation_probability") ?: JSONArray()
            for (i in start until minOf(start + 24, times.length())) {
                add(HourSlot(times.getString(i).substringAfter('T').take(5), c.optInt(i), t.optDouble(i), p.optInt(i)))
            }
        }
        val daily = json.getJSONObject("daily")
        val dTimes = daily.getJSONArray("time")
        val days = buildList {
            for (i in 0 until minOf(7, dTimes.length())) {
                add(
                    DaySlot(
                        date = dTimes.getString(i),
                        code = daily.getJSONArray("weather_code").optInt(i),
                        low = daily.getJSONArray("temperature_2m_min").optDouble(i),
                        high = daily.getJSONArray("temperature_2m_max").optDouble(i),
                        rainChance = daily.optJSONArray("precipitation_probability_max")?.optInt(i) ?: 0,
                        sunrise = daily.optJSONArray("sunrise")?.optString(i).orEmpty().substringAfter('T'),
                        sunset = daily.optJSONArray("sunset")?.optString(i).orEmpty().substringAfter('T'),
                        uv = daily.optJSONArray("uv_index_max")?.optDouble(i) ?: 0.0,
                    )
                )
            }
        }
        return WeatherState(
            city = city,
            temp = cur.optDouble("temperature_2m"),
            feelsLike = cur.optDouble("apparent_temperature"),
            code = cur.optInt("weather_code"),
            humidity = cur.optInt("relative_humidity_2m"),
            windKmh = cur.optDouble("wind_speed_10m"),
            windDir = cur.optInt("wind_direction_10m"),
            pressure = cur.optDouble("surface_pressure"),
            hourly = hours,
            daily = days,
        )
    }

    fun news(): List<NewsItem>? {
        if (!Prefs.pageEnabled("daily-news")) return null
        val url = Prefs.sourceUrl("daily-news").ifBlank { return null }
        return FeedCache.get("daily", 30 * 60_000L) {
            parseRss(FeedText.fetch("daily-news", url), 12).ifEmpty { error("RSS 里没有条目") }
        }
    }

    private fun parseRss(xml: String, limit: Int): List<NewsItem> {
        val blocks = Regex("<(item|entry)[\\s>][\\s\\S]*?</\\1>", RegexOption.IGNORE_CASE).findAll(xml)
        return blocks.mapNotNull { m ->
            val b = m.value
            val title = FeedText.decode(FeedText.slice(b, "title"))
            if (title.isBlank()) return@mapNotNull null
            val summary = FeedText.decode(FeedText.slice(b, "description").ifBlank { FeedText.slice(b, "summary") })
            var link = FeedText.decode(FeedText.slice(b, "link"))
            if (link.isBlank()) link = Regex("""<link[^>]+href="([^"]+)"""").find(b)?.groupValues?.get(1).orEmpty()
            val img = Regex("""<(?:enclosure|media:content|media:thumbnail)[^>]+url="([^"]+)"""", RegexOption.IGNORE_CASE)
                .find(b)?.groupValues?.get(1)
                ?: Regex("""<img[^>]+src=["']([^"']+)["']""", RegexOption.IGNORE_CASE).find(FeedText.slice(b, "description"))?.groupValues?.get(1)
            val date = FeedText.slice(b, "pubDate").ifBlank { FeedText.slice(b, "published").ifBlank { FeedText.slice(b, "updated") } }
            NewsItem(title, summary.removePrefix(title).trim(), link, img.orEmpty(), FeedText.parseDate(FeedText.decode(date)))
        }.take(limit).toList()
    }

    /** True during A-share continuous trading (Beijing time). */
    fun marketOpen(): Boolean {
        val c = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
        val wd = c.get(Calendar.DAY_OF_WEEK)
        if (wd == Calendar.SATURDAY || wd == Calendar.SUNDAY) return false
        val m = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
        return m in (9 * 60 + 15)..(11 * 60 + 35) || m in (12 * 60 + 55)..(15 * 60 + 5)
    }

    private val indexIds = listOf("1.000001", "0.399001", "0.399006")

    fun splitSymbols(raw: String, limit: Int): List<String> =
        raw.split(Regex("[,，\\s;；]+")).map { it.trim() }.filter { it.isNotEmpty() }.distinct().take(limit)

    private fun stockSecid(token: String): Pair<String, String>? {
        val s = token.lowercase().trim().replace(".", "")
        val (market, code) = when {
            s.startsWith("sh") -> "1" to s.drop(2)
            s.startsWith("sz") || s.startsWith("bj") -> "0" to s.drop(2)
            s.length == 6 && s.all { it.isDigit() } -> (if (s[0] == '6' || s[0] == '5' || s[0] == '9') "1" else "0") to s
            else -> return null
        }
        if (code.length != 6 || !code.all { it.isDigit() }) return null
        return "$market.$code" to code
    }

    fun stocks(): StockBoard? {
        if (!Prefs.pageEnabled("stocks-cn")) return null
        val ttl = if (marketOpen()) 2 * 60_000L else 30 * 60_000L
        return FeedCache.get("stocks", ttl) {
            val spec = Prefs.sourceUrl("stocks-cn").ifBlank { "600519,300750,600036,601318,002594" }
            val picks = splitSymbols(spec, 8).mapNotNull { stockSecid(it) }
            if (picks.isEmpty()) error("没有认出股票代码")
            val ids = indexIds + picks.map { it.first }
            // Eastmoney sometimes resets connections from a busy IP; Tencent serves the same fields.
            val byId = runCatching { eastmoney(ids) }.getOrNull()?.takeIf { it.isNotEmpty() } ?: tencent(ids)
            val board = StockBoard(indexIds.mapNotNull { byId[it] }, picks.mapNotNull { byId[it.first] })
            if (board.stocks.isEmpty()) error("没有解析到行情")
            board
        }
    }

    private fun eastmoney(ids: List<String>): Map<String, QuoteItem> {
        val url = "https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&fields=f2,f3,f4,f6,f12,f13,f14,f15,f16,f17,f18&secids=${ids.joinToString(",")}"
        val diff = JSONObject(FeedText.fetch("stocks-cn", url)).optJSONObject("data")?.optJSONArray("diff")
            ?: error("没有解析到行情")
        val out = HashMap<String, QuoteItem>()
        for (i in 0 until diff.length()) {
            val r = diff.optJSONObject(i) ?: continue
            val code = r.optString("f12")
            if (code.isBlank()) continue
            out["${r.optInt("f13")}.$code"] = QuoteItem(
                name = r.optString("f14").ifBlank { code }, symbol = code,
                price = r.optDouble("f2"), percent = r.optDouble("f3"), change = r.optDouble("f4"),
                high = r.optDouble("f15"), low = r.optDouble("f16"), open = r.optDouble("f17"), prev = r.optDouble("f18"),
                turnover = r.optDouble("f6"), unit = "元", market = "stock",
            )
        }
        return out
    }

    /** qt.gtimg.cn, GBK text: v_sh600519="1~name~code~price~prev~open~…~31 change~32 pct~33 high~34 low~…~37 turnover(万)". */
    private fun tencent(ids: List<String>): Map<String, QuoteItem> {
        fun prefix(id: String): String {
            val code = id.substringAfter('.')
            return when {
                id.startsWith("1.") -> "sh"
                code.startsWith("8") || code.startsWith("4") || code.startsWith("92") -> "bj"
                else -> "sz"
            } + code
        }
        val keys = ids.associateBy { prefix(it) }
        val raw = String(com.glooby.remotepanel.net.HttpClient.getBytes("https://qt.gtimg.cn/q=${keys.keys.joinToString(",")}"), charset("GBK"))
        val out = HashMap<String, QuoteItem>()
        for (line in raw.split(';')) {
            val key = line.substringAfter("v_", "").substringBefore('=').trim()
            val id = keys[key] ?: continue
            val f = line.substringAfter('"').substringBeforeLast('"').split('~')
            if (f.size < 38) continue
            fun d(i: Int) = f[i].toDoubleOrNull() ?: Double.NaN
            out[id] = QuoteItem(
                name = f[1], symbol = f[2], price = d(3), percent = d(32), change = d(31),
                high = d(33), low = d(34), open = d(5), prev = d(4), turnover = d(37) * 1e4,
                unit = "元", market = "stock",
            )
        }
        if (out.isEmpty()) error("没有解析到行情")
        return out
    }

    private val coinNames = mapOf(
        "btc" to "比特币", "eth" to "以太坊", "sol" to "Solana", "bnb" to "币安币", "xrp" to "瑞波币",
        "doge" to "狗狗币", "ada" to "艾达币", "trx" to "波场", "ltc" to "莱特币", "bch" to "比特币现金",
        "dot" to "波卡", "avax" to "Avalanche", "link" to "Chainlink", "ton" to "TON",
    )

    fun crypto(): List<QuoteItem>? {
        if (!Prefs.pageEnabled("crypto")) return null
        return FeedCache.get("crypto", 5 * 60_000L) {
            val spec = Prefs.sourceUrl("crypto").ifBlank { "btc,eth,sol,bnb,xrp" }
            val wanted = splitSymbols(spec, 8).map { t ->
                val k = t.lowercase()
                val inst = if (k.contains("-")) k.uppercase() else "${k.uppercase()}-USDT"
                Triple(inst, coinNames[inst.substringBefore('-').lowercase()] ?: inst.substringBefore('-'), inst.substringBefore('-'))
            }
            if (wanted.isEmpty()) error("没有认出币种")
            val items = wanted.mapNotNull { (inst, name, symbol) ->
                val row = runCatching {
                    JSONObject(FeedText.fetch("crypto", "https://www.okx.com/api/v5/market/ticker?instId=$inst"))
                        .optJSONArray("data")?.optJSONObject(0)
                }.getOrNull() ?: return@mapNotNull null
                val last = row.optString("last").toDoubleOrNull() ?: return@mapNotNull null
                val open = row.optString("sodUtc8").toDoubleOrNull()?.takeIf { it > 0 }
                    ?: row.optString("open24h").toDoubleOrNull() ?: 0.0
                QuoteItem(
                    name = name, symbol = symbol, price = last,
                    percent = if (open > 0) (last - open) / open * 100.0 else 0.0, change = last - open,
                    high = row.optString("high24h").toDoubleOrNull() ?: 0.0,
                    low = row.optString("low24h").toDoubleOrNull() ?: 0.0,
                    open = open, prev = open,
                    turnover = row.optString("volCcy24h").toDoubleOrNull() ?: 0.0,
                    unit = "USDT", market = "crypto",
                )
            }
            items.ifEmpty { error("没有解析到行情") }
        }
    }
}
