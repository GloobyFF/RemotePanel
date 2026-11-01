package com.glooby.remotepanel.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.glooby.remotepanel.data.FeedCache
import com.glooby.remotepanel.data.FeedRepository
import com.glooby.remotepanel.data.PageCatalog
import com.glooby.remotepanel.data.PageDef
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Prefs
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.pages.BoardPage
import com.glooby.remotepanel.pages.DefaultPageFactory
import com.glooby.remotepanel.pages.Pages
import com.glooby.remotepanel.pages.PanelPage
import com.glooby.remotepanel.ui.Ui.W
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.random.Random

/**
 * Full-screen rotating kiosk laid out for 1080×1920 portrait: 132 px header, 8 px dwell bar, page below.
 * Tap the left / right 18 % of the screen to page, long-press the header (or the gear) for settings.
 */
class KioskActivity : AppCompatActivity() {
    private lateinit var root: FrameLayout
    private lateinit var stage: LinearLayout
    private lateinit var header: LinearLayout
    private lateinit var titleLabel: TextView
    private lateinit var indexLabel: TextView
    private lateinit var statusDot: View
    private lateinit var clockLabel: TextView
    private lateinit var progressTrack: FrameLayout
    private lateinit var progressFill: View
    private lateinit var pageHost: FrameLayout
    private lateinit var edgeLeft: View
    private lateinit var edgeRight: View
    private lateinit var chromePeek: View

    private var roster: List<PageDef> = emptyList()
    private var rosterKey = ""
    private var index = 0
    private var currentPage: PanelPage? = null
    private var chromeHidden = false
    private var dayKey = ""

    private val handler = Handler(Looper.getMainLooper())
    private var dwellTotalMs = 60_000L
    private var dwellLeftMs = 60_000L
    private var preloaded = false
    private var transitioning = false
    private var paused = false
    private var videoHold = false
    private var askedCalendar = false
    private var askedVideo = false
    private var fromSettings = false
    private var refreshing = false
    private var pendingBind = false

    private val clockTick = object : Runnable {
        override fun run() {
            clockLabel.text = SimpleDateFormat("HH:mm", Locale.CHINA).format(Date())
            val today = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
            if (today != dayKey) {
                dayKey = today
                applyThemeColors()
            }
            runCatching { currentPage?.tick() }
            updateStatus()
            handler.postDelayed(this, 1000L)
        }
    }

    private val dwellTick = object : Runnable {
        override fun run() {
            if (!paused && !transitioning && !videoHold) {
                dwellLeftMs -= 250L
                updateProgress()
                if (!preloaded && dwellLeftMs <= 8_000L) {
                    preloaded = true
                    roster.getOrNull(Math.floorMod(index + 1, roster.size.coerceAtLeast(1)))?.let {
                        runCatching { Pages.preload(this@KioskActivity, it.id, FeedRepository.lastState) }
                    }
                }
                if (dwellLeftMs <= 0L) {
                    turnBy(1)
                    return
                }
            }
            updateIndex()
            handler.postDelayed(this, 250L)
        }
    }

    private val pollTick = object : Runnable {
        override fun run() {
            refreshFeed()
            handler.postDelayed(this, 30_000L)
        }
    }

