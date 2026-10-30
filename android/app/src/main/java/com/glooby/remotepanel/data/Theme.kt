package com.glooby.remotepanel.data

import android.graphics.Color
import java.util.Calendar

object Theme {
    // Monday=0 … Sunday=6 — bg, card, border, accent
    private val week = arrayOf(
        intArrayOf(0x142D78, 0x1D4EC4, 0x8EE7FF, 0x5EF0FF),
        intArrayOf(0x0C3A2C, 0x146B48, 0x8CFFC4, 0x5DFFB0),
        intArrayOf(0x24124C, 0x4A2490, 0xD4B4FF, 0xC9A0FF),
        intArrayOf(0x3A220C, 0x6A3C14, 0xFFD090, 0xFFC15A),
        intArrayOf(0x3A1230, 0x7A2458, 0xFFB4D4, 0xFF7AB6),
        intArrayOf(0x0C3044, 0x145878, 0x9AD8FF, 0x5EC8FF),
        intArrayOf(0x241C0C, 0x4A3A18, 0xF0D090, 0xF0C14A),
    )

    private fun dayIndex(): Int {
        val wd = Calendar.getInstance().get(Calendar.DAY_OF_WEEK) // Sun=1
        return if (wd == Calendar.SUNDAY) 6 else wd - 2
    }

    fun dayName(): String = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")[dayIndex()]

    private fun hex(rgb: Int): Int = Color.rgb((rgb shr 16) and 0xff, (rgb shr 8) and 0xff, rgb and 0xff)

    fun bg(): Int = hex(week[dayIndex()][0])
    fun card(): Int = hex(week[dayIndex()][1])
    fun border(): Int = hex(week[dayIndex()][2])
    fun accent(): Int = hex(week[dayIndex()][3])
}
