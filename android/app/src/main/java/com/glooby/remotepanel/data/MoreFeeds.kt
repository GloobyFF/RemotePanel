package com.glooby.remotepanel.data

import android.graphics.Color
import com.glooby.remotepanel.net.HttpClient
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLDecoder
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

object MoreFeeds {
    private val cache = ConcurrentHashMap<String, Pair<Long, Any>>()

    private fun proxyFor(id: String): String? = if (Prefs.useProxy(id)) Prefs.proxy() else null

    private fun fresh(key: String, ttlMs: Long): Any? {
        val hit = cache[key] ?: return null
        if (System.currentTimeMillis() - hit.first > ttlMs) return null
        return hit.second
    }

    private fun store(key: String, value: Any) {
        cache[key] = System.currentTimeMillis() to value
    }

    fun github(): List<RepoCard> {
        if (!Prefs.pageEnabled("github-news")) return emptyList()
        fresh("github", 12 * 3600_000L)?.let { @Suppress("UNCHECKED_CAST") return it as List<RepoCard> }
        val base = Prefs.sourceUrl("github-news")
        val proxy = proxyFor("github-news")
        val items = if (base.contains("/rss") || base.contains("feed") || base.endsWith(".xml")) {
            val xml = HttpClient.getString(base, proxy = proxy)
            Regex("<item[\\s\\S]*?</item>", RegexOption.IGNORE_CASE).findAll(xml).take(6).map { block ->
                val title = textTag(block.value, "title")
                RepoCard(title, textTag(block.value, "description"), "", "RSS")
            }.filter { it.name.isNotBlank() }.toList()
        } else {
            val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(
                Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -30) }.time
            )
            val q = URLEncoder.encode("topic:ai created:>=$day fork:false archived:false", "UTF-8")
            val url = "https://api.github.com/search/repositories?q=$q&sort=stars&order=desc&per_page=8"
            val json = JSONObject(HttpClient.getString(url, mapOf("Accept" to "application/vnd.github+json"), proxy))
            val arr = json.optJSONArray("items") ?: JSONArray()
            buildList {
                for (i in 0 until arr.length()) {
                    if (size >= 6) break
                    val repo = arr.optJSONObject(i) ?: continue
                    val name = repo.optString("full_name")
                    if (name.isBlank()) continue
                    add(
                        RepoCard(
                            name = name,
                            description = repo.optString("description").ifBlank { "这个项目没有简介。" },
                            stars = "★ ${repo.optInt("stargazers_count")}  ${repo.optString("language")}",
                            language = repo.optString("language")
                        )
                    )
                }
            }
        }
        if (items.isEmpty()) error("没有解析到项目")
        store("github", items)
        return items
    }

    fun trends(): List<TrendCard> {
        if (!Prefs.pageEnabled("x-news")) return emptyList()
        fresh("x", 2 * 3600_000L)?.let { @Suppress("UNCHECKED_CAST") return it as List<TrendCard> }
        val url = Prefs.sourceUrl("x-news").ifBlank { "https://getdaytrends.com/united-states/" }
        val html = HttpClient.getString(url, proxy = proxyFor("x-news"))
        val found = LinkedHashSet<String>()
        Regex("""/trend/([^"'/?#]+)""").findAll(html).forEach { m ->
            val name = URLDecoder.decode(m.groupValues[1], "UTF-8").replace('+', ' ').trim()
            if (name.length in 2..40) found += name
        }
        val items = found.take(6).map { TrendCard(it, it, "美国区热门话题") }
        if (items.isEmpty()) error("没有解析到话题")
        store("x", items)
        return items
    }

    fun xiaohongshu(): List<PostCard> {
        if (!Prefs.pageEnabled("xiaohongshu-hot")) return emptyList()
        fresh("xhs", 2 * 3600_000L)?.let { @Suppress("UNCHECKED_CAST") return it as List<PostCard> }
        val page = Prefs.sourceUrl("xiaohongshu-hot")
        val text = HttpClient.getString("https://r.jina.ai/$page", proxy = proxyFor("xiaohongshu-hot"))
        val re = Regex("""\d+\.\[([^\]]+)\]\((https://www\.xiaohongshu\.com/search_result[^)]+)\)([0-9.]+[wW]?)""")
        val items = re.findAll(text).take(6).map { m ->
            PostCard(m.groupValues[1], "热度 ${m.groupValues[3]}", "")
        }.toList()
        if (items.isEmpty()) error("没有解析到热门")
        store("xhs", items)
        return items
    }

    fun bilibili(): List<PostCard> {
        if (!Prefs.pageEnabled("bilibili-hot")) return emptyList()
        fresh("bili", 2 * 3600_000L)?.let { @Suppress("UNCHECKED_CAST") return it as List<PostCard> }
        val url = Prefs.sourceUrl("bilibili-hot").ifBlank {
            "https://api.bilibili.com/x/web-interface/popular?ps=8&pn=1"
        }
        val json = JSONObject(
            HttpClient.getString(url, mapOf("Referer" to "https://www.bilibili.com"), proxyFor("bilibili-hot"))
        )
        val list = json.optJSONObject("data")?.optJSONArray("list") ?: error("没有解析到热门")
        val items = buildList {
            for (i in 0 until list.length()) {
                if (size >= 6) break
                val row = list.optJSONObject(i) ?: continue
                val title = row.optString("title")
                if (title.isBlank()) continue
                val owner = row.optJSONObject("owner")?.optString("name").orEmpty()
                val views = row.optJSONObject("stat")?.optLong("view") ?: 0L
                val dur = row.optInt("duration")
                val desc = row.optString("desc").take(80)
                val viewText = if (views >= 10000) {
                    String.format(Locale.US, "%.1f万", views / 10000.0)
                } else {
                    views.toString()
                }
                val bits = listOfNotNull(
                    owner.takeIf { it.isNotBlank() },
                    if (views > 0) "播放 $viewText" else null,
                    desc.takeIf { it.isNotBlank() },
                    if (dur > 0) "时长 ${dur / 60}:${(dur % 60).toString().padStart(2, '0')}" else null
                )
                var pic = row.optString("pic")
                if (pic.startsWith("http://")) pic = "https://" + pic.removePrefix("http://")
                add(PostCard(title, bits.joinToString(" · "), pic))
            }
        }
        if (items.isEmpty()) error("没有解析到热门")
        store("bili", items)
        return items
    }

    fun movies(): List<CoverCard> {
        if (!Prefs.pageEnabled("movie-now-showing")) return emptyList()
        fresh("movies", 24 * 3600_000L)?.let { @Suppress("UNCHECKED_CAST") return it as List<CoverCard> }
        val url = Prefs.sourceUrl("movie-now-showing")
        val json = JSONObject(HttpClient.getString(url))
        val list = json.optJSONArray("movieList") ?: error("没有解析到电影")
        val items = buildList {
            for (i in 0 until list.length()) {
                if (size >= 8) break
                val movie = list.optJSONObject(i) ?: continue
                val title = movie.optString("nm")
                if (title.isBlank()) continue
                add(CoverCard(title, movie.optString("rt"), movie.optString("img")))
            }
        }
        if (items.isEmpty()) error("没有解析到电影")
        store("movies", items)
        return items
    }

    fun steam(): Pair<List<CoverCard>, List<CoverCard>> {
        val want = Prefs.pageEnabled("steam-new-releases") || Prefs.pageEnabled("steam-new-releases-2")
        if (!want) return emptyList<CoverCard>() to emptyList()
        fresh("steam", 24 * 3600_000L)?.let {
            @Suppress("UNCHECKED_CAST")
            return it as Pair<List<CoverCard>, List<CoverCard>>
        }
        val url = Prefs.sourceUrl("steam-new-releases")
        val json = JSONObject(HttpClient.getString(url, proxy = proxyFor("steam-new-releases")))
        val freshItems = steamList(json.optJSONObject("new_releases")?.optJSONArray("items"))
        val hot = steamList(json.optJSONObject("top_sellers")?.optJSONArray("items"))
        if (freshItems.isEmpty() && hot.isEmpty()) error("没有解析到游戏")
        val pair = freshItems to hot
        store("steam", pair)
        return pair
    }

    private fun steamList(arr: JSONArray?): List<CoverCard> {
        if (arr == null) return emptyList()
        return buildList {
            for (i in 0 until arr.length()) {
                if (size >= 6) break
                val row = arr.optJSONObject(i) ?: continue
                val title = row.optString("name")
                if (title.isBlank()) continue
                val cents = row.optInt("final_price")
                val price = if (cents > 0) "¥${cents / 100}" else ""
                val off = row.optInt("discount_percent")
                val meta = listOfNotNull(
                    if (off > 0) "-$off%" else null,
                    price.takeIf { it.isNotBlank() }
                ).joinToString(" ")
                val img = row.optString("header_image").ifBlank { row.optString("large_capsule_image") }
                add(CoverCard(title, meta, img))
            }
        }
    }

    fun covers(pageId: String, cacheKey: String): List<CoverCard> {
        if (!Prefs.pageEnabled(pageId)) return emptyList()
        fresh(cacheKey, 24 * 3600_000L)?.let { @Suppress("UNCHECKED_CAST") return it as List<CoverCard> }
        val url = Prefs.sourceUrl(pageId)
        if (url.isBlank()) return emptyList()
        val html = HttpClient.getString(url, proxy = proxyFor(pageId))
        val items = mutableListOf<CoverCard>()
        val imgRe = Regex("""<img[^>]+(?:data-src|src)=["']([^"']+)["']""", RegexOption.IGNORE_CASE)
        for (m in imgRe.findAll(html)) {
            if (items.size >= 9) break
            var src = m.groupValues[1]
            if (src.startsWith("//")) src = "https:$src"
            if (!src.startsWith("http")) continue
            val low = src.lowercase()
            if (low.contains("logo") || low.contains("icon") || low.endsWith(".svg") || low.contains("avatar")) continue
            val windowStart = (m.range.first - 80).coerceAtLeast(0)
            val window = html.substring(windowStart, (m.range.last + 280).coerceAtMost(html.length))
            val title = Regex("""alt=["']([^"']{2,48})["']""").find(window)?.groupValues?.get(1)
                ?: Regex("""title=["']([^"']{2,48})["']""").find(window)?.groupValues?.get(1)
                ?: continue
            val clean = decode(title)
            if (clean.length < 2) continue
            items += CoverCard(clean, "", src)
        }
        if (items.isEmpty()) error("封面没读到")
        store(cacheKey, items)
        return items
    }

    fun vps(): VpsState? {
        if (!Prefs.pageEnabled("weather")) return null
        val token = Prefs.vpsToken()
        if (token.isEmpty()) return null
        fresh("vps", 24 * 3600_000L)?.let { return it as VpsState }
        val raw = HttpClient.getString(
            Prefs.vpsUrl(),
            mapOf("Authorization" to "Bearer $token")
        )
        val json = JSONObject(raw)
        val data = json.optJSONObject("data") ?: json
        val state = VpsState(
            used = data.optString("used").ifBlank { data.optString("used_traffic", "-") },
            remain = data.optString("remain").ifBlank { data.optString("remaining", "-") },
            status = data.optString("status").ifBlank { data.optString("message", "流量") },
            cycle = data.optString("cycle").ifBlank { "本月" }
        )
        store("vps", state)
        return state
    }

    fun printer(): PrintState? {
        if (!Prefs.pageEnabled("print")) return null
        val url = Prefs.sourceUrl("print")
        if (url.isBlank()) return null
        fresh("print", 10 * 60_000L)?.let { return it as PrintState }
        val body = HttpClient.getString(url, proxy = proxyFor("print"))
        val parsed = JSONArray().also { arr ->
            val trimmed = body.trim()
            if (trimmed.startsWith("[")) {
                val src = JSONArray(trimmed)
                for (i in 0 until src.length()) arr.put(src.opt(i))
            } else {
                arr.put(JSONObject(trimmed))
            }
        }
        var primary = parsed.optJSONObject(0) ?: JSONObject()
        val id = primary.optString("id")
        if (id.isNotBlank()) {
            val detailUrl = if (url.endsWith("/")) "$url$id" else "$url/$id"
            val detail = runCatching { JSONObject(HttpClient.getString(detailUrl, proxy = proxyFor("print"))) }.getOrNull()
            if (detail != null && detail.length() > 0) primary = detail
        }
        val temps = primary.optJSONObject("temps") ?: JSONObject()
        val chips = mutableListOf<TempChip>()
        fun addTemp(label: String, key: String) {
            val v = temps.opt(key) ?: return
            if (v == JSONObject.NULL) return
            chips += TempChip(label, "$v°")
        }
        addTemp("热床", "bed")
        addTemp("腔体", "chamber")
        addTemp("喷嘴", "nozzle")
        val slots = mutableListOf<FilamentSlot>()
        val ams = primary.optJSONArray("ams") ?: JSONArray()
        for (u in 0 until ams.length()) {
            val unit = ams.optJSONObject(u) ?: continue
            val tray = unit.optJSONArray("trays") ?: unit.optJSONArray("slots") ?: JSONArray()
            for (s in 0 until tray.length()) {
                val slot = tray.optJSONObject(s) ?: continue
                val bound = slot.optJSONObject("bound") ?: slot
                val name = bound.optString("name").ifBlank { slot.optString("type").ifBlank { "空" } }
                val pct = bound.optDouble("remainingPercent", slot.optDouble("remainPercent", 0.0))
                val hex = bound.optString("colorHex").ifBlank { slot.optString("colorHex") }
                slots += FilamentSlot(
                    name = name,
                    percent = "${pct.toInt()}%",
                    color = parseHex(hex),
                    kind = "AMS ${u + 1} · ${bound.optString("type").ifBlank { slot.optString("type") }}"
                )
            }
        }
        val prog = primary.optDouble("progress", 0.0)
        val state = PrintState(
            online = primary.optBoolean("online"),
            title = listOf(primary.optString("name"), primary.optString("model")).filter { it.isNotBlank() }.joinToString(" · ").ifBlank { "打印机" },
            status = primary.optString("statusText").ifBlank { primary.optString("status").ifBlank { "-" } },
            progress = "${prog.toInt()}%",
            detail = primary.optString("fileName"),
            temps = chips,
            slots = slots
        )
        store("print", state)
        return state
    }

    private fun textTag(xml: String, tag: String): String {
        val open = Regex("""<$tag[^>]*>""", RegexOption.IGNORE_CASE).find(xml) ?: return ""
        val end = xml.indexOf("</$tag>", open.range.last, ignoreCase = true)
        if (end < 0) return ""
        return decode(xml.substring(open.range.last + 1, end))
    }

    private fun decode(text: String): String {
        var s = text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
            .replace("&quot;", "\"").replace("&#39;", "'")
        s = Regex("<[^>]+>").replace(s, " ")
        return Regex("\\s+").replace(s, " ").trim()
    }

    private fun parseHex(raw: String): Int {
        val hex = raw.trim().removePrefix("#").take(6)
        if (hex.length < 6) return Color.rgb(0x88, 0x88, 0x88)
        return runCatching { Color.parseColor("#$hex") }.getOrDefault(Color.rgb(0x88, 0x88, 0x88))
    }
}