    /** Nudge the whole layout a few px every few minutes so static parts do not burn in. */
    private val shiftTick = object : Runnable {
        override fun run() {
            stage.animate().translationX(Ui.pxf(Random.nextInt(-6, 7).toFloat()))
                .translationY(Ui.pxf(Random.nextInt(-6, 7).toFloat())).setDuration(1200).start()
            handler.postDelayed(this, 4 * 60_000L)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Ui.init(this)
        buildViews()
        setContentView(root)
        applyImmersive()
        rebuildRoster()
        rosterKey = roster.joinToString(",") { it.id }
        showPage(0)
        refreshFeed()
        handler.post(clockTick)
        handler.postDelayed(pollTick, 30_000L)
        handler.postDelayed(shiftTick, 4 * 60_000L)
    }

    private fun buildViews() {
        root = FrameLayout(this)
        stage = Ui.column(this)
        header = Ui.row(this).apply {
            setPadding(Ui.px(Ui.PAD), Ui.px(10), Ui.px(18), Ui.px(6))
            setOnLongClickListener { openSettings(); true }
        }
        titleLabel = Ui.text(this, "", Ui.H1, Theme.text(), W.BOLD)
        // Two short lines (weekday / page · countdown) so the page title keeps its width.
        indexLabel = Ui.text(this, "", Ui.META, Theme.textFaint(), lines = 2, gravity = Gravity.END)
        statusDot = View(this)
        clockLabel = Ui.number(this, "", Ui.H1, Theme.text())
        val gear = Ui.text(this, "⚙", Ui.H1, Theme.textDim(), gravity = Gravity.CENTER).apply {
            setOnClickListener { openSettings() }
            setOnLongClickListener { openSettings(); true }
        }
        header.addView(titleLabel, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(indexLabel, Ui.wrap(start = 16, end = 20))
        header.addView(statusDot, Ui.fixed(22, 22, end = 24))
        header.addView(clockLabel, Ui.wrap(end = 6))
        header.addView(gear, Ui.fixed(96, 112))

        progressTrack = FrameLayout(this)
        progressFill = View(this)
        progressTrack.addView(progressFill, FrameLayout.LayoutParams(0, FrameLayout.LayoutParams.MATCH_PARENT))
        pageHost = FrameLayout(this)

        stage.addView(header, Ui.wide(132))
        stage.addView(progressTrack, Ui.wide(8))
        stage.addView(pageHost, Ui.flexV())
        root.addView(stage, FrameLayout.LayoutParams(-1, -1))

        edgeLeft = edgeZone(-1)
        edgeRight = edgeZone(1)
        root.addView(edgeLeft, FrameLayout.LayoutParams(0, 0))
        root.addView(edgeRight, FrameLayout.LayoutParams(0, 0))
        chromePeek = View(this).apply {
            visibility = View.GONE
            setOnLongClickListener { openSettings(); true }
        }
        root.addView(chromePeek, FrameLayout.LayoutParams(-1, Ui.px(120), Gravity.TOP))
        dayKey = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
        applyThemeColors()
    }

    /** Invisible tap strip at a screen edge: tap pages, long-press opens settings. */
    private fun edgeZone(delta: Int): View = View(this).apply {
        isClickable = true
        setOnClickListener { turnBy(delta) }
        setOnLongClickListener { openSettings(); true }
    }

    private fun layoutEdges() {
        root.post {
            val strip = (root.width * 0.18f).toInt().coerceAtLeast(Ui.px(120))
            val top = if (chromeHidden) Ui.px(120) else header.height + progressTrack.height
            val h = (root.height - top).coerceAtLeast(0)
            for ((v, g) in listOf(edgeLeft to Gravity.START, edgeRight to Gravity.END)) {
                v.layoutParams = FrameLayout.LayoutParams(strip, h, g or Gravity.TOP).apply { topMargin = top }
            }
            edgeLeft.bringToFront()
            edgeRight.bringToFront()
            chromePeek.bringToFront()
        }
    }

    private fun applyThemeColors() {
        root.setBackgroundColor(Theme.bg())
        progressTrack.setBackgroundColor(Theme.surface())
        progressFill.setBackgroundColor(Theme.accent())
    }
    override fun onResume() {
        super.onResume()
        paused = false
        applyImmersive()
        val cur = roster.getOrNull(index)?.id
        rebuildRoster()
        val key = roster.joinToString(",") { it.id }
        if (fromSettings) {
            fromSettings = false
            FeedCache.expireAll()
            refreshFeed()
        }
        if (key != rosterKey || currentPage == null) {
            rosterKey = key
            showPage(roster.indexOfFirst { it.id == cur }.let { if (it >= 0) it else 0 })
        } else {
            restartDwell()
        }
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
        handler.removeCallbacksAndMessages(null)
        currentPage?.onDisappear()
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        Ui.init(this)
        showPage(index)
    }

    @Suppress("DEPRECATION")
    private fun applyImmersive() {
        window?.decorView?.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            or View.SYSTEM_UI_FLAG_FULLSCREEN
            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION)
    }

    fun askCalendar() {
        if (askedCalendar) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED) return
        askedCalendar = true
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CALENDAR), 1002)
    }

    fun askVideo() {
        if (askedVideo) return
        val perm = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_VIDEO else Manifest.permission.READ_EXTERNAL_STORAGE
        if (ContextCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED) return
        askedVideo = true
        ActivityCompat.requestPermissions(this, arrayOf(perm), 1003)
    }

    fun turnFromPage() {
        if (!isFinishing) turnBy(1)
    }

    fun holdForVideo(hold: Boolean) {
        videoHold = hold
    }

    private fun refreshFeed() {
        if (refreshing) return
        refreshing = true
        lifecycleScope.launch {
            // Sources land one by one; coalesce rebinds to at most one per frame burst.
            runCatching { FeedRepository.refresh { handler.post { schedulePartialBind() } } }
                .onSuccess { bindCurrent(it) }
            refreshing = false
            updateStatus()
        }
    }

    private fun schedulePartialBind() {
        if (pendingBind) return
        pendingBind = true
        handler.postDelayed({
            pendingBind = false
            bindCurrent(FeedRepository.lastState)
        }, 300L)
    }

    private fun bindCurrent(state: PanelState) {
        runCatching { currentPage?.bind(state) }
        updateStatus()
    }

    /** Green: this page's data is fresh. Yellow: loading or showing old data. Red: failed with nothing to show. */
    private fun updateStatus() {
        val id = roster.getOrNull(index)?.id ?: return
        val feed = Pages.feedOf(id)
        val color = when {
            feed.isEmpty() -> Theme.ok()
            FeedCache.failures().containsKey(feed) -> if (FeedRepository.lastState.fetchedAt.containsKey(feed)) Theme.warn() else Theme.bad()
            !FeedRepository.lastState.fetchedAt.containsKey(feed) -> Theme.warn()
            else -> Theme.ok()
        }
        statusDot.background = Ui.rounded(color, 999)
    }

    private fun rebuildRoster() {
        roster = Prefs.enabledRoster()
    }

    private fun showPage(idx: Int) {
        if (roster.isEmpty()) return
        index = Math.floorMod(idx, roster.size)
        val def = roster[index]
        videoHold = false
        currentPage?.onDisappear()
        pageHost.removeAllViews()
        val page = runCatching { DefaultPageFactory.create(this, def.id, def.title) }.getOrElse { BoardPage(this, "hello") }
        currentPage = page
        pageHost.addView(page.root, FrameLayout.LayoutParams(-1, -1))
        titleLabel.text = def.title
        setChromeHidden(PageCatalog.isWebId(def.id) || def.kind == PageDef.Kind.WEB)
        runCatching { page.bind(FeedRepository.lastState) }
        page.onAppear()
        updateStatus()
        restartDwell()
    }

    private fun restartDwell() {
        handler.removeCallbacks(dwellTick)
        val def = roster.getOrNull(index) ?: return
        dwellTotalMs = Prefs.effectiveDwell(def) * 1000L
        dwellLeftMs = dwellTotalMs
        preloaded = false
        updateProgress()
        updateIndex()
        handler.postDelayed(dwellTick, 250L)
    }

    private fun updateIndex() {
        val tail = if (videoHold) "播放中" else "${((dwellLeftMs + 999) / 1000).coerceAtLeast(0)}s"
        indexLabel.text = "${Theme.dayName()}\n${index + 1}/${roster.size} · $tail"
    }

    private fun updateProgress() {
        val p = if (dwellTotalMs <= 0) 0f else 1f - dwellLeftMs.toFloat() / dwellTotalMs
        val lp = progressFill.layoutParams
        lp.width = (progressTrack.width * p.coerceIn(0f, 1f)).toInt()
        progressFill.layoutParams = lp
    }

    private fun turnBy(delta: Int) {
        if (transitioning || roster.isEmpty()) return
        transitioning = true
        handler.removeCallbacks(dwellTick)
        val travel = pageHost.width.coerceAtLeast(1).toFloat() * 0.2f
        val dir = if (delta >= 0) 1f else -1f
        pageHost.animate().cancel()
        pageHost.animate().translationX(-dir * travel).alpha(0f).setDuration(220).withEndAction {
            showPage(index + delta)
            pageHost.translationX = dir * travel
            pageHost.animate().translationX(0f).alpha(1f).setDuration(320).withEndAction { transitioning = false }.start()
        }.start()
    }

    private fun setChromeHidden(hidden: Boolean) {
        chromeHidden = hidden
        header.visibility = if (hidden) View.GONE else View.VISIBLE
        progressTrack.visibility = if (hidden) View.GONE else View.VISIBLE
        chromePeek.visibility = if (hidden) View.VISIBLE else View.GONE
        layoutEdges()
    }

    private fun openSettings() {
        fromSettings = true
        startActivity(Intent(this, SettingsActivity::class.java))
    }

    fun askPhotos() {
        val need = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        if (ContextCompat.checkSelfPermission(this, need) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(need), 1001)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            showPage(index)
        } else if (requestCode == 1002) {
            Toast.makeText(this, "没有日历权限，日程页会一直显示提示", Toast.LENGTH_LONG).show()
        }
    }
}
