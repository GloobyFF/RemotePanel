package com.glooby.remotepanel.pages

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.provider.CalendarContract
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import androidx.core.content.ContextCompat
import com.glooby.remotepanel.data.DaySlot
import com.glooby.remotepanel.data.FeedRepository
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.QuoteItem
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.data.WeatherState
import com.glooby.remotepanel.data.Wmo
import com.glooby.remotepanel.ui.BarView
import com.glooby.remotepanel.ui.Fmt
import com.glooby.remotepanel.ui.KioskActivity
import com.glooby.remotepanel.ui.Ui
import com.glooby.remotepanel.ui.Ui.W
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/** 问候 (dashboard), 天气, 日程, 打印机. */
object HomePages {
    private val cn = Locale.CHINA

    // ---------- 问候海报：时钟 + 天气 + 一句话 + 头条 + 行情 ----------

    fun hello(ctx: Context, s: PanelState): View = Ui.column(ctx).apply {
        val now = Date()
        val top = Ui.row(ctx)
        val clock = Ui.column(ctx).apply {
            addView(Ui.number(ctx, SimpleDateFormat("HH:mm", cn).format(now), 200, Theme.text()), Ui.wide())
            addView(Ui.text(ctx, SimpleDateFormat("M月d日 EEEE", cn).format(now), Ui.H2, Theme.textDim(), W.MEDIUM), Ui.wide())
        }
        top.addView(clock, Ui.flexH(1.25f, end = Ui.GAP))
        top.addView(weatherChip(ctx, s.weather), Ui.flexH(1f))
        addView(top, Ui.wide(300, bottom = Ui.GAP))

        val greet = Ui.column(ctx, Theme.surface()).apply {
            setPadding(Ui.px(36), Ui.px(28), Ui.px(36), Ui.px(28))
            gravity = Gravity.CENTER_VERTICAL
            addView(Ui.text(ctx, s.helloPeriod.ifBlank { FeedRepository.helloSlot().first }, Ui.H1, Theme.accent(), W.BOLD), Ui.wide())
            addView(Ui.text(ctx, s.hello.ifBlank { localTip(s.weather) }, Ui.H2, Theme.text(), W.MEDIUM, lines = 3), Ui.wide(top = 10))
        }
        addView(greet, Ui.wide(310, bottom = 28))

        val quotes = marketPicks(s)
        if (s.dailyNews.isNotEmpty()) {
            addView(Blocks.section(ctx, "今日头条", "共 ${s.dailyNews.size} 条"), Ui.wide(64, bottom = 14))
            val list = Ui.column(ctx)
            s.dailyNews.take(if (quotes.isEmpty()) 7 else 5).forEach { n ->
                val row = Ui.row(ctx).apply {
                    addView(View(ctx).apply { background = Ui.rounded(Theme.accent(), 999) }, Ui.fixed(14, 14, end = 22))
                    addView(Ui.text(ctx, n.title, Ui.BODY, Theme.text(), W.MEDIUM), LinearLayout.LayoutParams(0, -2, 1f))
                    if (n.publishedAt > 0) addView(Ui.text(ctx, Fmt.clock(n.publishedAt), Ui.META, Theme.textFaint()), Ui.wrap(start = 16))
                }
                list.addView(row, Ui.flexV())
            }
            addView(list, Ui.flexV(bottom = if (quotes.isEmpty()) 0 else 24))
        } else {
            addView(Ui.spacer(ctx), Ui.flexV())
        }
        if (quotes.isNotEmpty()) {
            addView(Blocks.section(ctx, "行情", if (com.glooby.remotepanel.data.Feeds.marketOpen()) "交易中" else "已收盘"), Ui.wide(64, bottom = 14))
            addView(Pages.grid(ctx, 1, 3, Ui.GAP) { i -> quotes.getOrNull(i)?.let { quoteTile(ctx, it) } }, Ui.wide(230))
        }
    }

