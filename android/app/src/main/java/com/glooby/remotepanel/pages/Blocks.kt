package com.glooby.remotepanel.pages

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.glooby.remotepanel.data.FeedCache
import com.glooby.remotepanel.data.QuoteItem
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.ui.Fmt
import com.glooby.remotepanel.ui.Img
import com.glooby.remotepanel.ui.Ui
import com.glooby.remotepanel.ui.Ui.W

/** Pieces shared by the page layouts. All sizes are design px on the 1080-wide canvas. */
object Blocks {
    fun section(ctx: Context, title: String, note: String = ""): View = Ui.row(ctx).apply {
        addView(View(ctx).apply { background = Ui.rounded(Theme.accent(), 4) }, Ui.fixed(10, 44, end = 18))
        addView(Ui.text(ctx, title, Ui.H2, Theme.text(), W.BOLD), Ui.wrap())
        addView(Ui.spacer(ctx), LinearLayout.LayoutParams(0, 1, 1f))
        if (note.isNotBlank()) addView(Ui.text(ctx, note, Ui.META, Theme.textFaint()), Ui.wrap())
    }

    fun rank(ctx: Context, n: Int, size: Int = 64): TextView {
        val (bg, fg) = when (n) {
            1 -> Theme.bad() to Color.WHITE
            2 -> Theme.warn() to Color.BLACK
            3 -> Theme.accent() to Color.BLACK
            else -> Theme.surfaceHigh() to Theme.textDim()
        }
        return Ui.number(ctx, n.toString(), if (n >= 10) (size * 0.52f).toInt() else (size * 0.6f).toInt(), fg).apply {
            gravity = Gravity.CENTER
            background = Ui.rounded(bg, 16)
            layoutParams = Ui.fixed(size, size, end = 22)
        }
    }

    /** Centered message for loading / failed / not configured. */
    fun message(ctx: Context, title: String, detail: String = "", glyph: String = "⏳"): View =
        Ui.column(ctx, Theme.surface()).apply {
            gravity = Gravity.CENTER
            setPadding(Ui.px(60), Ui.px(60), Ui.px(60), Ui.px(60))
            addView(Ui.text(ctx, glyph, 120, gravity = Gravity.CENTER), Ui.wide(bottom = 24))
            addView(Ui.text(ctx, title, Ui.H1, Theme.text(), W.BOLD, lines = 2, gravity = Gravity.CENTER), Ui.wide())
            if (detail.isNotBlank()) {
                addView(Ui.text(ctx, detail, Ui.BODY, Theme.textDim(), lines = 4, gravity = Gravity.CENTER), Ui.wide(top = 24))
            }
        }

    /** Message for a feed that has nothing to show yet; mentions the last error if there is one. */
    fun pending(ctx: Context, feedKey: String, what: String): View {
        val err = FeedCache.failures()[feedKey]
        return if (err != null) message(ctx, "$what 暂时读不到", "${reason(err)}\n会自动重试，也可以在设置里换数据源。", "⚠️")
        else message(ctx, "正在读取$what", "第一次打开需要几秒钟。", "⏳")
    }

    /** Turn a raw network error into something a family member can act on. */
    private fun reason(err: String): String {
        val e = err.lowercase()
        // OkHttp: “failed to connect to /192.168.28.126 (port 8088) from /10.0.2.15 …”
        val host = Regex("""connect to [\w.-]*/([\w.:-]+) \(port (\d+)\)""").find(err)?.let { m ->
            m.groupValues[1] + if (m.groupValues[2].isNotBlank()) ":" + m.groupValues[2] else ""
        }
        return when {
            e.contains("failed to connect") || e.contains("timeout") || e.contains("timed out") ->
                "连不上${host?.let { " $it" } ?: "数据源"}，请确认设备和它在同一个网络里。"
            e.contains("unable to resolve") || e.contains("no address") -> "找不到这个网址，请检查网络或地址拼写。"
            e.startsWith("http 4") -> "数据源拒绝了请求（${err.take(8)}）。"
            e.startsWith("http 5") -> "数据源出错了（${err.take(8)}），稍后再试。"
            else -> "原因：$err"
        }
    }

