package com.glooby.remotepanel.data

import android.graphics.Color
import androidx.core.graphics.ColorUtils
import java.util.Calendar

/**
 * Dark wall-screen palette. The background stays near-black so cards and text carry the contrast;
 * each weekday only changes the accent and a faint background tint.
 */
object Theme {
    // Monday=0 … Sunday=6: background tint, accent
    private val week = arrayOf(
        intArrayOf(0x0B1426, 0x5EC8FF),
        intArrayOf(0x0A1A16, 0x4FE0A0),
        intArrayOf(0x140F24, 0xB89CFF),
        intArrayOf(0x1A130A, 0xFFB547),
        intArrayOf(0x1A0D16, 0xFF7AB6),
        intArrayOf(0x0A1720, 0x53D6E8),
        intArrayOf(0x17140A, 0xF2C94C),
    )

    private fun dayIndex(): Int {
        val wd = Calendar.getInstance().get(Calendar.DAY_OF_WEEK) // Sun=1
        return if (wd == Calendar.SUNDAY) 6 else wd - 2
    }

    fun dayName(): String = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")[dayIndex()]

    private fun hex(rgb: Int): Int = Color.rgb((rgb shr 16) and 0xff, (rgb shr 8) and 0xff, rgb and 0xff)

    fun bg(): Int = hex(week[dayIndex()][0])
    fun accent(): Int = hex(week[dayIndex()][1])

    /** Card surface: background lifted toward white. */
    fun surface(): Int = ColorUtils.blendARGB(bg(), Color.WHITE, 0.075f)
    fun surfaceHigh(): Int = ColorUtils.blendARGB(bg(), Color.WHITE, 0.13f)
    fun track(): Int = ColorUtils.blendARGB(bg(), Color.WHITE, 0.2f)

    fun text(): Int = Color.rgb(0xF4, 0xF7, 0xFB)
    fun textDim(): Int = Color.rgb(0xB4, 0xC0, 0xD0)
    fun textFaint(): Int = Color.rgb(0x86, 0x93, 0xA6)

    fun ok(): Int = Color.rgb(0x3D, 0xD6, 0x8C)
    fun warn(): Int = Color.rgb(0xFF, 0xC8, 0x3A)
    fun bad(): Int = Color.rgb(0xFF, 0x5C, 0x6C)

    /** China market convention: red is up, green is down. */
    fun up(): Int = Color.rgb(0xFF, 0x4D, 0x5E)
    fun down(): Int = Color.rgb(0x2E, 0xD1, 0x7F)
    fun upBg(): Int = ColorUtils.blendARGB(surface(), up(), 0.22f)
    fun downBg(): Int = ColorUtils.blendARGB(surface(), down(), 0.2f)
    fun move(percent: Double): Int = when {
        percent > 0.0001 -> up()
        percent < -0.0001 -> down()
        else -> textDim()
    }

    private val tints = intArrayOf(0x2F8F9D, 0x3E6FD8, 0x7A5AD8, 0xD9822B, 0xC94F86, 0x3A9D5D)

    /** Category colour for chips, rank badges and image fallbacks. */
    fun cardTint(index: Int): Int = hex(tints[Math.floorMod(index, tints.size)])

    // Kept for the settings screen.
    fun card(): Int = surfaceHigh()
    fun border(): Int = textDim()
}
