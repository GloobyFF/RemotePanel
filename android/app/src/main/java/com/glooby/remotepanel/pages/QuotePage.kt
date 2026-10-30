package com.glooby.remotepanel.pages

import android.graphics.Color
import android.util.TypedValue
import android.view.LayoutInflater
import android.widget.LinearLayout
import android.widget.TextView
import com.glooby.remotepanel.R
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Theme
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max

class QuotePage(
    context: android.content.Context,
    private val crypto: Boolean
) : PanelPage {
    override val root = LayoutInflater.from(context).inflate(R.layout.page_simple_scroll, null)
    private val content: LinearLayout = root.findViewById(R.id.content)

    override fun bind(state: PanelState) {
        content.removeAllViews()
        root.setBackgroundColor(Theme.bg())
        val items = if (crypto) state.crypto else state.stocks
        val header = TextView(root.context).apply {
            val up = items.count { it.percent > 0.0001 }
            val down = items.count { it.percent < -0.0001 }
            text = if (items.isEmpty()) {
                if (crypto) "正在读取主流币行情" else "正在读取沪深行情"
            } else {
                val hint = if (crypto) "USDT · 约每 30 分钟" else "红涨绿跌 · 约每 30 分钟"
                "涨 $up    跌 $down    ·    $hint"
            }
            setTextColor(Theme.border())
            textSize = 15f
            setPadding(0, 0, 0, dp(10))
        }
        content.addView(header)

        if (items.isEmpty()) {
            content.addView(TextView(root.context).apply {
                text = if (crypto) {
                    "设置里填写币种，逗号分隔，例如 btc,eth,sol"
                } else {
                    "设置里填写股票代码，逗号分隔，例如 600519,300750"
                }
                setTextColor(Theme.border())
                textSize = 18f
            })
            return
        }

        val inflater = LayoutInflater.from(root.context)
        val rowH = max(118, (root.height.takeIf { it > 0 } ?: 900) / max(1, items.size) - 10)
            .coerceAtMost(168)
        items.forEach { item ->
            val row = inflater.inflate(R.layout.item_quote_row, content, false)
            val move = moveColor(item.percent)
            row.setBackgroundColor(
                when {
                    item.percent > 0.0001 -> Color.argb(245, 82, 28, 33)
                    item.percent < -0.0001 -> Color.argb(245, 20, 72, 48)
                    else -> Theme.card()
                }
            )
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(rowH)
            ).apply { bottomMargin = dp(8) }
            row.layoutParams = lp

            val frac = priceFrac(item.price, crypto)
            row.findViewById<TextView>(R.id.name).text = item.name.ifBlank { item.symbol }
            row.findViewById<TextView>(R.id.symbol).text = item.symbol
            row.findViewById<TextView>(R.id.open).text = "开 ${grouped(item.open, frac)}"
            row.findViewById<TextView>(R.id.prev).text =
                "${if (crypto) "24h前" else "昨收"} ${grouped(item.prev, frac)}"

            val priceView = row.findViewById<TextView>(R.id.price)
            priceView.text = grouped(item.price, frac)
            priceView.setTextColor(move)
            row.findViewById<TextView>(R.id.unit).text = item.unit

            val pctView = row.findViewById<TextView>(R.id.percent)
            pctView.text = "${signed(item.percent, 2)}%"
            pctView.setTextColor(move)
            val chgView = row.findViewById<TextView>(R.id.change)
            chgView.text = signed(item.change, frac)
            chgView.setTextColor(move)

            row.findViewById<TextView>(R.id.high).text = "高 ${grouped(item.high, frac)}"
            val turn = turnover(item.turnover)
            row.findViewById<TextView>(R.id.lowOrTurn).text =
                if (turn.isNotEmpty()) {
                    "${if (crypto) "24h" else "成交"} $turn"
                } else {
                    "低 ${grouped(item.low, frac)}"
                }
            content.addView(row)
        }
    }

    private fun moveColor(percent: Double): Int = when {
        percent > 0.0001 -> Color.parseColor("#FF4D6A")
        percent < -0.0001 -> Color.parseColor("#3DFF8A")
        else -> Color.parseColor("#B8E7FF")
    }

    private fun priceFrac(n: Double, crypto: Boolean): Int {
        if (!crypto) return 2
        return when {
            n >= 1000.0 -> 1
            n >= 1.0 -> 2
            n >= 0.01 -> 4
            else -> 6
        }
    }

    private fun grouped(n: Double, frac: Int): String {
        val sym = DecimalFormatSymbols(Locale.US)
        val pattern = if (frac <= 0) "#,##0" else "#,##0." + "0".repeat(frac)
        return DecimalFormat(pattern, sym).format(n)
    }

    private fun signed(n: Double, frac: Int): String {
        val body = grouped(abs(n), frac)
        return when {
            n > 0.0000001 -> "+$body"
            n < -0.0000001 -> "-$body"
            else -> body
        }
    }

    private fun turnover(n: Double): String = when {
        n >= 100_000_000.0 -> String.format(Locale.US, "%.2f亿", n / 100_000_000.0)
        n >= 10_000.0 -> String.format(Locale.US, "%.1f万", n / 10_000.0)
        n <= 0.0 -> ""
        else -> grouped(n, 0)
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            v.toFloat(),
            root.resources.displayMetrics
        ).toInt()
}
