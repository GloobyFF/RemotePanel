package com.glooby.remotepanel.pages

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import com.glooby.remotepanel.data.FeedCache
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.ui.Fmt
import com.glooby.remotepanel.ui.Img
import com.glooby.remotepanel.ui.Ui
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Native data page. It rebuilds only when the slice of state it shows changes, so the 30 s poll
 * and partial updates do not make it flicker or reload images.
 */
class BoardPage(private val context: Context, private val pageId: String) : PanelPage {
    override val root = FrameLayout(context)
    private var signature: Any? = null
    private var last = PanelState()

    override fun bind(state: PanelState) {
        last = state
        val sig = Pages.signature(pageId, state)
        if (sig == signature && root.childCount > 0) return
        signature = sig
        Img.release(root)
        root.removeAllViews()
        root.setBackgroundColor(Theme.bg())
        root.addView(Pages.frame(context, pageId, state), Ui.fill())
    }

    override fun tick() = bind(last)

    override fun onDisappear() {
        Img.release(root)
    }
}

/** Which source each page shows, how to draw it, and what to preload. */
object Pages {
    private class Meta(val feed: String, val source: String)

    private val meta = mapOf(
        "hello" to Meta("weather", "Open-Meteo · 本机"),
        "schedule" to Meta("", "本机日历"),
        "weather" to Meta("weather", "Open-Meteo"),
        "daily-news" to Meta("daily", "中新网 RSS"),
        "github-news" to Meta("github", "GitHub"),
        "x-news" to Meta("x", "getdaytrends · 美国"),
        "xiaohongshu-hot" to Meta("xhs", "今日热榜 · 小红书"),
        "bilibili-hot" to Meta("bili", "哔哩哔哩 · 综合热门"),
        "stocks-cn" to Meta("stocks", "东方财富 / 腾讯行情"),
        "crypto" to Meta("crypto", "OKX 现货 · 涨跌自北京时间 0 点"),
        "print" to Meta("print", "打印机接口"),
        "movie-now-showing" to Meta("movies", "猫眼电影"),
        "steam-new-releases" to Meta("steam", "Steam 商店"),
        "steam-new-releases-2" to Meta("steam", "Steam 商店"),
        "gamer520-pc-latest" to Meta("pc", "gamer520"),
        "gamer520-switch-latest" to Meta("switch", "gamer520"),
        "ps5-games-latest" to Meta("ps5", "2468c"),
    )

    private fun minute(): String = SimpleDateFormat("yyyyMMddHHmm", Locale.US).format(Date())

    /** Feed key behind a page ("" when the page has no network feed). */
    fun feedOf(id: String): String = meta[id]?.feed.orEmpty()

    fun signature(id: String, s: PanelState): Any? = when (id) {
        "hello" -> listOf(minute(), s.helloPeriod, s.hello, s.weather)
        "schedule" -> minute().dropLast(1)
        "weather" -> listOf(s.weather, s.vps)
        "daily-news" -> s.dailyNews
        "github-news" -> s.github
        "x-news" -> s.trends
        "xiaohongshu-hot" -> s.xhs
        "bilibili-hot" -> s.bili
        "stocks-cn" -> s.stocks
        "crypto" -> s.crypto
        "print" -> s.printer
        "movie-now-showing" -> s.movies
        "steam-new-releases", "steam-new-releases-2" -> s.steam
        "gamer520-pc-latest" -> s.pcGames
        "gamer520-switch-latest" -> s.switchGames
        "ps5-games-latest" -> s.ps5Games
        else -> null
    }?.let { listOf(it, FeedCache.failures()[meta[id]?.feed]) }

    fun frame(ctx: Context, id: String, s: PanelState): View = Ui.column(ctx).apply {
        setPadding(Ui.px(Ui.PAD), Ui.px(24), Ui.px(Ui.PAD), Ui.px(12))
        val body = runCatching { render(ctx, id, s) }
            .getOrElse { Blocks.message(ctx, "这一页画不出来", it.message ?: it.javaClass.simpleName, "⚠️") }
        addView(body, Ui.flexV())
        footer(ctx, id, s)?.let { addView(it, Ui.wide(64, top = 12)) }
    }

