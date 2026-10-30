package com.glooby.remotepanel.pages

import android.content.Context
import android.util.TypedValue
import android.view.LayoutInflater
import android.widget.LinearLayout
import android.widget.TextView
import com.glooby.remotepanel.R
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Theme

class WeatherPage(context: Context) : PanelPage {
    override val root = LayoutInflater.from(context).inflate(R.layout.page_simple_scroll, null)
    private val content: LinearLayout = root.findViewById(R.id.content)

    override fun bind(state: PanelState) {
        content.removeAllViews()
        root.setBackgroundColor(Theme.bg())
        val w = state.weather
        if (w == null) {
            content.addView(label(root.context, "天气还没准备好", 22, Theme.border()))
            return
        }
        content.addView(label(root.context, w.city, 22, Theme.border()))
        content.addView(label(root.context, w.temperature, 72, 0xFFFFFFFF.toInt()).apply {
            setPadding(0, dp(8), 0, 0)
        })
        content.addView(label(root.context, "${w.description} · ${w.wind}", 24, Theme.accent()))
        content.addView(label(root.context, "本周", 20, Theme.accent()).apply {
            setPadding(0, dp(24), 0, dp(8))
        })
        for (row in w.weekly) {
            val line = TextView(root.context)
            line.text = "${row.first}    ${row.second}    ${row.third}"
            line.setTextColor(0xFFFFFFFF.toInt())
            line.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            line.setBackgroundColor(Theme.card())
            line.setPadding(dp(14), dp(12), dp(14), dp(12))
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.bottomMargin = dp(8)
            content.addView(line, lp)
        }
    }

    private fun label(ctx: Context, text: String, sp: Int, color: Int): TextView =
        TextView(ctx).apply {
            this.text = text
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sp.toFloat())
        }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), root.resources.displayMetrics).toInt()
}
