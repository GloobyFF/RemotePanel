package com.glooby.remotepanel.pages

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.provider.CalendarContract
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.bumptech.glide.Glide
import com.glooby.remotepanel.data.CoverCard
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.PostCard
import com.glooby.remotepanel.data.PrintState
import com.glooby.remotepanel.data.QuoteItem
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.ui.KioskActivity
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.round

/**
 * Portrait pages composed for a 1080×1920 phone.
 * Sizes are in dp so a 1080×1920 xxhdpi screen (360×640 dp) matches the design.
 */
class BoardPage(
    private val context: android.content.Context,
    private val pageId: String
) : PanelPage {
    private val content = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(10), dp(6), dp(10), dp(8))
    }
    override val root: ScrollView = ScrollView(context).apply {
        isFillViewport = true
        addView(content, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))
    }
    private var serial = 0

    override fun bind(state: PanelState) {
        serial = 0
        content.removeAllViews()
        root.setBackgroundColor(Theme.bg())
        when (pageId) {
            "hello" -> renderHello(state)
            "schedule" -> renderSchedule()
            "weather" -> renderWeather(state)
            "daily-news" -> renderNews(state)
            "github-news" -> renderGithub(state)
            "x-news" -> renderTrends(state)
            "xiaohongshu-hot" -> renderPosts(state.xhs, "小红书还在读取")
            "bilibili-hot" -> renderPosts(state.bili, "哔哩哔哩还在读取")
            "stocks-cn" -> renderQuotes(state.stocks, crypto = false)
            "crypto" -> renderQuotes(state.crypto, crypto = true)
            "print" -> renderPrint(state.printer)
            "movie-now-showing" -> renderCovers(state.movies, "电影还在读取")
            "steam-new-releases" -> renderCovers(state.steamNew, "Steam 新游还在读取")
            "steam-new-releases-2" -> renderCovers(state.steamHot, "Steam 热销还在读取")
            "gamer520-pc-latest" -> renderCovers(state.pcGames, "PC 游戏还在读取")
            "gamer520-switch-latest" -> renderCovers(state.switchGames, "Switch 还在读取")
            "ps5-games-latest" -> renderCovers(state.ps5Games, "PS5 还在读取")
            else -> note("这一页还没有内容")
        }
    }

    private fun renderHello(state: PanelState) {
        val period = state.helloPeriod.ifBlank { "你好" }
        val head = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        val left = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        left.addView(text(period, 28, Theme.accent(), bold = true))
        left.addView(text(state.hello.ifBlank { "正在准备一句问候" }, 15, Color.WHITE).apply { maxLines = 4 })
        left.addView(text(SimpleDateFormat("M月d日 EEEE", Locale.CHINA).format(Date()), 13, Theme.border()))
        head.addView(left, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.4f))
        val w = state.weather
        val side = card()
        side.addView(text(w?.temperature ?: "--", 32, Color.WHITE, bold = true))
        side.addView(text(listOfNotNull(w?.city, w?.description).joinToString(" "), 13, Color.WHITE).apply { maxLines = 2 })
        if (w != null) side.addView(text(w.wind, 12, Theme.border()))
        head.addView(side, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = dp(8) })
        content.addView(head, match())
    }

    private fun renderWeather(state: PanelState) {
        val w = state.weather
        if (w == null) {
            note("天气还没准备好")
            return
        }
        val hero = card()
        hero.orientation = LinearLayout.HORIZONTAL
        val heroText = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        heroText.addView(text(w.city, 13, Theme.border()))
        heroText.addView(text(w.temperature, 36, Color.WHITE, bold = true))
        heroText.addView(text("${w.description}  ${w.wind}", 14, Color.WHITE))
        heroText.addView(text(w.weekly.firstOrNull()?.second ?: "", 13, Theme.border()))
        hero.addView(heroText, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        content.addView(hero, match())
        val rows = w.weekly.take(6).chunked(3)
        for (row in rows) {
            val line = rowLine()
            for (day in row) {
                val cell = card()
                cell.addView(text(weekday(day.first), 12, Theme.border()))
                cell.addView(text(day.third, 14, Color.WHITE, bold = true))
                cell.addView(text(day.second, 12, Color.WHITE))
                line.addView(cell, weight())
            }
            while (line.childCount < 3) line.addView(View(context), weight())
            content.addView(line)
        }
        content.addView(text("VPS 用量", 14, Theme.accent(), bold = true).apply {
            setPadding(0, dp(16), 0, dp(8))
        })
        val vps = state.vps
        if (vps == null) {
            note("VPS 令牌还没填写。设置里可以补上。")
        } else {
            val band = rowLine()
            for (pair in listOf("已用" to vps.used, "剩余" to vps.remain, "状态" to vps.status, "周期" to vps.cycle)) {
                val cell = card()
                cell.addView(text(pair.first, 11, Theme.border()))
                cell.addView(text(pair.second, 13, Color.WHITE, bold = true).apply { maxLines = 3 })
                band.addView(cell, weight())
            }
            content.addView(band)
        }
    }

    private fun renderNews(state: PanelState) {
        if (state.dailyNews.isEmpty()) {
            note("新闻还在读取")
            return
        }
        state.dailyNews.take(8).forEachIndexed { i, item ->
            val card = card(i)
            card.addView(text("%02d  ${item.title}".format(i + 1), 15, Color.WHITE, bold = true).apply { maxLines = 2 })
            if (item.summary.isNotBlank()) {
                card.addView(text(item.summary.take(72), 12, Theme.border()).apply {
                    maxLines = 2
                })
            }
            content.addView(card, match())
        }
    }

    private fun renderGithub(state: PanelState) {
        if (state.github.isEmpty()) {
            note("热门项目还在读取")
            return
        }
        state.github.forEachIndexed { i, repo ->
            val card = card(i)
            card.addView(text("%02d  ${repo.name}".format(i + 1), 14, Color.WHITE, bold = true).apply { maxLines = 1 })
            card.addView(text(repo.description, 12, Color.WHITE).apply { maxLines = 2 })
            if (repo.stars.isNotBlank()) card.addView(text(repo.stars, 11, Theme.border()))
            content.addView(card, match())
        }
    }

    private fun renderTrends(state: PanelState) {
        if (state.trends.isEmpty()) {
            note("话题还在读取")
            return
        }
        content.addView(text("美国区热门", 14, Theme.border()).apply { setPadding(0, 0, 0, dp(8)) })
        state.trends.chunked(2).forEach { row ->
            val line = rowLine()
            row.forEach { trend ->
                val cell = card()
                cell.addView(text(trend.title, 15, Color.WHITE, bold = true).apply { maxLines = 2 })
                cell.addView(text(trend.blurb, 11, Theme.border()).apply { maxLines = 2 })
                line.addView(cell, weight())
            }
            if (row.size == 1) line.addView(View(context), weight())
            content.addView(line)
        }
    }

    private fun renderPosts(items: List<PostCard>, empty: String) {
        if (items.isEmpty()) {
            note(empty)
            return
        }
        items.take(6).chunked(2).forEach { row ->
            val line = rowLine()
            row.forEach { post ->
                val cell = card()
                if (post.imageUrl.isNotBlank()) {
                    val image = ImageView(context).apply {
                        scaleType = ImageView.ScaleType.CENTER_CROP
                        layoutParams = LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            dp(96)
                        )
                    }
                    Glide.with(context.applicationContext).load(post.imageUrl).into(image)
                    cell.addView(image)
                }
                cell.addView(text(post.title, 13, Color.WHITE, bold = true).apply {
                    maxLines = 2
                    setPadding(0, dp(4), 0, 0)
                })
                cell.addView(text(post.summary, 11, Theme.border()).apply { maxLines = 3 })
                line.addView(cell, weight())
            }
            if (row.size == 1) line.addView(View(context), weight())
            content.addView(line)
        }
    }

    private fun renderQuotes(items: List<QuoteItem>, crypto: Boolean) {
        if (items.isEmpty()) {
            note(if (crypto) "正在读取比特币、以太坊等行情" else "正在读取沪深行情")
            return
        }
        val up = items.count { it.percent > 0.0001 }
        val down = items.count { it.percent < -0.0001 }
        content.addView(text("涨 $up    跌 $down", 14, Theme.border()).apply { setPadding(0, 0, 0, dp(8)) })
        items.forEach { item ->
            val bg = when {
                item.percent > 0.0001 -> Theme.up()
                item.percent < -0.0001 -> Theme.down()
                else -> Theme.card()
            }
            val card = card(color = bg)
            card.orientation = LinearLayout.HORIZONTAL
            card.gravity = Gravity.CENTER_VERTICAL
            val sign = if (item.percent > 0) "+" else ""
            val nameCol = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
            nameCol.addView(text(item.name.ifBlank { item.symbol }, 14, Color.WHITE, bold = true).apply { maxLines = 1 })
            nameCol.addView(text(item.symbol, 11, Theme.border()))
            card.addView(nameCol, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            card.addView(text(formatPrice(item.price, crypto), 22, Color.WHITE, bold = true))
            card.addView(text("$sign${String.format(Locale.US, "%.2f", item.percent)}%", 14, Color.WHITE).apply {
                setPadding(dp(8), 0, 0, 0)
            })
            content.addView(card, match())
        }
    }

    private fun renderCovers(items: List<CoverCard>, empty: String) {
        if (items.isEmpty()) {
            note(empty)
            return
        }
        items.take(9).chunked(3).forEach { row ->
            val line = rowLine()
            row.forEach { cover ->
                val cell = card()
                val image = ImageView(context).apply {
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        dp(108)
                    )
                }
                if (cover.imageUrl.isNotBlank()) {
                    Glide.with(context.applicationContext).load(cover.imageUrl).into(image)
                }
                cell.addView(image)
                cell.addView(text(cover.title, 11, Color.WHITE, bold = true).apply {
                    maxLines = 2
                    setPadding(0, dp(4), 0, 0)
                })
                if (cover.meta.isNotBlank()) cell.addView(text(cover.meta, 10, Theme.border()).apply { maxLines = 1 })
                line.addView(cell, weight())
            }
            while (line.childCount < 3) line.addView(View(context), weight())
            content.addView(line)
        }
    }

    private fun renderPrint(printer: PrintState?) {
        if (printer == null) {
            note("打印机还没读到。设置里填写接口地址。")
            return
        }
        content.addView(text(if (printer.online) "在线  ${printer.status}" else "离线  ${printer.status}", 14, Theme.border()))
        val hero = card()
        hero.addView(text(printer.title, 16, Color.WHITE))
        hero.addView(text(printer.progress, 28, Color.WHITE, bold = true))
        if (printer.detail.isNotBlank()) hero.addView(text(printer.detail, 13, Theme.border()).apply { maxLines = 2 })
        content.addView(hero, match())
        if (printer.temps.isNotEmpty()) {
            val line = rowLine()
            printer.temps.take(3).forEach { chip ->
                val cell = card()
                cell.addView(text(chip.label, 13, Theme.border()))
                cell.addView(text(chip.value, 18, Color.WHITE, bold = true))
                line.addView(cell, weight())
            }
            content.addView(line)
        }
        if (printer.slots.isNotEmpty()) {
            content.addView(text("耗材料仓 · ${printer.slots.size} 槽", 16, Theme.accent()).apply {
                setPadding(0, dp(10), 0, dp(6))
            })
            printer.slots.chunked(3).forEach { row ->
                val line = rowLine()
                row.forEach { slot ->
                    val ink = inkOn(slot.color)
                    val cell = card(color = slot.color)
                    cell.addView(text(slot.name, 14, ink, bold = true).apply { maxLines = 2 })
                    cell.addView(text(slot.percent, 16, ink, bold = true))
                    cell.addView(text(slot.kind, 11, ink))
                    line.addView(cell, weight())
                }
                while (line.childCount < 3) line.addView(View(context), weight())
                content.addView(line)
            }
        }
    }

    private fun renderSchedule() {
        val activity = context as? KioskActivity
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            note("日历来自这台手机。允许读取后，这里显示今天和接下来的日程。")
            activity?.askCalendar()
            return
        }
        val events = runCatching { loadEvents() }.getOrElse {
            note(it.message ?: "读不了日历")
            return
        }
        content.addView(text("日历来自这台手机，只能查看。", 13, Theme.border()).apply {
            setPadding(0, 0, 0, dp(8))
        })
        if (events.isEmpty()) {
            note("无")
            return
        }
        content.addView(text("接下来", 14, Theme.accent(), bold = true))
        events.take(12).chunked(2).forEach { row ->
            val line = rowLine()
            row.forEach { (whenText, title) ->
                val cell = card()
                cell.addView(text(whenText, 11, Theme.border()).apply { maxLines = 1 })
                cell.addView(text(title, 14, Color.WHITE, bold = true).apply { maxLines = 2 })
                line.addView(cell, weight())
            }
            if (row.size == 1) line.addView(View(context), weight())
            content.addView(line)
        }
    }

    private fun loadEvents(): List<Pair<String, String>> {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val start = cal.timeInMillis
        cal.add(Calendar.DAY_OF_YEAR, 8)
        val end = cal.timeInMillis
        val out = mutableListOf<Pair<String, String>>()
        val projection = arrayOf(
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.ALL_DAY
        )
        val selection = "${CalendarContract.Events.DTSTART} >= ? AND ${CalendarContract.Events.DTSTART} < ?"
        context.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selection,
            arrayOf(start.toString(), end.toString()),
            "${CalendarContract.Events.DTSTART} ASC"
        )?.use { c ->
            val titleCol = c.getColumnIndex(CalendarContract.Events.TITLE)
            val startCol = c.getColumnIndex(CalendarContract.Events.DTSTART)
            val allCol = c.getColumnIndex(CalendarContract.Events.ALL_DAY)
            val fmt = SimpleDateFormat("M月d日 EEEE", Locale.CHINA)
            while (c.moveToNext() && out.size < 12) {
                val title = if (titleCol >= 0) c.getString(titleCol).orEmpty() else ""
                if (title.isBlank()) continue
                val whenMs = if (startCol >= 0) c.getLong(startCol) else start
                val allDay = allCol >= 0 && c.getInt(allCol) == 1
                val whenText = fmt.format(Date(whenMs)) + if (allDay) " 全天" else " " + SimpleDateFormat("HH:mm", Locale.CHINA).format(Date(whenMs))
                out += whenText to title
            }
        }
        return out
    }

    private fun card(index: Int = serial++, color: Int = Theme.cardTint(index + bias())): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(color)
                cornerRadius = dp(10).toFloat()
            }
            setPadding(dp(8), dp(6), dp(8), dp(6))
        }
    }

    private fun bias(): Int {
        var n = 0
        for (ch in pageId) n = n * 33 + ch.code
        return Math.floorMod(n, 6)
    }

    private fun rowLine(): LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        layoutParams = match()
    }

    private fun weight(): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
            marginEnd = dp(4)
            bottomMargin = dp(4)
        }

    private fun match(): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) }

    private fun text(value: String, sp: Int, color: Int, bold: Boolean = false): TextView =
        TextView(context).apply {
            text = value
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sp.toFloat())
            if (bold) typeface = Typeface.DEFAULT_BOLD
        }

    private fun note(value: String) {
        content.addView(text(value, 18, Theme.border()).apply {
            setPadding(0, dp(24), 0, 0)
        })
    }

    private fun weekday(iso: String): String {
        val date = runCatching { SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(iso) }.getOrNull() ?: return iso
        return SimpleDateFormat("EEE", Locale.CHINA).format(date)
    }

    private fun formatPrice(price: Double, crypto: Boolean): String {
        val frac = if (!crypto || price >= 100) 2 else if (price >= 1) 2 else 4
        val pattern = if (abs(price - round(price)) < 0.001 && price >= 100) "#,##0" else "#,##0.${"0".repeat(max(frac, 2))}"
        return java.text.DecimalFormat(pattern, java.text.DecimalFormatSymbols(Locale.US)).format(price)
    }

    private fun inkOn(color: Int): Int {
        val r = Color.red(color) / 255.0
        val g = Color.green(color) / 255.0
        val b = Color.blue(color) / 255.0
        val l = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return if (l > 0.62) Color.BLACK else Color.WHITE
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), context.resources.displayMetrics).toInt()
}