    private fun marketPicks(s: PanelState): List<QuoteItem> {
        val idx = s.stocks?.indices.orEmpty()
        return (idx.ifEmpty { s.stocks?.stocks.orEmpty() } + s.crypto).take(3)
    }

    private fun quoteTile(ctx: Context, q: QuoteItem): View = Ui.column(ctx, Theme.surface()).apply {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(Ui.px(26), Ui.px(18), Ui.px(26), Ui.px(18))
        val crypto = q.market == "crypto"
        addView(Ui.text(ctx, q.name, Ui.BODY, Theme.textDim(), W.MEDIUM), Ui.wide())
        addView(Ui.number(ctx, Fmt.price(q.price, crypto), 68, Theme.text()), Ui.wide())
        addView(Ui.number(ctx, Fmt.percent(q.percent), Ui.BODY, Theme.move(q.percent)), Ui.wide())
    }

    private fun weatherChip(ctx: Context, w: WeatherState?): View = Ui.column(ctx, Theme.surface()).apply {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(Ui.px(30), Ui.px(20), Ui.px(30), Ui.px(20))
        if (w == null) {
            addView(Ui.text(ctx, "天气读取中", Ui.H2, Theme.textDim(), W.MEDIUM), Ui.wide())
            return@apply
        }
        val today = w.daily.firstOrNull()
        addView(Ui.row(ctx).apply {
            addView(Ui.text(ctx, Wmo.icon(w.code), 84), Ui.wrap(end = 16))
            addView(Ui.number(ctx, Fmt.temp(w.temp), 104, Theme.text()), Ui.wrap())
        }, Ui.wide())
        addView(Ui.text(ctx, "${w.city} · ${Wmo.text(w.code)}", Ui.BODY, Theme.text(), W.MEDIUM), Ui.wide())
        if (today != null) {
            addView(Ui.text(ctx, "${Fmt.temp(today.low)} ~ ${Fmt.temp(today.high)}  降水 ${today.rainChance}%", Ui.META, Theme.textDim()), Ui.wide())
        }
    }

    /** A useful line when no AI key is set, built from today's forecast. */
    private fun localTip(w: WeatherState?): String {
        val d = w?.daily?.firstOrNull() ?: return "今天也要好好吃饭，按时休息。"
        return when {
            d.rainChance >= 60 -> "今天降水概率 ${d.rainChance}%，出门记得带伞。"
            d.high - d.low >= 10 -> "今天温差 ${(d.high - d.low).roundToInt()} 度，早晚记得加件外套。"
            d.high >= 33 -> "今天最高 ${Fmt.temp(d.high)}，注意防暑，多喝水。"
            d.low <= 3 -> "今天最低 ${Fmt.temp(d.low)}，出门穿暖和些。"
            d.uv >= 7 -> "今天紫外线很强，出门记得防晒。"
            w.windKmh >= 30 -> "今天风比较大，出门注意安全。"
            else -> "今天${Wmo.text(d.code)}，${Fmt.temp(d.low)} 到 ${Fmt.temp(d.high)}，适合出门走走。"
        }
    }
    // ---------- 天气：实况 + 指标 + 逐 2 小时 + 未来几天 + VPS ----------