    /** Image filling the box with a dark gradient at the bottom carrying [title] and [meta]. */
    fun overlayTile(
        ctx: Context, url: String, title: String, meta: String, label: String, seed: Int,
        w: Int, h: Int, titleSize: Int = Ui.BODY, titleLines: Int = 2, rankNo: Int = 0,
    ): View = FrameLayout(ctx).apply {
        Ui.clip(this)
        val img = Img.view(ctx, 0)
        addView(img, Ui.fill())
        Img.load(img, url, title, label, seed, w, h)
        val scrim = Ui.column(ctx).apply {
            gravity = Gravity.BOTTOM
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(0x00000000, 0xCC000000.toInt(), 0xF0000000.toInt()))
            setPadding(Ui.px(24), Ui.px(56), Ui.px(24), Ui.px(18))
            addView(Ui.text(ctx, title, titleSize, Color.WHITE, W.BOLD, lines = titleLines), Ui.wide())
            if (meta.isNotBlank()) addView(Ui.text(ctx, meta, Ui.META, 0xFFE0E6EE.toInt()), Ui.wide(top = 4))
        }
        addView(scrim, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))
        if (rankNo > 0) {
            addView(rank(ctx, rankNo, 72), FrameLayout.LayoutParams(Ui.px(72), Ui.px(72)).apply {
                leftMargin = Ui.px(16); topMargin = Ui.px(16)
            })
        }
    }

    /** Coloured pill showing a percentage move, red up / green down. */
    fun movePill(ctx: Context, percent: Double, size: Int = Ui.BODY): TextView {
        val bg = when {
            percent > 0.0001 -> Theme.up()
            percent < -0.0001 -> Theme.down()
            else -> Theme.surfaceHigh()
        }
        return Ui.number(ctx, Fmt.percent(percent), size, Color.WHITE).apply {
            gravity = Gravity.CENTER
            background = Ui.rounded(bg, 14)
            setPadding(Ui.px(16), Ui.px(6), Ui.px(16), Ui.px(6))
        }
    }

    /** One quote: name/code | big price | move. Optional detail line below. */
    fun quoteRow(ctx: Context, q: QuoteItem, crypto: Boolean, detail: Boolean): View = Ui.column(ctx, Theme.surface()).apply {
        setPadding(Ui.px(30), Ui.px(16), Ui.px(30), Ui.px(16))
        gravity = Gravity.CENTER_VERTICAL
        val top = Ui.row(ctx)
        val name = Ui.column(ctx).apply {
            addView(Ui.text(ctx, q.name, Ui.H2, Theme.text(), W.BOLD), Ui.wide())
            addView(Ui.text(ctx, q.symbol + if (crypto) " / USDT" else "", Ui.META, Theme.textFaint()), Ui.wide())
        }
        top.addView(name, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        top.addView(Ui.number(ctx, Fmt.price(q.price, crypto), 80, Theme.move(q.percent)).apply { gravity = Gravity.END }, Ui.wrap(end = 24))
        top.addView(Ui.column(ctx).apply {
            gravity = Gravity.END
            addView(movePill(ctx, q.percent), Ui.wrap())
            addView(Ui.number(ctx, Fmt.change(q.change, crypto), Ui.META, Theme.move(q.percent)).apply { gravity = Gravity.END }, Ui.wrap())
        }, LinearLayout.LayoutParams(Ui.px(210), LinearLayout.LayoutParams.WRAP_CONTENT))
        addView(top, Ui.wide())
        if (detail) {
            val line = if (crypto) "24h 高 ${Fmt.price(q.high, true)}   低 ${Fmt.price(q.low, true)}   额 ${Fmt.big(q.turnover)}"
            else "开 ${Fmt.price(q.open)}   高 ${Fmt.price(q.high)}   低 ${Fmt.price(q.low)}   额 ${Fmt.big(q.turnover)}"
            addView(Ui.text(ctx, line, Ui.META, Theme.textDim()), Ui.wide(top = 8))
        }
    }
}
