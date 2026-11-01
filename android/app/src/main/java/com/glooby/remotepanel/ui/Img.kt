package com.glooby.remotepanel.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.widget.ImageView
import androidx.core.graphics.ColorUtils
import com.bumptech.glide.Glide
import com.bumptech.glide.RequestBuilder
import com.bumptech.glide.RequestManager
import com.bumptech.glide.load.DecodeFormat
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.load.resource.drawable.DrawableTransitionOptions
import com.glooby.remotepanel.data.Theme

/** Network images with a designed fallback, so a missing cover never shows a blank or a stock icon. */
object Img {
    /** Images that look like real content on the source page but are site chrome or lazy-load stubs. */
    private val junk = listOf(
        "1210e985ce56b56f20e06094f6817d28", // gamer520 site banner
        "/logo", "logo.", "favicon", "avatar", "/icon", "placeholder", "loading.", "blank.", "default."
    )

    fun usable(url: String?): Boolean {
        val u = url?.trim().orEmpty()
        if (!u.startsWith("http://") && !u.startsWith("https://") && !u.startsWith("//")) return false
        val low = u.lowercase()
        if (low.substringBefore('?').endsWith(".svg")) return false
        return junk.none { low.contains(it) }
    }

    /** Ask CDNs for a thumbnail near the display size instead of the original upload. */
    fun normalize(raw: String, w: Int, h: Int): String {
        var u = raw.trim()
        if (u.startsWith("//")) u = "https:$u"
        val host = u.substringAfter("://").substringBefore('/').lowercase()
        if (u.startsWith("http://") && (host.endsWith("hdslb.com") || host.endsWith("qhimgs1.com") ||
                host.endsWith("pipi.cn") || host.endsWith("meituan.net") || host.endsWith("steamstatic.com"))
        ) u = "https://" + u.removePrefix("http://")
        val tw = w.coerceIn(120, 720)
        val th = h.coerceIn(80, 720)
        when {
            host.endsWith("hdslb.com") -> {
                val base = u.substringBefore('@')
                u = "$base@${tw}w_${th}h_1c.jpg"
            }
            u.contains("/w.h/") -> u = u.replace("/w.h/", "/$tw.$th/")
            host.endsWith("pipi.cn") || host.endsWith("meituan.net") -> {
                val base = u.substringBefore('?')
                u = "$base?imageMogr2/thumbnail/${tw}x${th}/quality/85"
            }
        }
        return u
    }

    /**
     * Load [url] into [view] at about [w]×[h] design px. While loading and on failure the view shows a
     * tinted tile with the title's first character and [label].
     */
    fun load(view: ImageView, url: String?, title: String, label: String, seed: Int, w: Int, h: Int) {
        val fallback = FallbackDrawable(title, label, Theme.cardTint(seed))
        val glide = Glide.with(view)
        if (!usable(url)) {
            glide.clear(view)
            view.setImageDrawable(fallback)
            return
        }
        // Plain tile while loading; the lettered tile only when the image really failed.
        request(glide, url!!, w, h)
            .placeholder(android.graphics.drawable.ColorDrawable(Theme.surfaceHigh()))
            .error(fallback)
            .transition(DrawableTransitionOptions.withCrossFade(220))
            .into(view)
    }

    /** Fetch and decode the next page's images at the same size so they show instantly. */
    fun preload(ctx: Context, url: String?, w: Int, h: Int) {
        if (!usable(url)) return
        request(Glide.with(ctx.applicationContext), url!!, w, h).preload(Ui.px(w).coerceAtLeast(1), Ui.px(h).coerceAtLeast(1))
    }

    private fun request(glide: RequestManager, url: String, w: Int, h: Int): RequestBuilder<Drawable> {
        val pw = Ui.px(w).coerceAtLeast(1)
        val ph = Ui.px(h).coerceAtLeast(1)
        return glide.load(normalize(url, pw, ph))
            .override(pw, ph)
            .centerCrop()
            .format(DecodeFormat.PREFER_RGB_565)
            .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
    }

    /** Cancel requests and drop bitmaps under [root] when a page leaves the screen. */
    fun release(root: android.view.View) {
        if (root is ImageView) {
            runCatching { Glide.with(root.context.applicationContext).clear(root) }
            root.setImageDrawable(null)
        } else if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) release(root.getChildAt(i))
        }
    }

    fun view(ctx: Context, radius: Int = Ui.RADIUS): ImageView = ImageView(ctx).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
        Ui.clip(this, radius)
    }
}

/** Gradient tile with a large initial and a source label. */
class FallbackDrawable(title: String, private val label: String, tint: Int) : Drawable() {
    private val initial = title.trim().firstOrNull { !it.isWhitespace() && it != '【' && it != '[' && it != '#' }
        ?.toString()?.uppercase().orEmpty()
    private val top = ColorUtils.blendARGB(tint, 0xFF000000.toInt(), 0.15f)
    private val bottom = ColorUtils.blendARGB(tint, 0xFF000000.toInt(), 0.55f)
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val big = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xE6FFFFFF.toInt()
        typeface = Typeface.DEFAULT_BOLD
        textAlign = Paint.Align.CENTER
    }
    private val small = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xB3FFFFFF.toInt()
        typeface = Typeface.DEFAULT_BOLD
    }

    override fun draw(canvas: Canvas) {
        val b = bounds
        if (b.width() <= 0 || b.height() <= 0) return
        fill.shader = LinearGradient(0f, b.top.toFloat(), 0f, b.bottom.toFloat(), top, bottom, Shader.TileMode.CLAMP)
        canvas.drawRect(b, fill)
        val side = minOf(b.width(), b.height()).toFloat()
        big.textSize = side * 0.42f
        val cy = b.exactCenterY() - (big.descent() + big.ascent()) / 2f
        canvas.drawText(initial, b.exactCenterX(), cy, big)
        if (label.isNotBlank() && side > Ui.pxf(120f)) {
            small.textSize = (side * 0.11f).coerceAtLeast(Ui.pxf(26f))
            val pad = side * 0.07f
            canvas.drawText(label, b.left + pad, b.bottom - pad, small)
        }
    }

    override fun setAlpha(alpha: Int) {
        fill.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        fill.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.OPAQUE
}