    fun weather(ctx: Context, s: PanelState): View {
        val w = s.weather ?: return Blocks.pending(ctx, "weather", "天气")
        val today = w.daily.firstOrNull()
        return Ui.column(ctx).apply {
            val hero = Ui.row(ctx, Theme.surface()).apply {
                setPadding(Ui.px(40), Ui.px(24), Ui.px(40), Ui.px(24))
                addView(Ui.column(ctx).apply {
                    addView(Ui.text(ctx, "📍 ${w.city}", Ui.BODY, Theme.textDim(), W.MEDIUM), Ui.wide())
                    addView(Ui.number(ctx, Fmt.temp(w.temp), Ui.HERO, Theme.text()), Ui.wide())
                    addView(Ui.text(ctx, "${Wmo.text(w.code)} · 体感 ${Fmt.temp(w.feelsLike)}", Ui.H2, Theme.text(), W.MEDIUM), Ui.wide())
                }, Ui.flexH(1f))
                addView(Ui.column(ctx).apply {
                    gravity = Gravity.CENTER
                    addView(Ui.text(ctx, Wmo.icon(w.code), 150, gravity = Gravity.CENTER), Ui.wide())
                    if (today != null) addView(Ui.text(ctx, "${Fmt.temp(today.low)} / ${Fmt.temp(today.high)}", Ui.H2, Theme.textDim(), W.BOLD, gravity = Gravity.CENTER), Ui.wide())
                }, Ui.fixed(330, -1))
            }
            addView(hero, Ui.wide(390, bottom = Ui.GAP))

            val stats = listOf(
                "湿度" to "${w.humidity}%",
                "风" to "${Wmo.windDir(w.windDir)}风 ${beaufort(w.windKmh)}级",
                "紫外线" to (today?.let { uvText(it.uv) } ?: "--"),
                "日出" to (today?.sunrise?.take(5)?.ifBlank { null } ?: "--"),
                "日落" to (today?.sunset?.take(5)?.ifBlank { null } ?: "--"),
                "气压" to if (w.pressure.isNaN()) "--" else "${w.pressure.roundToInt()} hPa",
            )
            addView(Pages.grid(ctx, 2, 3, 16) { i ->
                stats.getOrNull(i)?.let { (k, v) ->
                    Ui.column(ctx, Theme.surface()).apply {
                        gravity = Gravity.CENTER_VERTICAL
                        setPadding(Ui.px(26), Ui.px(10), Ui.px(20), Ui.px(10))
                        addView(Ui.text(ctx, k, Ui.META, Theme.textFaint()), Ui.wide())
                        addView(Ui.text(ctx, v, Ui.H2, Theme.text(), W.BOLD), Ui.wide())
                    }
                }
            }, Ui.wide(300, bottom = Ui.GAP))

            val hours = w.hourly.filterIndexed { i, _ -> i % 2 == 0 }.take(8)
            if (hours.isNotEmpty()) {
                val strip = Ui.row(ctx, Theme.surface()).apply {
                    setPadding(Ui.px(8), Ui.px(14), Ui.px(8), Ui.px(14))
                    hours.forEachIndexed { i, hSlot ->
                        addView(Ui.column(ctx).apply {
                            gravity = Gravity.CENTER
                            addView(Ui.text(ctx, if (i == 0) "现在" else hSlot.hour, Ui.META, Theme.textDim(), gravity = Gravity.CENTER), Ui.wide())
                            addView(Ui.text(ctx, Wmo.icon(hSlot.code), 56, gravity = Gravity.CENTER), Ui.wide(top = 4))
                            addView(Ui.number(ctx, Fmt.temp(hSlot.temp), Ui.H2, Theme.text()).apply { gravity = Gravity.CENTER }, Ui.wide())
                            addView(Ui.text(ctx, if (hSlot.rainChance >= 20) "${hSlot.rainChance}%" else " ", Ui.META, Theme.accent(), gravity = Gravity.CENTER), Ui.wide())
                        }, Ui.flexH(1f))
                    }
                }
                addView(strip, Ui.wide(290, bottom = Ui.GAP))
            }

            val vps = s.vps
            val days = w.daily.take(if (vps != null) 5 else 7)
            val lo = days.minOfOrNull { it.low } ?: 0.0
            val hi = days.maxOfOrNull { it.high } ?: 1.0
            val list = Ui.column(ctx, Theme.surface()).apply {
                setPadding(Ui.px(30), Ui.px(8), Ui.px(30), Ui.px(8))
                days.forEachIndexed { i, d -> addView(dayRow(ctx, i, d, lo, hi), Ui.flexV()) }
            }
            addView(list, Ui.flexV(bottom = if (vps != null) Ui.GAP else 0))
            if (vps != null) addView(vpsCard(ctx, vps), Ui.wide(200))
        }
    }

