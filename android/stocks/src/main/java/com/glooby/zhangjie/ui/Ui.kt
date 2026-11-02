package com.glooby.zhangjie.ui

import android.app.Activity
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.TextViewCompat
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.round

/** Sizes are design pixels on a 1080×1920 portrait canvas. */
object Ui {
    const val DESIGN_W = 1080f
    const val DESIGN_H = 1920f
    val BG = 0xFF0B1220.toInt()
    val CARD = 0xFF16233A.toInt()
    val UP = 0xFFF0444C.toInt()
    val DOWN = 0xFF1EAE5A.toInt()
    val DIM = 0xFF9AA4B2.toInt()
    val TEXT = 0xFFFFFFFF.toInt()

    var scale = 1f
        private set

    private val numeric: Typeface = Typeface.create("sans-serif-condensed", Typeface.BOLD)
    private val medium: Typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    private val zone: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")
    private val money: NumberFormat = NumberFormat.getNumberInstance(Locale.CHINA).apply {
        minimumFractionDigits = 2
        maximumFractionDigits = 2
        isGroupingUsed = true
    }

    fun init(activity: Activity) {
        val b = if (android.os.Build.VERSION.SDK_INT >= 30) {
            activity.windowManager.currentWindowMetrics.bounds
        } else {
            val m = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.getRealMetrics(m)
            android.graphics.Rect(0, 0, m.widthPixels, m.heightPixels)
        }
        val shortSide = minOf(b.width(), b.height()).toFloat()
        val longSide = maxOf(b.width(), b.height()).toFloat()
        scale = minOf(shortSide / DESIGN_W, longSide / DESIGN_H).coerceAtLeast(0.5f)
    }

    fun px(design: Int): Int = (design * scale + 0.5f).toInt()

    fun moveColor(n: Double): Int = when {
        n > 0.0001 -> UP
        n < -0.0001 -> DOWN
        else -> DIM
    }

    fun grouped(n: Double): String = money.format(abs(n))

    fun signed(n: Double): String {
        val body = grouped(n)
        return when {
            n > 0.00005 -> "+$body"
            n < -0.00005 -> "-$body"
            else -> body
        }
    }

    fun pct(n: Double): String = signed(n) + "%"

    fun shares(n: Double): String = if (abs(n - round(n)) < 0.001) round(n).toInt().toString() else grouped(n)

    fun clock(date: Date = Date()): String {
        val fmt = SimpleDateFormat("HH:mm", Locale.CHINA)
        fmt.timeZone = zone
        return fmt.format(date)
    }

    fun stamp(at: Long): String {
        if (at <= 0) return ""
        val fmt = SimpleDateFormat("MM-dd HH:mm", Locale.CHINA)
        fmt.timeZone = zone
        return "更新 " + fmt.format(Date(at))
    }

    fun label(ctx: android.content.Context, text: String, size: Int, color: Int, bold: Boolean = false): TextView =
        TextView(ctx).apply {
            this.text = text
            setTextColor(color)
            gravity = Gravity.CENTER
            typeface = if (bold) Typeface.DEFAULT_BOLD else medium
            setTextSize(TypedValue.COMPLEX_UNIT_PX, px(size).toFloat())
            fontFeatureSettings = "tnum"
        }

    fun number(ctx: android.content.Context, text: String, size: Int, color: Int): TextView =
        label(ctx, text, size, color, bold = true).apply {
            typeface = numeric
            TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration(
                this,
                px((size * 0.35f).toInt().coerceAtLeast(12)),
                px(size),
                px(2).coerceAtLeast(1),
                TypedValue.COMPLEX_UNIT_PX,
            )
        }

    fun wide(height: Int = ViewGroup.LayoutParams.WRAP_CONTENT, bottom: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, if (height > 0) px(height) else height).apply {
            bottomMargin = px(bottom)
        }

    fun flex(weight: Float = 1f, end: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight).apply {
            marginEnd = px(end)
        }
}
