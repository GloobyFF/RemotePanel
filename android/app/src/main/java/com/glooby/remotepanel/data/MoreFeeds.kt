package com.glooby.remotepanel.data

import android.graphics.Color
import com.glooby.remotepanel.ui.Fmt
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLDecoder
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

object MoreFeeds {
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    fun github(): List<RepoCard>? {
        if (!Prefs.pageEnabled("github-news")) return null
        return FeedCache.get("github", 6 * 3600_000L) {
            val base = Prefs.sourceUrl("github-news")
            val items = if (base.contains("/rss") || base.contains("feed") || base.endsWith(".xml")) {
                Regex("<item[\\s\\S]*?</item>", RegexOption.IGNORE_CASE).findAll(FeedText.fetch("github-news", base)).take(8).map { b ->
                    RepoCard(FeedText.decode(FeedText.slice(b.value, "title")), FeedText.decode(FeedText.slice(b.value, "description")), 0, 0, "", emptyList())
                }.filter { it.name.isNotBlank() }.toList()
            } else {
                val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -30) }.time)
                val q = enc("topic:ai created:>=$day fork:false archived:false")
                val json = JSONObject(FeedText.fetch("github-news", "https://api.github.com/search/repositories?q=$q&sort=stars&order=desc&per_page=12", mapOf("Accept" to "application/vnd.github+json")))
                val arr = json.optJSONArray("items") ?: JSONArray()
                (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }.map { r ->
                    val topics = r.optJSONArray("topics")?.let { t -> (0 until t.length()).map { t.optString(it) } }.orEmpty()
                    RepoCard(
                        r.optString("full_name"), r.optString("description").ifBlank { "这个项目没有简介。" },
                        r.optInt("stargazers_count"), r.optInt("forks_count"), r.optString("language").takeIf { it != "null" }.orEmpty(),
                        topics.filter { it != "ai" }.take(3),
                    )
                }.filter { it.name.isNotBlank() }.take(8)
            }
            items.ifEmpty { error("没有解析到项目") }
        }
    }

    fun trends(): TrendState? {
        if (!Prefs.pageEnabled("x-news")) return null
        return FeedCache.get("x", 60 * 60_000L) {
            val html = FeedText.fetch("x-news", Prefs.sourceUrl("x-news").ifBlank { "https://getdaytrends.com/united-states/" })
            fun rows(table: String): List<TrendItem> =
                Regex("""<tr><th[^>]*>(\d+)</th><td class="main"><a[^>]*href="[^"]*/trend/([^"/]+)/?"[^>]*>([^<]*)</a>(?:</td><td class="details[^"]*">([^<]*)</td>)?""")
                    .findAll(table).map { m ->
                        val name = FeedText.decode(m.groupValues[3]).ifBlank { URLDecoder.decode(m.groupValues[2], "UTF-8") }
                        TrendItem(m.groupValues[1].toIntOrNull() ?: 0, name, m.groupValues[4].trim())
                    }.filter { it.name.isNotBlank() }.toList()
            // The ranking is split over two tables (1–15, 16–50); “Most Tweeted” follows them.
            val ranked = html.substringBefore("Most Tweeted")
            val most = html.substringAfter("Most Tweeted", "").substringAfter("<table", "").substringBefore("</table>")
            val state = TrendState(rows(ranked).distinctBy { it.rank }.take(20), rows(most).take(6))
            if (state.now.isEmpty()) error("没有解析到话题")
            state
        }
    }

    fun xiaohongshu(): List<PostCard>? {
        if (!Prefs.pageEnabled("xiaohongshu-hot")) return null
        return FeedCache.get("xhs", 2 * 3600_000L) {
            val page = Prefs.sourceUrl("xiaohongshu-hot")
            val html = runCatching { FeedText.fetch("xiaohongshu-hot", page) }.getOrDefault("")
            var rows = Regex("""<a class="rank-item-container"[\s\S]*?</a>""").findAll(html).mapNotNull { m ->
                val title = FeedText.decode(Regex("""class="s-title">([^<]+)<""").find(m.value)?.groupValues?.get(1).orEmpty())
                val heat = Regex("""class="s-tie-count">([^<]+)<""").find(m.value)?.groupValues?.get(1).orEmpty().trim()
                val img = Regex("""url\(['"]?([^'")]+)['"]?\)""").find(m.value)?.groupValues?.get(1).orEmpty()
                if (title.isBlank()) null else PostCard(title, img, heat = heat)
            }.toList()
            if (rows.isEmpty()) {
                val text = FeedText.fetch("xiaohongshu-hot", "https://r.jina.ai/$page")
                rows = Regex("""\d+\.\[([^\]]+)\]\((https://www\.xiaohongshu\.com/search_result[^)]+)\)([0-9.]+[wW万]?)""")
                    .findAll(text).map { PostCard(it.groupValues[1], "", heat = it.groupValues[3]) }.toList()
            }
            if (rows.isEmpty()) error("没有解析到热门")
            val seen = HashSet<String>()
            rows.take(16).mapIndexed { i, p ->
                if (i >= 7 || p.imageUrl.startsWith("http")) return@mapIndexed p
                val img = runCatching { topicImage(p.title) }.getOrDefault("")
                if (img.isNotBlank() && seen.add(img)) p.copy(imageUrl = img) else p
            }
        }
    }

    /** Best-matching photo for a topic from 360 image search (same approach as the iPad app). */
    private fun topicImage(query: String): String {
        val json = JSONObject(FeedText.fetch("", "https://image.so.com/j?q=${enc(query)}&src=srp&sn=0&pn=12", mapOf("Referer" to "https://image.so.com/")))
        val list = json.optJSONArray("list") ?: return ""
        var best = ""
        var bestScore = 3
        var bestArea = 0.0
        for (i in 0 until list.length()) {
            val r = list.optJSONObject(i) ?: continue
            val w = r.optDouble("width", 0.0)
            val h = r.optDouble("height", 0.0)
            if (w in 1.0..359.0 || h in 1.0..219.0 || (h > 0 && w / h < 0.9)) continue
            var thumb = r.optString("thumb").ifBlank { r.optString("_thumb") }
            if (thumb.startsWith("http://")) thumb = "https://" + thumb.removePrefix("http://")
            if (!thumb.startsWith("https://")) continue
            val score = FeedText.overlap(query, r.optString("title"))
            if (score > bestScore || (score == bestScore && w * h > bestArea)) {
                best = thumb; bestScore = score; bestArea = w * h
            }
        }
        return best
    }

    fun bilibili(): List<PostCard>? {
        if (!Prefs.pageEnabled("bilibili-hot")) return null
        return FeedCache.get("bili", 60 * 60_000L) {
            val url = Prefs.sourceUrl("bilibili-hot").ifBlank { "https://api.bilibili.com/x/web-interface/popular?ps=10&pn=1" }
            val list = JSONObject(FeedText.fetch("bilibili-hot", url, mapOf("Referer" to "https://www.bilibili.com"))).optJSONObject("data")?.optJSONArray("list")
                ?: error("没有解析到热门")
            (0 until list.length()).mapNotNull { list.optJSONObject(it) }.mapNotNull { r ->
                val title = FeedText.decode(r.optString("title")).ifBlank { return@mapNotNull null }
                val stat = r.optJSONObject("stat") ?: JSONObject()
                PostCard(
                    title = title,
                    imageUrl = r.optString("pic"),
                    heat = Fmt.count(stat.optLong("view")),
                    author = r.optJSONObject("owner")?.optString("name").orEmpty(),
                    stats = listOfNotNull(
                        Fmt.count(stat.optLong("like")).takeIf { it.isNotBlank() }?.let { "赞 $it" },
                        Fmt.count(stat.optLong("danmaku")).takeIf { it.isNotBlank() }?.let { "弹幕 $it" },
                    ),
                    badge = r.optString("tname"),
                    duration = Fmt.duration(r.optInt("duration")),
                )
            }.take(10).ifEmpty { error("没有解析到热门") }
        }
    }

    fun movies(): List<CoverCard>? {
        if (!Prefs.pageEnabled("movie-now-showing")) return null
        return FeedCache.get("movies", 6 * 3600_000L) {
            val list = JSONObject(FeedText.fetch("movie-now-showing", Prefs.sourceUrl("movie-now-showing"))).optJSONArray("movieList")
                ?: error("没有解析到电影")
            (0 until list.length()).mapNotNull { list.optJSONObject(it) }.mapNotNull { m ->
                val title = m.optString("nm").ifBlank { return@mapNotNull null }
                val sc = m.optDouble("sc", 0.0)
                val wish = m.optLong("wish")
                CoverCard(
                    title = title,
                    imageUrl = m.optString("img"),
                    subtitle = m.optString("star"),
                    meta = m.optString("showInfo").ifBlank { m.optString("rt").let { if (it.isBlank()) "" else "$it 上映" } },
                    badge = m.optString("version").uppercase().replace("V2D", "").replace("V3D", "3D").trim(),
                    score = if (sc > 0) String.format(Locale.US, "%.1f", sc) else if (wish > 0) "${Fmt.count(wish)}想看" else "",
                )
            }.take(8).ifEmpty { error("没有解析到电影") }
        }
    }

    fun steam(): SteamBoard? {
        if (!Prefs.pageEnabled("steam-new-releases") && !Prefs.pageEnabled("steam-new-releases-2")) return null
        return FeedCache.get("steam", 6 * 3600_000L) {
            val json = JSONObject(FeedText.fetch("steam-new-releases", Prefs.sourceUrl("steam-new-releases")))
            fun list(key: String, n: Int): List<CoverCard> {
                val arr = json.optJSONObject(key)?.optJSONArray("items") ?: return emptyList()
                val seen = HashSet<Int>()
                return (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }.mapNotNull { r ->
                    if (!seen.add(r.optInt("id"))) return@mapNotNull null
                    val name = r.optString("name").ifBlank { return@mapNotNull null }
                    val fin = r.optInt("final_price")
                    val orig = r.optInt("original_price", 0)
                    val off = r.optInt("discount_percent")
                    CoverCard(
                        title = name,
                        imageUrl = r.optString("header_image").ifBlank { r.optString("large_capsule_image") },
                        price = if (fin > 0) "¥${fin / 100}" else if (r.isNull("original_price")) "" else "免费",
                        oldPrice = if (off > 0 && orig > fin) "¥${orig / 100}" else "",
                        badge = if (off > 0) "-$off%" else "",
                    )
                }.take(n)
            }
            val board = SteamBoard(list("new_releases", 10), list("top_sellers", 10), list("specials", 6))
            if (board.newReleases.isEmpty() && board.topSellers.isEmpty()) error("没有解析到游戏")
            board
        }
    }

    private val hotTags = setOf("IGN必玩推荐榜", "3A巨作")
    private val noise = setOf("解压即撸", "NSP", "NSZ", "XCI", "")
    /** Version words that gamer520 glues onto the game name; “非虚拟机版” must come before “虚拟机版”. */
    private val titleTags = listOf("非虚拟机版", "虚拟机版", "移植版", "解压即撸")

    /** WordPress game listings (gamer520, 2468c): one <article> per game, cover in data-src. */
    fun covers(pageId: String, cacheKey: String): List<CoverCard>? {
        if (!Prefs.pageEnabled(pageId)) return null
        val url = Prefs.sourceUrl(pageId).ifBlank { return null }
        return FeedCache.get(cacheKey, 6 * 3600_000L) {
            val html = FeedText.fetch(pageId, url)
            Regex("<article[\\s\\S]*?</article>").findAll(html).mapNotNull { m ->
                val a = m.value
                val raw = FeedText.decode(Regex("""<h2 class="entry-title">\s*<a[^>]*>([\s\S]*?)</a>""").find(a)?.groupValues?.get(1).orEmpty())
                if (raw.isBlank()) return@mapNotNull null
                val parts = raw.split('|').map { it.trim() }
                var title = parts.first()
                val extra = mutableListOf<String>()
                for (tag in titleTags) {
                    if (!title.contains(tag)) continue
                    title = title.replace(tag, "").replace(Regex("\\s+"), " ").trim()
                    if (tag != "解压即撸") extra += tag
                }
                var sub = (extra + parts.drop(1).filter { it !in noise }).take(2).joinToString(" · ")
                if (sub.isEmpty()) {
                    // PS5 titles look like “中文名.English Name”
                    val dot = title.indexOf('.')
                    if (dot in 2 until title.length - 2) {
                        sub = title.substring(dot + 1).trim(); title = title.substring(0, dot).trim()
                    }
                }
                val img = Regex("""<img[^>]*?\b(?:data-src|data-original|data-lazy-src)=["'](https?://[^"']+)["']""").find(a)?.groupValues?.get(1)
                    ?: Regex("""<img[^>]*?\bsrc=["'](https?://[^"']+)["']""").find(a)?.groupValues?.get(1).orEmpty()
                val time = FeedText.parseDate(Regex("""<time datetime="([^"]+)"""").find(a)?.groupValues?.get(1).orEmpty())
                val cats = Regex("""rel="category">\s*(?:<i[^>]*></i>)?([^<]+)<""").findAll(a).map { it.groupValues[1].trim() }.toList()
                CoverCard(
                    title = title, imageUrl = img, subtitle = sub, time = time,
                    badge = cats.firstOrNull { it in hotTags }.orEmpty(),
                )
            }.take(12).toList().ifEmpty { error("封面没读到") }
        }
    }

    fun vps(): VpsState? {
        if (!Prefs.pageEnabled("weather")) return null
        val token = Prefs.vpsToken().ifEmpty { return null }
        return FeedCache.get("vps", 3 * 3600_000L) {
            val json = JSONObject(com.glooby.remotepanel.net.HttpClient.getString(Prefs.vpsUrl(), mapOf("Authorization" to "Bearer $token")))
            val monthly = json.optJSONObject("monthly") ?: json.optJSONObject("data") ?: json
            val cycle = json.optJSONObject("cycle")
            val alert = json.optJSONObject("alert")
            VpsState(
                used = monthly.optString("used_human").ifBlank { monthly.optString("used", "-") },
                remain = monthly.optString("remaining_human").ifBlank { monthly.optString("remain", "-") },
                status = alert?.optString("message")?.ifBlank { alert.optString("level") } ?: monthly.optString("status", ""),
                cycle = if (cycle != null) "${cycle.optString("start").take(10)} → ${cycle.optString("end").take(10)}" else monthly.optString("cycle", ""),
                percent = monthly.optDouble("percent_used", Double.NaN),
            )
        }
    }

    fun printer(): PrintState? {
        if (!Prefs.pageEnabled("print")) return null
        val url = Prefs.sourceUrl("print").ifBlank { return null }
        return FeedCache.get("print", 2 * 60_000L) { parsePrinter(url) }
    }

    private fun parsePrinter(url: String): PrintState {
        val body = FeedText.fetch("print", url).trim()
        var primary = if (body.startsWith("[")) JSONArray(body).optJSONObject(0) ?: JSONObject() else JSONObject(body)
        val id = primary.optString("id")
        if (id.isNotBlank()) {
            runCatching { JSONObject(FeedText.fetch("print", if (url.endsWith("/")) "$url$id" else "$url/$id")) }.getOrNull()
                ?.takeIf { it.length() > 0 }?.let { primary = it }
        }
        val temps = primary.optJSONObject("temps") ?: JSONObject()
        val chips = listOf("喷嘴" to "nozzle", "热床" to "bed", "腔体" to "chamber").mapNotNull { (label, key) ->
            val v = temps.opt(key)
            if (v == null || v == JSONObject.NULL) null else TempChip(label, "${(v as? Number)?.toInt() ?: v}°")
        }
        val slots = mutableListOf<FilamentSlot>()
        val ams = primary.optJSONArray("ams") ?: JSONArray()
        for (u in 0 until ams.length()) {
            val unit = ams.optJSONObject(u) ?: continue
            val tray = unit.optJSONArray("trays") ?: unit.optJSONArray("slots") ?: continue
            for (s in 0 until tray.length()) {
                val slot = tray.optJSONObject(s) ?: continue
                val bound = slot.optJSONObject("bound") ?: slot
                val type = bound.optString("type").ifBlank { slot.optString("type") }
                slots += FilamentSlot(
                    name = bound.optString("name").ifBlank { type.ifBlank { "空" } },
                    percent = bound.optDouble("remainingPercent", slot.optDouble("remainPercent", -1.0)).toInt(),
                    color = parseHex(bound.optString("colorHex").ifBlank { slot.optString("colorHex") }),
                    kind = "A${u + 1}-${s + 1}" + if (type.isNotBlank()) " $type" else "",
                )
            }
        }
        val layer = primary.optString("layer")
        val total = primary.optString("totalLayers")
        return PrintState(
            online = primary.optBoolean("online"),
            title = run {
                val name = primary.optString("name")
                val model = primary.optString("model")
                // “高级玩具H2D · H2D” → “高级玩具H2D”
                val parts = if (model.isNotBlank() && !name.contains(model)) listOf(name, model) else listOf(name.ifBlank { model })
                parts.filter { it.isNotBlank() }.joinToString(" · ").ifBlank { "打印机" }
            },
            status = primary.optString("statusText").ifBlank { primary.optString("status").ifBlank { "-" } },
            progress = primary.optDouble("progress", 0.0),
            fileName = primary.optString("fileName"),
            remainMinutes = primary.optInt("remainingMinutes", -1),
            layer = if (layer.isNotBlank() && total.isNotBlank()) "$layer / $total" else "",
            temps = chips,
            slots = slots,
        )
    }

    private fun parseHex(raw: String): Int {
        val hex = raw.trim().removePrefix("#").take(6)
        if (hex.length < 6) return Color.rgb(0x88, 0x88, 0x88)
        return runCatching { Color.parseColor("#$hex") }.getOrDefault(Color.rgb(0x88, 0x88, 0x88))
    }
}
