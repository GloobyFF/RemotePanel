package com.glooby.remotepanel.pages

import android.content.Context
import android.view.Gravity
import android.view.View
import com.glooby.remotepanel.data.Feeds
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.QuoteItem
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.ui.Fmt
import com.glooby.remotepanel.ui.Ui
import com.glooby.remotepanel.ui.Ui.W

/** 国内股票, 比特币. */
object MarketPages {
    fun stocks(ctx: Context, s: PanelState): View {
        val board = s.stocks ?: return Blocks.pending(ctx, "stocks", "沪深行情")
        return Ui.column(ctx).apply {
            if (board.indices.isNotEmpty()) {
                addView(Pages.grid(ctx, 1, 3, Ui.GAP) { i -> board.indices.getOrNull(i)?.let { indexTile(ctx, it) } }, Ui.wide(230, bottom = Ui.GAP))
            }
            addView(Blocks.section(ctx, "自选股", breadth(board.stocks) + "  ·  " + if (Feeds.marketOpen()) "交易中" else "已收盘"), Ui.wide(64, bottom = 16))
            rows(this, board.stocks, crypto = false, detailMax = 6)
        }
    }

    fun crypto(ctx: Context, s: PanelState): View {
        val items = s.crypto.ifEmpty { return Blocks.pending(ctx, "crypto", "加密货币行情") }
        return Ui.column(ctx).apply {
            addView(Blocks.section(ctx, "加密货币 · USDT", breadth(items)), Ui.wide(64, bottom = 16))
            rows(this, items, crypto = true, detailMax = 7)
        }
    }

    private fun rows(parent: android.widget.LinearLayout, items: List<QuoteItem>, crypto: Boolean, detailMax: Int) {
        val ctx = parent.context
        val shown = items.take(8)
        val detail = shown.size <= detailMax
        shown.forEachIndexed { i, q ->
            parent.addView(Blocks.quoteRow(ctx, q, crypto, detail), Ui.flexV(bottom = if (i < shown.size - 1) 14 else 0))
        }
        // Keep rows a sensible height when there are only a few symbols.
        repeat((5 - shown.size).coerceAtLeast(0)) { parent.addView(Ui.spacer(ctx), Ui.flexV(bottom = 14)) }
    }

    private fun breadth(items: List<QuoteItem>): String {
        val up = items.count { it.percent > 0.0001 }
        val down = items.count { it.percent < -0.0001 }
        return "涨 $up  跌 $down"
    }

    private fun indexTile(ctx: Context, q: QuoteItem): View = Ui.column(ctx, Theme.surface()).apply {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(Ui.px(26), Ui.px(14), Ui.px(22), Ui.px(14))
        addView(Ui.text(ctx, q.name, Ui.BODY, Theme.textDim(), W.MEDIUM), Ui.wide())
        addView(Ui.number(ctx, Fmt.price(q.price), 72, Theme.move(q.percent)), Ui.wide())
        addView(Ui.number(ctx, "${Fmt.percent(q.percent)}  ${Fmt.change(q.change)}", Ui.META, Theme.move(q.percent)), Ui.wide())
    }
}
