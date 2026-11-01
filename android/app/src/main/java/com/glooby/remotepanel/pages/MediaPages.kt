package com.glooby.remotepanel.pages

import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import com.glooby.remotepanel.data.CoverCard
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.ui.Fmt
import com.glooby.remotepanel.ui.Img
import com.glooby.remotepanel.ui.Ui
import com.glooby.remotepanel.ui.Ui.W

/** 最近上映, Steam, PC / Switch / PS5 上新. */
object MediaPages {
    const val POSTER_W = 160
    const val POSTER_H = 224
    const val STEAM_W = 494
    const val STEAM_H = 231
    const val GAME_W = 494
    const val GAME_H = 260
    const val PS5_W = 323
    const val PS5_H = 380

    fun movies(ctx: Context, s: PanelState): View {
        val items = s.movies.ifEmpty { return Blocks.pending(ctx, "movies", "上映电影") }.take(6)
        return Ui.column(ctx).apply {
            items.forEachIndexed { i, m ->
                val row = Ui.row(ctx, Theme.surface()).apply {
                    setPadding(Ui.px(14), Ui.px(14), Ui.px(28), Ui.px(14))
                    val poster = Img.view(ctx, 18)
                    Img.load(poster, m.imageUrl, m.title, "电影", i, POSTER_W, POSTER_H)
                    addView(poster, Ui.fixed(POSTER_W, POSTER_H, end = 28))
                    addView(Ui.column(ctx).apply {
                        addView(Ui.row(ctx).apply {
                            addView(Ui.text(ctx, m.title, Ui.H2, Theme.text(), W.BOLD), LinearLayout.LayoutParams(0, -2, 1f))
                            if (m.score.isNotBlank()) {
                                val numeric = m.score.first().isDigit() && !m.score.endsWith("想看")
                                addView(Ui.pill(ctx, if (numeric) "${m.score} 分" else m.score, if (numeric) Theme.warn() else Theme.surfaceHigh(),
                                    if (numeric) Color.BLACK else Theme.textDim()), Ui.wrap(start = 14))
                            }
                        }, Ui.wide())
                        if (m.subtitle.isNotBlank()) addView(Ui.text(ctx, "主演 " + m.subtitle.replace(",", " / "), Ui.BODY, Theme.textDim()), Ui.wide(top = 10))
                        val meta = listOf(m.meta, m.badge).filter { it.isNotBlank() }.joinToString("  ·  ")
                        if (meta.isNotBlank()) addView(Ui.text(ctx, meta, Ui.META, Theme.accent()), Ui.wide(top = 8))
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                }
                addView(row, Ui.flexV(bottom = if (i < items.size - 1) 14 else 0))
            }
        }
    }

    fun steam(ctx: Context, s: PanelState, hot: Boolean): View {
        val b = s.steam ?: return Blocks.pending(ctx, "steam", "Steam 商店")
        val items = (if (hot) b.topSellers else b.newReleases).take(8)
        if (items.isEmpty()) return Blocks.pending(ctx, "steam", "Steam 商店")
        return Pages.grid(ctx, 4, 2, Ui.GAP) { i ->
            items.getOrNull(i)?.let { tile(ctx, it, i, "Steam", STEAM_W, STEAM_H, rankNo = if (hot) i + 1 else 0) }
        }
    }

    fun games(ctx: Context, items: List<CoverCard>, key: String, label: String): View {
        if (items.isEmpty()) return Blocks.pending(ctx, key, "$label 新游")
        return Pages.grid(ctx, 4, 2, Ui.GAP) { i -> items.getOrNull(i)?.let { tile(ctx, it, i, label, GAME_W, GAME_H) } }
    }

    fun ps5(ctx: Context, items: List<CoverCard>): View {
        if (items.isEmpty()) return Blocks.pending(ctx, "ps5", "PS5 新游")
        return Pages.grid(ctx, 3, 3, 18) { i -> items.getOrNull(i)?.let { tile(ctx, it, i, "PS5", PS5_W, PS5_H, compact = true) } }
    }

    /** Cover image on top (fills the spare height), then title, subtitle and price / time. */
    private fun tile(
        ctx: Context, c: CoverCard, i: Int, label: String, w: Int, h: Int, rankNo: Int = 0, compact: Boolean = false,
    ): View = Ui.column(ctx, Theme.surface()).apply {
        Ui.clip(this)
        val box = FrameLayout(ctx)
        val img = Img.view(ctx, 0)
        box.addView(img, Ui.fill())
        Img.load(img, c.imageUrl, c.title, label, i, w, h)
        if (c.badge.isNotBlank()) {
            val sale = c.badge.startsWith("-")
            box.addView(Ui.pill(ctx, c.badge, if (sale) Theme.ok() else Theme.bad(), if (sale) Color.BLACK else Color.WHITE),
                FrameLayout.LayoutParams(-2, -2, Gravity.END or Gravity.TOP).apply { topMargin = Ui.px(12); rightMargin = Ui.px(12) })
        }
        if (rankNo > 0) {
            box.addView(Blocks.rank(ctx, rankNo, 60), FrameLayout.LayoutParams(Ui.px(60), Ui.px(60)).apply { leftMargin = Ui.px(12); topMargin = Ui.px(12) })
        }
        addView(box, Ui.flexV())
        val text = Ui.column(ctx).apply {
            setPadding(Ui.px(22), Ui.px(12), Ui.px(22), Ui.px(14))
            addView(Ui.text(ctx, c.title, Ui.BODY, Theme.text(), W.BOLD), Ui.wide())
            val ago = if (c.time > 0) Fmt.ago(c.time) else ""
            // Game listings: show the time first so it survives ellipsizing; PS5 subtitles are the English name.
            val sub = (if (compact) listOf(c.subtitle, ago) else listOf(ago, c.subtitle)).filter { it.isNotBlank() }.joinToString("  ·  ")
            if (c.price.isNotBlank()) {
                addView(Ui.row(ctx).apply {
                    addView(Ui.number(ctx, c.price, Ui.BODY, if (c.oldPrice.isNotBlank()) Theme.ok() else Theme.text()), Ui.wrap(end = 16))
                    if (c.oldPrice.isNotBlank()) addView(Ui.text(ctx, c.oldPrice, Ui.META, Theme.textFaint()).apply {
                        paintFlags = paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
                    }, Ui.wrap())
                }, Ui.wide(top = 4))
            } else if (sub.isNotBlank()) {
                addView(Ui.text(ctx, sub, Ui.META, Theme.textDim()), Ui.wide(top = 4))
            }
        }
        addView(text, Ui.wide())
    }
}
