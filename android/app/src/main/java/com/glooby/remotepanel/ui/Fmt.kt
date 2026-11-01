package com.glooby.remotepanel.ui

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

object Fmt {
    private val us = DecimalFormatSymbols(Locale.US)

    fun price(v: Double, crypto: Boolean = false): String {
        if (v.isNaN() || v == 0.0) return "--"
        val pattern = when {
            v >= 10000 -> "#,##0.0"
            crypto && v < 1 -> "0.0000"
            crypto && v < 10 -> "0.000"
            else -> "#,##0.00"
        }
        return DecimalFormat(pattern, us).format(v)
    }

    fun percent(v: Double): String {
        if (v.isNaN()) return "--"
        val sign = if (v > 0.0001) "+" else ""
        return sign + String.format(Locale.US, "%.2f%%", v)
    }

    fun change(v: Double, crypto: Boolean = false): String {
        if (v.isNaN()) return "--"
        val sign = if (v > 0) "+" else ""
        return sign + if (crypto && abs(v) < 10) String.format(Locale.US, "%.3f", v) else String.format(Locale.US, "%.2f", v)
    }

    /** 1234567 → 123.5万, 1.2e9 → 12.0亿 */
    fun big(v: Double): String = when {
        v.isNaN() || v <= 0 -> "--"
        v >= 1e8 -> String.format(Locale.US, "%.1f亿", v / 1e8)
        v >= 1e4 -> String.format(Locale.US, "%.1f万", v / 1e4)
        else -> v.roundToInt().toString()
    }

    fun count(v: Long): String = if (v <= 0) "" else big(v.toDouble())

    fun temp(v: Double): String = if (v.isNaN()) "--" else "${v.roundToInt()}°"

    fun clock(ms: Long): String = if (ms <= 0) "--:--" else SimpleDateFormat("HH:mm", Locale.CHINA).format(Date(ms))

    /** “刚刚 / 12 分钟前 / 3 小时前 / 10月30日” */
    fun ago(ms: Long, now: Long = System.currentTimeMillis()): String {
        if (ms <= 0) return ""
        val d = (now - ms) / 60_000L
        return when {
            d < 1 -> "刚刚"
            d < 60 -> "$d 分钟前"
            d < 24 * 60 -> "${d / 60} 小时前"
            else -> SimpleDateFormat("M月d日", Locale.CHINA).format(Date(ms))
        }
    }

    fun duration(seconds: Int): String {
        if (seconds <= 0) return ""
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s) else String.format(Locale.US, "%d:%02d", m, s)
    }
}