    private fun dayRow(ctx: Context, i: Int, d: DaySlot, lo: Double, hi: Double): View = Ui.row(ctx).apply {
        val label = when (i) {
            0 -> "今天"
            1 -> "明天"
            else -> runCatching { SimpleDateFormat("EEE", cn).format(SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(d.date)!!) }.getOrDefault(d.date)
        }
        addView(Ui.text(ctx, label, Ui.BODY, Theme.text(), W.BOLD), Ui.fixed(130, -2))
        addView(Ui.text(ctx, Wmo.icon(d.code), 52), Ui.fixed(80, -2))
        addView(Ui.text(ctx, Wmo.text(d.code) + if (d.rainChance >= 30) " ${d.rainChance}%" else "", Ui.META, Theme.textDim()), Ui.fixed(220, -2))
        addView(Ui.number(ctx, Fmt.temp(d.low), Ui.BODY, Color.rgb(0x8E, 0xC5, 0xFF)).apply { gravity = Gravity.END }, Ui.fixed(100, -2, end = 16))
        val span = (hi - lo).takeIf { it > 0.1 } ?: 1.0
        addView(BarView(ctx, Theme.track(), Theme.accent()).apply {
            from = ((d.low - lo) / span).toFloat(); to = ((d.high - lo) / span).toFloat()
        }, LinearLayout.LayoutParams(0, Ui.px(16), 1f).apply { marginEnd = Ui.px(16) })
        addView(Ui.number(ctx, Fmt.temp(d.high), Ui.BODY, Color.rgb(0xFF, 0xB0, 0x6A)), Ui.fixed(96, -2))
    }

    private fun vpsCard(ctx: Context, v: com.glooby.remotepanel.data.VpsState): View = Ui.column(ctx, Theme.surface()).apply {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(Ui.px(36), Ui.px(18), Ui.px(36), Ui.px(18))
        addView(Ui.row(ctx).apply {
            addView(Ui.text(ctx, "VPS 流量", Ui.H2, Theme.text(), W.BOLD), Ui.wrap(end = 24))
            addView(Ui.text(ctx, "已用 ${v.used} · 剩余 ${v.remain}", Ui.BODY, Theme.textDim()), LinearLayout.LayoutParams(0, -2, 1f))
        }, Ui.wide())
        if (!v.percent.isNaN()) {
            addView(BarView(ctx, Theme.track(), if (v.percent >= 85) Theme.bad() else Theme.ok()).apply { to = (v.percent / 100.0).toFloat() }, Ui.wide(20, top = 14, bottom = 10))
        }
        addView(Ui.text(ctx, listOf(v.cycle, v.status).filter { it.isNotBlank() }.joinToString("  ·  "), Ui.META, Theme.textFaint()), Ui.wide())
    }

    private fun beaufort(kmh: Double): Int = intArrayOf(1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 118).indexOfFirst { kmh < it }.let { if (it < 0) 12 else it }

    private fun uvText(uv: Double): String = when {
        uv < 3 -> "低"
        uv < 6 -> "中等"
        uv < 8 -> "高"
        uv < 11 -> "很高"
        else -> "极高"
    } + " ${uv.roundToInt()}"
    // ---------- 日程：本机日历未来 8 天（含重复事件） ----------

    private class Event(val start: Long, val allDay: Boolean, val title: String, val place: String)