    private fun footer(ctx: Context, id: String, s: PanelState): View? {
        val m = meta[id] ?: return null
        val at = s.fetchedAt[m.feed] ?: 0L
        val failed = m.feed.isNotEmpty() && FeedCache.failures().containsKey(m.feed)
        val text = buildString {
            append("来源 ").append(m.source)
            if (at > 0) append("   ·   ").append(Fmt.clock(at)).append(" 更新")
            if (failed && at > 0) append("   ·   刷新失败，显示的是旧数据")
        }
        return Ui.text(ctx, text, Ui.META, if (failed) Theme.warn() else Theme.textFaint())
    }

    private fun render(ctx: Context, id: String, s: PanelState): View = when (id) {
        "hello" -> HomePages.hello(ctx, s)
        "weather" -> HomePages.weather(ctx, s)
        "schedule" -> HomePages.schedule(ctx)
        "print" -> HomePages.printer(ctx, s)
        "daily-news" -> NewsPages.news(ctx, s)
        "github-news" -> NewsPages.github(ctx, s)
        "x-news" -> NewsPages.trends(ctx, s)
        "xiaohongshu-hot" -> NewsPages.xiaohongshu(ctx, s)
        "bilibili-hot" -> NewsPages.bilibili(ctx, s)
        "stocks-cn" -> MarketPages.stocks(ctx, s)
        "crypto" -> MarketPages.crypto(ctx, s)
        "movie-now-showing" -> MediaPages.movies(ctx, s)
        "steam-new-releases" -> MediaPages.steam(ctx, s, hot = false)
        "steam-new-releases-2" -> MediaPages.steam(ctx, s, hot = true)
        "gamer520-pc-latest" -> MediaPages.games(ctx, s.pcGames, "pc", "PC")
        "gamer520-switch-latest" -> MediaPages.games(ctx, s.switchGames, "switch", "Switch")
        "ps5-games-latest" -> MediaPages.ps5(ctx, s.ps5Games)
        else -> Blocks.message(ctx, "这一页还没有内容", glyph = "🗂️")
    }

    /** Warm the image cache for [id] a few seconds before it appears. */
    fun preload(ctx: Context, id: String, s: PanelState) {
        val jobs: List<Triple<String, Int, Int>> = when (id) {
            "xiaohongshu-hot" -> s.xhs.mapIndexed { i, p -> Triple(p.imageUrl, if (i == 0) 1008 else 494, if (i == 0) 420 else 300) }
            "bilibili-hot" -> s.bili.map { Triple(it.imageUrl, NewsPages.BILI_W, NewsPages.BILI_H) }
            "movie-now-showing" -> s.movies.map { Triple(it.imageUrl, MediaPages.POSTER_W, MediaPages.POSTER_H) }
            "steam-new-releases" -> s.steam?.newReleases.orEmpty().map { Triple(it.imageUrl, MediaPages.STEAM_W, MediaPages.STEAM_H) }
            "steam-new-releases-2" -> s.steam?.topSellers.orEmpty().map { Triple(it.imageUrl, MediaPages.STEAM_W, MediaPages.STEAM_H) }
            "gamer520-pc-latest" -> s.pcGames.map { Triple(it.imageUrl, MediaPages.GAME_W, MediaPages.GAME_H) }
            "gamer520-switch-latest" -> s.switchGames.map { Triple(it.imageUrl, MediaPages.GAME_W, MediaPages.GAME_H) }
            "ps5-games-latest" -> s.ps5Games.map { Triple(it.imageUrl, MediaPages.PS5_W, MediaPages.PS5_H) }
            else -> emptyList()
        }
        jobs.take(12).forEach { (u, w, h) -> Img.preload(ctx, u, w, h) }
    }

    /** Grid helper: [count] equal rows in a vertical stack, each filled by [cell]. */
    fun grid(ctx: Context, rows: Int, cols: Int, gap: Int, cell: (Int) -> View?): View = Ui.column(ctx).apply {
        for (r in 0 until rows) {
            val line = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
            for (c in 0 until cols) {
                val v = cell(r * cols + c) ?: View(ctx)
                line.addView(v, Ui.flexH(1f, end = if (c < cols - 1) gap else 0))
            }
            addView(line, Ui.flexV(1f, bottom = if (r < rows - 1) gap else 0))
        }
    }
}
