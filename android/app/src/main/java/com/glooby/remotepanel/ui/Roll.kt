package com.glooby.remotepanel.ui

import android.animation.ValueAnimator
import android.widget.TextView
import java.text.DecimalFormat
import java.util.Locale

/**
 * When a clock, temperature, price, or star count changes, roll the digits
 * instead of swapping the string in place.
 */
object Roll {
    private val last = HashMap<String, String>()
    private val number = Regex("""[+-]?\d[\d,]*\.?\d*""")

    fun bind(tv: TextView, key: String, text: String) {
        val prev = last.put(key, text)
        if (prev == null || prev == text) {
            tv.text = text
            return
        }
        val match = number.find(text)
        val from = number.find(prev)?.value?.replace(",", "")?.toFloatOrNull()
        val to = match?.value?.replace(",", "")?.toFloatOrNull()
        if (from == null || to == null || match == null || text.any { it == '万' || it == '亿' }) {
            slide(tv, text)
            return
        }
        val prefix = text.substring(0, match.range.first)
        val suffix = text.substring(match.range.last + 1)
        val sample = match.value
        val decimals = sample.substringAfter('.', "").length
        val grouped = sample.contains(',')
        val pattern = buildString {
            append(if (grouped) "#,##0" else "0")
            if (decimals > 0) append('.').append("0".repeat(decimals))
        }
        val fmt = DecimalFormat(pattern, java.text.DecimalFormatSymbols(Locale.US))
        ValueAnimator.ofFloat(from, to).apply {
            duration = 420
            addUpdateListener { tv.text = prefix + fmt.format((it.animatedValue as Float).toDouble()) + suffix }
            start()
        }
    }

    /** HH:mm. The whole time slides up when the minute changes. */
    fun clock(tv: TextView, text: String, key: String = "header-clock") {
        val prev = last.put(key, text)
        if (prev == null || prev == text) {
            tv.text = text
            return
        }
        tv.text = prev
        slide(tv, text)
    }

    private fun slide(tv: TextView, text: String) {
        val h = tv.height.toFloat().takeIf { it > 1f } ?: tv.textSize
        tv.animate().cancel()
        tv.animate().translationY(-h * 0.6f).alpha(0f).setDuration(160).withEndAction {
            tv.text = text
            tv.translationY = h * 0.6f
            tv.animate().translationY(0f).alpha(1f).setDuration(200).start()
        }.start()
    }
}
