package com.glooby.remotepanel.ui

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.LinearLayout
import android.widget.TextView
import com.glooby.remotepanel.data.Theme

/**
 * Layout system for the 1080×1920 portrait kiosk.
 * Every size below is in design pixels on a 1080-wide canvas; [px] scales it to the real screen.
 */
object Ui {
    const val DESIGN_W = 1080f
    const val DESIGN_H = 1920f

    var scale = 1f
        private set

    fun init(activity: Activity) {
        val w: Int
        val h: Int
        if (Build.VERSION.SDK_INT >= 30) {
            val b = activity.windowManager.currentWindowMetrics.bounds
            w = b.width(); h = b.height()
        } else {
            val m = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.getRealMetrics(m)
            w = m.widthPixels; h = m.heightPixels
        }
        val shortSide = minOf(w, h).toFloat()
        val longSide = maxOf(w, h).toFloat()
        scale = minOf(shortSide / DESIGN_W, longSide / DESIGN_H).coerceAtLeast(0.5f)
    }

    fun px(design: Int): Int = (design * scale + 0.5f).toInt()
    fun pxf(design: Float): Float = design * scale

    // Type scale (design px). Nothing on a page goes below META so it reads from across a room.
    const val HERO = 168
    const val DISPLAY = 104
    const val H1 = 68
    const val H2 = 54
    const val BODY = 46
    const val META = 38

    // Spacing (design px).
    const val PAD = 36
    const val GAP = 20
    const val RADIUS = 28

    enum class W { REGULAR, MEDIUM, BOLD }

    private val medium: Typeface by lazy {
        if (Build.VERSION.SDK_INT >= 28) Typeface.create(Typeface.DEFAULT, 500, false)
        else Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }
    private val bold: Typeface by lazy {
        if (Build.VERSION.SDK_INT >= 28) Typeface.create(Typeface.DEFAULT, 700, false)
        else Typeface.DEFAULT_BOLD
    }
    val numeric: Typeface by lazy { Typeface.create("sans-serif-condensed", Typeface.BOLD) }

    fun text(
        ctx: Context,
        value: CharSequence,
        size: Int,
        color: Int = Theme.text(),
        weight: W = W.REGULAR,
        lines: Int = 1,
        gravity: Int = Gravity.START or Gravity.CENTER_VERTICAL,
    ): TextView = TextView(ctx).apply {
        text = value
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_PX, pxf(size.toFloat()))
        typeface = when (weight) {
            W.REGULAR -> Typeface.DEFAULT
            W.MEDIUM -> medium
            W.BOLD -> bold
        }
        maxLines = lines
        if (lines == 1) isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        this.gravity = gravity
        setLineSpacing(0f, if (lines > 1) 1.12f else 1f)
        includeFontPadding = lines > 1
    }

    /** Big tabular numbers: prices, temperatures, percentages. */
    fun number(ctx: Context, value: CharSequence, size: Int, color: Int = Theme.text()): TextView =
        text(ctx, value, size, color, W.BOLD).apply { typeface = numeric }

    fun rounded(color: Int, radius: Int = RADIUS, stroke: Int = 0, strokeColor: Int = 0): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = pxf(radius.toFloat())
            if (stroke > 0) setStroke(px(stroke), strokeColor)
        }

    fun column(ctx: Context, bg: Int? = null, pad: Int = 0, radius: Int = RADIUS): LinearLayout =
        LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            if (bg != null) background = rounded(bg, radius)
            if (pad > 0) setPadding(px(pad), px(pad), px(pad), px(pad))
        }

    fun row(ctx: Context, bg: Int? = null, pad: Int = 0, radius: Int = RADIUS): LinearLayout =
        column(ctx, bg, pad, radius).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

    fun card(ctx: Context, horizontal: Boolean = false, bg: Int = Theme.surface()): LinearLayout =
        (if (horizontal) row(ctx, bg) else column(ctx, bg)).apply {
            setPadding(px(30), px(24), px(30), px(24))
        }

    fun pill(ctx: Context, value: String, bg: Int, fg: Int = Theme.text(), size: Int = META): TextView =
        text(ctx, value, size, fg, W.BOLD, gravity = Gravity.CENTER).apply {
            background = rounded(bg, 999)
            setPadding(px(18), px(4), px(18), px(4))
        }

    fun clip(view: View, radius: Int = RADIUS) {
        val r = pxf(radius.toFloat())
        view.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(v: View, outline: Outline) {
                outline.setRoundRect(0, 0, v.width, v.height, r)
            }
        }
        view.clipToOutline = true
    }

    // Layout params
    fun fill(): ViewGroup.LayoutParams =
        ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)

    fun wide(height: Int = -1, top: Int = 0, bottom: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            if (height < 0) LinearLayout.LayoutParams.WRAP_CONTENT else px(height)
        ).apply { topMargin = px(top); bottomMargin = px(bottom) }

    /** Vertical share of the remaining height. */
    fun flexV(weight: Float = 1f, bottom: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, weight).apply { bottomMargin = px(bottom) }

    /** Horizontal share of the row width. */
    fun flexH(weight: Float = 1f, end: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, weight).apply { marginEnd = px(end) }

    /** Fixed size in design px; pass -1 (match) or -2 (wrap) through unscaled. */
    fun fixed(w: Int, h: Int, end: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(if (w < 0) w else px(w), if (h < 0) h else px(h)).apply { marginEnd = px(end) }

    fun wrap(start: Int = 0, end: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { marginStart = px(start); marginEnd = px(end) }

    fun spacer(ctx: Context): View = View(ctx)
}

/** Horizontal bar: track plus a filled share, optionally offset (for temperature ranges). */
class BarView(ctx: Context, private val track: Int, private val fill: Int) : View(ctx) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    var from = 0f
        set(v) { field = v.coerceIn(0f, 1f); invalidate() }
    var to = 0f
        set(v) { field = v.coerceIn(0f, 1f); invalidate() }

    override fun onDraw(canvas: Canvas) {
        val h = height.toFloat()
        val w = width.toFloat()
        val r = h / 2f
        paint.color = track
        rect.set(0f, 0f, w, h)
        canvas.drawRoundRect(rect, r, r, paint)
        if (to > from) {
            paint.color = fill
            rect.set(w * from, 0f, maxOf(w * to, w * from + h), h)
            canvas.drawRoundRect(rect, r, r, paint)
        }
    }
}