    fun schedule(ctx: Context): View {
        val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            (ctx as? KioskActivity)?.askCalendar()
            return Blocks.message(ctx, "需要读取日历", "日程来自这台设备的系统日历。允许读取后，这里显示今天和接下来一周的安排。", "📅")
        }
        val events = runCatching { loadEvents(ctx) }.getOrElse { return Blocks.message(ctx, "读不了日历", it.message.orEmpty(), "⚠️") }
        if (events.isEmpty()) return Blocks.message(ctx, "接下来 8 天没有日程", "在系统日历里添加的事项会显示在这里。", "🌿")
        val dayKey = SimpleDateFormat("yyyyMMdd", Locale.US)
        val todayKey = dayKey.format(Date())
        val tomorrowKey = dayKey.format(Date(System.currentTimeMillis() + 86_400_000L))
        return Ui.column(ctx).apply {
            val shown = events.take(10)
            var lastDay = ""
            shown.forEach { e ->
                val k = dayKey.format(Date(e.start))
                val row = Ui.row(ctx, Theme.surface()).apply {
                    setPadding(Ui.px(30), Ui.px(12), Ui.px(30), Ui.px(12))
                    val day = when (k) {
                        todayKey -> "今天"
                        tomorrowKey -> "明天"
                        else -> SimpleDateFormat("M/d EEE", cn).format(Date(e.start))
                    }
                    addView(Ui.column(ctx).apply {
                        addView(Ui.text(ctx, if (k != lastDay) day else "", Ui.META, if (k == todayKey) Theme.accent() else Theme.textDim(), W.BOLD), Ui.wide())
                        addView(Ui.number(ctx, if (e.allDay) "全天" else Fmt.clock(e.start), Ui.H2, Theme.text()), Ui.wide())
                    }, Ui.fixed(220, -2))
                    addView(Ui.column(ctx).apply {
                        addView(Ui.text(ctx, e.title, Ui.H2, Theme.text(), W.BOLD, lines = 2), Ui.wide())
                        if (e.place.isNotBlank()) addView(Ui.text(ctx, "📍 ${e.place}", Ui.META, Theme.textDim()), Ui.wide())
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                }
                lastDay = k
                addView(row, Ui.flexV(bottom = 14))
            }
            repeat(10 - shown.size) { addView(Ui.spacer(ctx), Ui.flexV(bottom = 14)) }
            if (events.size > shown.size) addView(Ui.text(ctx, "还有 ${events.size - shown.size} 项没有显示", Ui.META, Theme.textFaint()), Ui.wide())
        }
    }

    private fun loadEvents(ctx: Context): List<Event> {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val now = System.currentTimeMillis()
        val begin = cal.timeInMillis
        val end = begin + 8 * 86_400_000L
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, begin); ContentUris.appendId(it, end)
        }.build()
        val cols = arrayOf(CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN, CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY, CalendarContract.Instances.EVENT_LOCATION)
        val out = mutableListOf<Event>()
        ctx.contentResolver.query(uri, cols, null, null, "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
            while (c.moveToNext() && out.size < 40) {
                val title = c.getString(0).orEmpty()
                if (title.isBlank()) continue
                val allDay = c.getInt(3) == 1
                val endMs = c.getLong(2)
                if (!allDay && endMs in 1 until now) continue
                // All-day instances are stored at UTC midnight; shift to local midnight.
                val start = if (allDay) c.getLong(1) - java.util.TimeZone.getDefault().getOffset(c.getLong(1)) else c.getLong(1)
                out += Event(start, allDay, title, c.getString(4).orEmpty())
            }
        }
        return out.sortedBy { it.start }
    }
    // ---------- 打印机：进度 + 温度 + 料仓 ----------

    fun printer(ctx: Context, s: PanelState): View {
        val p = s.printer ?: return Blocks.pending(ctx, "print", "打印机")
        return Ui.column(ctx).apply {
            val hero = Ui.column(ctx, Theme.surface()).apply {
                setPadding(Ui.px(40), Ui.px(28), Ui.px(40), Ui.px(28))
                addView(Ui.row(ctx).apply {
                    addView(Ui.pill(ctx, if (p.online) "在线" else "离线", if (p.online) Theme.ok() else Theme.bad(), Color.BLACK), Ui.wrap(end = 16))
                    addView(Ui.pill(ctx, p.status, Theme.surfaceHigh()), Ui.wrap(end = 20))
                    addView(Ui.text(ctx, p.title, Ui.BODY, Theme.textDim(), W.MEDIUM), LinearLayout.LayoutParams(0, -2, 1f))
                }, Ui.wide(bottom = 16))
                addView(Ui.row(ctx).apply {
                    addView(Ui.number(ctx, "${p.progress.roundToInt()}%", 150, Theme.accent()), Ui.wrap(end = 36))
                    addView(Ui.column(ctx).apply {
                        val remain = when {
                            p.remainMinutes < 0 -> "--"
                            p.remainMinutes >= 60 -> "${p.remainMinutes / 60} 小时 ${p.remainMinutes % 60} 分"
                            else -> "${p.remainMinutes} 分钟"
                        }
                        addView(Ui.text(ctx, "剩余 $remain", Ui.H2, Theme.text(), W.BOLD), Ui.wide())
                        if (p.layer.isNotBlank()) addView(Ui.text(ctx, "层 ${p.layer}", Ui.BODY, Theme.textDim()), Ui.wide(top = 6))
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                }, Ui.wide())
                addView(BarView(ctx, Theme.track(), Theme.accent()).apply { to = (p.progress / 100.0).toFloat() }, Ui.wide(24, top = 18, bottom = 16))
                addView(Ui.text(ctx, p.fileName.ifBlank { "没有正在打印的文件" }, Ui.BODY, Theme.textDim(), lines = 2), Ui.wide())
            }
            addView(hero, Ui.wide(520, bottom = Ui.GAP))
            if (p.temps.isNotEmpty()) {
                addView(Pages.grid(ctx, 1, 3, Ui.GAP) { i ->
                    p.temps.getOrNull(i)?.let { t ->
                        Ui.column(ctx, Theme.surface()).apply {
                            gravity = Gravity.CENTER
                            addView(Ui.text(ctx, t.label, Ui.BODY, Theme.textDim(), gravity = Gravity.CENTER), Ui.wide())
                            addView(Ui.number(ctx, t.value, Ui.DISPLAY, Theme.text()).apply { gravity = Gravity.CENTER }, Ui.wide())
                        }
                    }
                }, Ui.wide(220, bottom = 28))
            }
            if (p.slots.isEmpty()) {
                addView(Ui.spacer(ctx), Ui.flexV())
                return@apply
            }
            addView(Blocks.section(ctx, "耗材料仓", "${p.slots.size} 槽"), Ui.wide(64, bottom = 16))
            val rows = ((p.slots.size + 2) / 3).coerceIn(1, 4)
            addView(Pages.grid(ctx, rows, 3, Ui.GAP) { i ->
                p.slots.getOrNull(i)?.let { slot ->
                    Ui.column(ctx, Theme.surface()).apply {
                        gravity = Gravity.CENTER_VERTICAL
                        setPadding(Ui.px(22), Ui.px(12), Ui.px(22), Ui.px(12))
                        addView(View(ctx).apply { background = Ui.rounded(slot.color, 8, 2, 0x40FFFFFF) }, Ui.wide(24, bottom = 10))
                        addView(Ui.text(ctx, slot.name, Ui.BODY, Theme.text(), W.BOLD), Ui.wide())
                        addView(Ui.row(ctx).apply {
                            addView(Ui.text(ctx, slot.kind, Ui.META, Theme.textFaint()), LinearLayout.LayoutParams(0, -2, 1f))
                            addView(Ui.number(ctx, if (slot.percent >= 0) "${slot.percent}%" else "--", Ui.BODY, Theme.text()), Ui.wrap(start = 8))
                        }, Ui.wide())
                    }
                }
            }, Ui.flexV())
        }
    }
}
