package com.glooby.remotepanel.pages

import android.content.Context
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Theme
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class HelloPage(context: Context) : PanelPage {
    private val title = TextView(context)
    private val clock = TextView(context)
    private val sub = TextView(context)
    override val root: LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setPadding(dp(24), dp(24), dp(24), dp(24))
        setBackgroundColor(Theme.bg())
        title.setTextColor(0xFFFFFFFF.toInt())
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 42f)
        title.typeface = Typeface.DEFAULT_BOLD
        title.gravity = Gravity.CENTER
        clock.setTextColor(Theme.accent())
        clock.setTextSize(TypedValue.COMPLEX_UNIT_SP, 56f)
        clock.typeface = Typeface.MONOSPACE
        clock.gravity = Gravity.CENTER
        sub.setTextColor(Theme.border())
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        sub.gravity = Gravity.CENTER
        addView(title)
        addView(clock, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(24)
        })
        addView(sub, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(16)
        })
    }

    override fun bind(state: PanelState) {
        title.text = state.hello.ifBlank { "你好\nRemotePanel" }
        clock.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        sub.text = "${Theme.dayName()} · 家庭信息屏"
        root.setBackgroundColor(Theme.bg())
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), root.resources.displayMetrics).toInt()
}
