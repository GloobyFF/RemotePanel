package com.glooby.zhangjie.ui

import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.glooby.zhangjie.AlertHit
import com.glooby.zhangjie.Holding
import com.glooby.zhangjie.Quote
import com.glooby.zhangjie.Quotes
import com.glooby.zhangjie.Store
import java.util.Date
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Full-screen stock carousel laid out for 1080×1920 portrait.
 * Summary first, then one stock per page. Tap the side edges to turn.
 */
class KioskActivity : AppCompatActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val pool = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private lateinit var board: FrameLayout
    private lateinit var titleLabel: TextView
    private lateinit var statusLabel: TextView
    private lateinit var indexLabel: TextView
    private lateinit var clockLabel: TextView
    private lateinit var progressFill: View
    private lateinit var progressTrack: FrameLayout
    private lateinit var banner: LinearLayout
    private lateinit var bannerText: TextView

    private var index = 0
    private var dwellLeft = 20
    private var dwellTotal = 20
    private var lastFetch = 0L
    private var lastError = ""
    private var turning = false
    private var paused = false
    private val alerts = ArrayList<AlertHit>()

    private val onStore: () -> Unit = { if (!isDestroyed) render() }

    private val tick = object : Runnable {
        override fun run() {
            clockLabel.text = Ui.clock(Date())
            val now = System.currentTimeMillis()
            if (!paused && Store.shouldFetch() && now - lastFetch >= 60_000L) refresh()
            if (!paused && !turning) {
                dwellLeft -= 1
                if (dwellLeft <= 0) turn(1) else updateProgress()
            }
            updateIndex()
            main.postDelayed(this, 1000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Ui.init(this)
        setContentView(build())
        applyImmersive()
        Store.listen(onStore)
        board.post { render() }
        refresh()
        main.post(tick)
    }

    override fun onResume() {
        super.onResume()
        paused = false
        Ui.init(this)
        applyImmersive()
        if (index >= pageCount()) index = 0
        refresh()
        restartDwell()
        render()
    }

    override fun onPause() {
        paused = true
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyImmersive()
    }

    override fun onDestroy() {
        Store.unlisten(onStore)
        main.removeCallbacksAndMessages(null)
        pool.shutdownNow()
        super.onDestroy()
    }

    private fun build(): View {
        val root = FrameLayout(this).apply { setBackgroundColor(Ui.BG) }
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(Ui.px(12), 0, Ui.px(12), 0)
            setOnLongClickListener { openSettings(); true }
        }
        header.addView(chromeButton("◀") { turn(-1) }, LinearLayout.LayoutParams(Ui.px(88), Ui.px(88)))
        titleLabel = Ui.label(this, "张洁股票", 40, Ui.TEXT, bold = true).apply { gravity = Gravity.START or Gravity.CENTER_VERTICAL }
        header.addView(titleLabel, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f))
        statusLabel = Ui.label(this, "", 28, Ui.DIM)
        indexLabel = Ui.label(this, "", 28, Ui.DIM)
        clockLabel = Ui.number(this, "", 36, Ui.TEXT)
        header.addView(statusLabel, LinearLayout.LayoutParams(Ui.px(280), LinearLayout.LayoutParams.MATCH_PARENT))
        header.addView(indexLabel, LinearLayout.LayoutParams(Ui.px(120), LinearLayout.LayoutParams.MATCH_PARENT))
        header.addView(clockLabel, LinearLayout.LayoutParams(Ui.px(140), LinearLayout.LayoutParams.MATCH_PARENT))
        header.addView(chromeButton("⚙") { openSettings() }, LinearLayout.LayoutParams(Ui.px(88), Ui.px(88)))
        header.addView(chromeButton("▶") { turn(1) }, LinearLayout.LayoutParams(Ui.px(88), Ui.px(88)))

        progressTrack = FrameLayout(this).apply { setBackgroundColor(0x38FFFFFF) }
        progressFill = View(this).apply { setBackgroundColor(Ui.UP) }
        progressTrack.addView(progressFill, FrameLayout.LayoutParams(0, FrameLayout.LayoutParams.MATCH_PARENT))

        board = FrameLayout(this)
        banner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(Ui.px(36), Ui.px(28), Ui.px(36), Ui.px(28))
            background = GradientDrawable().apply {
                setColor(Ui.UP)
                cornerRadius = Ui.px(24).toFloat()
            }
            visibility = View.GONE
            setOnClickListener { dismissAlerts() }
        }
        bannerText = Ui.label(this, "", 36, Ui.TEXT, bold = true).apply { gravity = Gravity.CENTER }
        banner.addView(bannerText)
        column.addView(header, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, Ui.px(120)))
        column.addView(progressTrack, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, Ui.px(8)))
        column.addView(banner, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = Ui.px(16)
            leftMargin = Ui.px(36)
            rightMargin = Ui.px(36)
        })
        column.addView(board, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(column, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        val edgeTop = Ui.px(120)
        root.addView(edge(-1), FrameLayout.LayoutParams(Ui.px(180), FrameLayout.LayoutParams.MATCH_PARENT, Gravity.START).apply { topMargin = edgeTop })
        root.addView(edge(1), FrameLayout.LayoutParams(Ui.px(180), FrameLayout.LayoutParams.MATCH_PARENT, Gravity.END).apply { topMargin = edgeTop })
        return root
    }

    private fun chromeButton(glyph: String, click: () -> Unit): TextView =
        Ui.label(this, glyph, 44, Ui.TEXT, bold = true).apply { setOnClickListener { click() } }

    private fun edge(delta: Int): View = View(this).apply {
        setOnClickListener { turn(delta) }
        setOnLongClickListener { openSettings(); true }
    }

    private fun openSettings() {
        startActivity(Intent(this, SettingsActivity::class.java))
    }

    /** Six cards fill a 1080×1920 summary. Further stocks get another summary page. */
    private fun summaryCount(): Int {
        val n = Store.holdings().size
        return if (n == 0) 1 else (n + 5) / 6
    }

    private fun pageCount(): Int = summaryCount() + Store.holdings().size

    private fun summaryPage(): Boolean = index < summaryCount()

    private fun restartDwell() {
        dwellTotal = if (summaryPage()) Store.dwellSummary() else Store.dwellStock()
        dwellLeft = dwellTotal
        updateProgress()
    }

    private fun turn(delta: Int) {
        val n = pageCount()
        if (n <= 1 || turning) return
        turning = true
        board.animate().alpha(0f).setDuration(140).withEndAction {
            index = Math.floorMod(index + delta, n)
            restartDwell()
            render()
            board.alpha = 0f
            board.animate().alpha(1f).setDuration(180).withEndAction { turning = false }.start()
        }.start()
    }

    private fun updateIndex() {
        val n = pageCount()
        indexLabel.text = "${index + 1}/$n"
        val src = Store.lastSource()
        statusLabel.text = if (src.isEmpty()) Store.sessionShort() else "${Store.sessionShort()} · $src"
    }

    private fun updateProgress() {
        val p = if (dwellTotal <= 0) 0f else (dwellTotal - dwellLeft).toFloat() / dwellTotal
        val w = (progressTrack.width * p.coerceIn(0f, 1f)).toInt()
        progressFill.layoutParams = FrameLayout.LayoutParams(w, FrameLayout.LayoutParams.MATCH_PARENT)
    }

    private fun render() {
        if (board.width < 10) {
            board.post { render() }
            return
        }
        updateIndex()
        board.removeAllViews()
        val holds = Store.holdings()
        if (index >= pageCount()) index = 0
        val page: View = if (summaryPage() || holds.isEmpty()) {
            summary(holds.drop(index * 6).take(6), index, summaryCount())
        } else {
            detail(holds[index - summaryCount()])
        }
        board.addView(page, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    }

    private fun summary(holds: List<Holding>, page: Int, pages: Int): View {
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(Ui.px(20), Ui.px(12), Ui.px(20), Ui.px(12))
        }
        val caption = if (pages > 1) "${Store.sessionTitle()}    汇总 ${page + 1}/$pages" else Store.sessionTitle()
        col.addView(Ui.label(this, caption, 28, Ui.DIM), Ui.wide(48))
        if (holds.isEmpty()) {
            val msg = if (lastError.isNotEmpty()) lastError else "点右上角设置，或用浏览器打开设置页添加股票"
            col.addView(Ui.label(this, msg, 36, Ui.TEXT), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
            return col
        }
        val cols = if (holds.size == 1) 1 else 2
        val rows = holds.chunked(cols)
        val fill = rows.size >= 3
        rows.forEach { pair ->
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            pair.forEachIndexed { i, h ->
                row.addView(card(h), Ui.flex(1f, if (i == pair.lastIndex) 0 else 16))
            }
            if (pair.size < cols) row.addView(View(this), Ui.flex(1f))
            val lp = if (fill) {
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
            } else {
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, Ui.px(520))
            }
            lp.bottomMargin = Ui.px(16)
            col.addView(row, lp)
        }
        return col
    }

    private fun card(h: Holding): View {
        val q = Store.quote(h.code)
        val has = q != null && q.price > 0
        val pct = q?.percent ?: 0.0
        val color = if (has) Ui.moveColor(pct) else Ui.DIM
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(Ui.CARD)
                cornerRadius = Ui.px(24).toFloat()
            }
            setPadding(Ui.px(16), Ui.px(12), Ui.px(16), Ui.px(12))
        }
        val bell = if (h.above > 0 || h.below > 0) "  🔔" else ""
        box.addView(Ui.label(this, (h.name.ifBlank { h.code }) + bell, 52, Ui.TEXT, bold = true), Ui.wide(84))
        val price = Ui.number(this, if (has) Ui.grouped(q!!.price) else "—", 144, color).apply { maxLines = 1 }
        box.addView(price, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        box.addView(Ui.label(this, if (has) Ui.pct(pct) else h.code, 34, color, bold = true), Ui.wide(56))
        box.addView(Ui.label(this, pnlLine(h, q), 30, pnlColor(h, q)), Ui.wide(52))
        return box
    }

    private fun detail(h: Holding): View {
        val q = Store.quote(h.code)
        val has = q != null && q.price > 0
        val bought = h.buy > 0
        val pct = q?.percent ?: 0.0
        val color = if (has) Ui.moveColor(pct) else Ui.DIM
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(Ui.px(36), Ui.px(24), Ui.px(36), Ui.px(24))
        }
        col.addView(Ui.label(this, Store.sessionTitle(), 60, Ui.DIM), Ui.wide(84))
        col.addView(Ui.number(this, h.name.ifBlank { h.code }, 120, Ui.TEXT), Ui.wide(156))
        col.addView(Ui.label(this, h.code, 72, Ui.DIM), Ui.wide(96))
        val priceText = if (has) Ui.grouped(q!!.price) else "—"
        col.addView(Ui.number(this, priceText, 180, color), Ui.wide(220))
        val move = if (has) "${Ui.signed(q!!.change)}    ${Ui.pct(pct)}" else lastError.ifEmpty { "正在读取" }
        col.addView(Ui.label(this, move, 104, color, bold = true), Ui.wide(140))
        col.addView(newsBlock(h.code), LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        if (has && bought) {
            val one = q!!.price - h.buy
            val yield = one / h.buy * 100.0
            col.addView(Ui.label(this, "买入价  ${Ui.grouped(h.buy)}", 80, Ui.TEXT), Ui.wide(108))
            col.addView(Ui.label(this, "每股 ${Ui.signed(one)}    ${Ui.pct(yield)}", 96, Ui.moveColor(one), bold = true), Ui.wide(128))
            if (h.shares > 0) {
                val total = one * h.shares
                col.addView(Ui.label(this, "${Ui.shares(h.shares)} 股    一共 ${Ui.signed(total)}", 104, Ui.moveColor(total), bold = true), Ui.wide(140))
            }
        } else if (has) {
            col.addView(Ui.label(this, "设置买入价后显示赚了多少", 64, Ui.DIM), Ui.wide(88))
        }
        val bits = ArrayList<String>()
        if (h.above > 0) bits += "涨到 ${Ui.grouped(h.above)} 提醒"
        if (h.below > 0) bits += "跌到 ${Ui.grouped(h.below)} 提醒"
        if (bits.isNotEmpty()) col.addView(Ui.label(this, "🔔  " + bits.joinToString("    "), 64, Ui.TEXT, bold = true), Ui.wide(88))
        val foot = buildString {
            if (q != null) append(Ui.stamp(q.at))
            val src = Store.lastSource()
            if (src.isNotEmpty()) {
                if (isNotEmpty()) append(" · ")
                append("来源 $src")
            }
        }
        if (foot.isNotEmpty()) col.addView(Ui.label(this, foot, 48, Ui.DIM), Ui.wide(68))
        return col
    }

    private fun newsBlock(code: String): View {
        val items = Store.briefs(code)
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(Ui.px(8), Ui.px(8), Ui.px(8), Ui.px(8))
        }
        if (items.isEmpty()) {
            box.addView(Ui.label(this, "正在读取公司消息", 48, Ui.DIM))
            return box
        }
        items.forEach { item ->
            val row = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_VERTICAL }
            val title = Ui.label(this, item.title, 52, Ui.TEXT, bold = true).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
            }
            row.addView(title)
            val meta = listOf(item.whenText, item.source).filter { it.isNotEmpty() }.joinToString("  ")
            if (meta.isNotEmpty()) {
                row.addView(Ui.label(this, meta, 36, Ui.DIM).apply { gravity = Gravity.START })
            }
            box.addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f).apply {
                topMargin = Ui.px(8)
            })
        }
        return box
    }

    private fun pnlLine(h: Holding, q: Quote?): String {
        if (q == null) return ""
        if (h.buy > 0 && h.shares > 0) return "一共 ${Ui.signed((q.price - h.buy) * h.shares)}"
        if (h.buy > 0) return "每股 ${Ui.signed(q.price - h.buy)}"
        return "未设买入价"
    }

    private fun pnlColor(h: Holding, q: Quote?): Int {
        if (q == null || h.buy <= 0) return Ui.DIM
        val one = q.price - h.buy
        return Ui.moveColor(if (h.shares > 0) one * h.shares else one)
    }

    private fun refresh() {
        if (!busy.compareAndSet(false, true)) return
        lastFetch = System.currentTimeMillis()
        pool.execute {
            val result = Quotes.refresh()
            main.post {
                busy.set(false)
                if (isDestroyed) return@post
                lastError = result.exceptionOrNull()?.message.orEmpty()
                if (result.isSuccess) {
                    val hits = Store.checkAlerts()
                    if (hits.isNotEmpty()) showAlerts(hits)
                }
                render()
            }
            runCatching { Quotes.refreshNews() }
        }
    }

    private fun showAlerts(hits: List<AlertHit>) {
        alerts += hits
        bannerText.text = alerts.joinToString("\n") { hit ->
            val dir = if (hit.above) "涨到" else "跌到"
            "${hit.name} $dir ${Ui.grouped(hit.limit)}    现价 ${Ui.grouped(hit.price)}"
        }
        banner.visibility = View.VISIBLE
        if (Store.alertSoundOn()) chime()
        banner.animate().cancel()
        banner.alpha = 1f
        banner.animate().alpha(0.55f).setDuration(700).withEndAction {
            banner.animate().alpha(1f).setDuration(700).start()
        }.start()
    }

    private fun dismissAlerts() {
        alerts.clear()
        banner.animate().cancel()
        banner.alpha = 1f
        banner.visibility = View.GONE
    }

    private fun chime() {
        val tone = ToneGenerator(AudioManager.STREAM_ALARM, 90)
        fun ring(left: Int) {
            if (left <= 0) {
                tone.release()
                return
            }
            tone.startTone(ToneGenerator.TONE_PROP_BEEP, 180)
            main.postDelayed({ ring(left - 1) }, 320)
        }
        ring(3)
    }

    @Suppress("DEPRECATION")
    private fun applyImmersive() {
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            )
    }
}
