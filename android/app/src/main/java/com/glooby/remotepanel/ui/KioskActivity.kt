package com.glooby.remotepanel.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.glooby.remotepanel.R
import com.glooby.remotepanel.data.FeedRepository
import com.glooby.remotepanel.data.PageCatalog
import com.glooby.remotepanel.data.PageDef
import com.glooby.remotepanel.data.Prefs
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.pages.BoardPage
import com.glooby.remotepanel.pages.DefaultPageFactory
import com.glooby.remotepanel.pages.PanelPage
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class KioskActivity : AppCompatActivity() {
    private lateinit var root: View
    private lateinit var pageHost: FrameLayout
    private lateinit var chrome: View
    private lateinit var progressTrack: View
    private lateinit var progressFill: View
    private lateinit var titleLabel: TextView
    private lateinit var indexLabel: TextView
    private lateinit var clockLabel: TextView
    private lateinit var statusPill: TextView
    private lateinit var edgeLeft: View
    private lateinit var edgeRight: View
    private lateinit var chromePeek: View

    private var roster: List<PageDef> = emptyList()
    private var index = 0
    private var currentPage: PanelPage? = null
    private var chromeHidden = false
    private var pageHostTop: Int = 0
    private var pageHostBottom: Int = 0

    private val handler = Handler(Looper.getMainLooper())
    private var dwellTotalMs = 60_000L
    private var dwellLeftMs = 60_000L
    private var transitioning = false
    private var rosterKey = ""
    private var askedCalendar = false
    private var askedVideo = false
    private var videoHold = false

    private val clockTick = object : Runnable {
        override fun run() {
            clockLabel.text = "${Theme.dayName()} " + SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            applyThemeColors()
            handler.postDelayed(this, 1000L)
        }
    }

    private val dwellTick = object : Runnable {
        override fun run() {
            if (videoHold) {
                indexLabel.text = "${index + 1}/${roster.size} · 播放"
            } else if (!transitioning) {
                dwellLeftMs -= 250L
                updateProgress()
                indexLabel.text = "${index + 1}/${roster.size} · ${((dwellLeftMs + 999) / 1000)}s"
                if (dwellLeftMs <= 2400L) {
                    turnBy(1)
                    return
                }
            }
            handler.postDelayed(this, 250L)
        }
    }

    private val pollTick = object : Runnable {
        override fun run() {
            refreshFeed()
            handler.postDelayed(this, 30_000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_kiosk)
        bindViews()
        applyImmersive()
        pageHostTop = (pageHost.layoutParams as ViewGroup.MarginLayoutParams).topMargin
        pageHostBottom = (pageHost.layoutParams as ViewGroup.MarginLayoutParams).bottomMargin

        findViewById<ImageButton>(R.id.settingsBtn).setOnClickListener { openSettings() }
        findViewById<ImageButton>(R.id.prevBtn).setOnClickListener { turnBy(-1) }
        findViewById<ImageButton>(R.id.nextBtn).setOnClickListener { turnBy(1) }
        chromePeek.setOnLongClickListener {
            openSettings()
            true
        }
        root.setOnLongClickListener {
            openSettings()
            true
        }

        rebuildRoster()
        rosterKey = roster.joinToString(",") { it.id }
        showPage(0, resetDwell = true)
        refreshFeed()
        handler.post(clockTick)
        handler.post(pollTick)
    }

    override fun onResume() {
        super.onResume()
        applyImmersive()
        val cur = roster.getOrNull(index)?.id
        rebuildRoster()
        val key = roster.joinToString(",") { it.id }
        if (key != rosterKey || currentPage == null) {
            rosterKey = key
            val newIdx = roster.indexOfFirst { it.id == cur }.let { if (it >= 0) it else 0 }
            showPage(newIdx, resetDwell = true)
        }
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
        layoutEdgeCatchers()
        currentPage?.bind(FeedRepository.lastState)
    }

    private fun bindViews() {
        root = findViewById(R.id.root)
        pageHost = findViewById(R.id.pageHost)
        chrome = findViewById(R.id.chrome)
        progressTrack = findViewById(R.id.progressTrack)
        progressFill = findViewById(R.id.progressFill)
        titleLabel = findViewById(R.id.titleLabel)
        indexLabel = findViewById(R.id.indexLabel)
        clockLabel = findViewById(R.id.clockLabel)
        statusPill = findViewById(R.id.statusPill)
        edgeLeft = findViewById(R.id.edgeLeft)
        edgeRight = findViewById(R.id.edgeRight)
        chromePeek = findViewById(R.id.chromePeek)
    }

    @Suppress("DEPRECATION")
    private fun applyImmersive() {
        val decor = window?.decorView ?: return
        decor.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            )
    }

    fun askCalendar() {
        if (askedCalendar) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED
        ) return
        askedCalendar = true
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CALENDAR), 1002)
    }

    fun askVideo() {
        if (askedVideo) return
        val perm = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.READ_MEDIA_VIDEO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (ContextCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED) return
        askedVideo = true
        ActivityCompat.requestPermissions(this, arrayOf(perm), 1003)
    }

    fun turnFromPage() {
        if (!isFinishing) turnBy(1)
    }

    private fun applyThemeColors() {
        root.setBackgroundColor(Theme.bg())
        progressTrack.setBackgroundColor(0x38FFFFFF)
        progressFill.setBackgroundColor(Theme.accent())
    }

    private fun rebuildRoster() {
        roster = Prefs.enabledRoster()
    }

    private fun refreshFeed() {
        lifecycleScope.launch {
            statusPill.text = "更新"
            statusPill.setBackgroundColor(Theme.accent())
            runCatching { FeedRepository.refresh() }
                .onSuccess {
                    statusPill.text = getString(R.string.live)
                    statusPill.setBackgroundColor(
                        ContextCompat.getColor(this@KioskActivity, R.color.rp_ok)
                    )
                    runCatching { currentPage?.bind(it) }
                }
                .onFailure {
                    statusPill.text = getString(R.string.stale)
                    statusPill.setBackgroundColor(
                        ContextCompat.getColor(this@KioskActivity, R.color.rp_warn)
                    )
                }
        }
    }

    fun holdForVideo(hold: Boolean) {
        videoHold = hold
    }

    private fun showPage(idx: Int, resetDwell: Boolean) {
        if (roster.isEmpty()) return
        var i = idx
        if (i < 0) i = roster.lastIndex
        if (i > roster.lastIndex) i = 0
        index = i
        val def = roster[i]

        videoHold = false
        currentPage?.onDisappear()
        pageHost.removeAllViews()

        val page = runCatching { DefaultPageFactory.create(this, def.id, def.title) }
            .getOrElse { BoardPage(this, "hello") }
        currentPage = page
        pageHost.addView(
            page.root,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        titleLabel.text = def.title
        setChromeHidden(PageCatalog.isWebId(def.id) || def.kind == PageDef.Kind.WEB)
        runCatching { page.bind(FeedRepository.lastState) }
        page.onAppear()
        layoutEdgeCatchers()

        if (resetDwell) restartDwell()
    }

    private fun restartDwell() {
        handler.removeCallbacks(dwellTick)
        val def = roster.getOrNull(index) ?: return
        dwellTotalMs = Prefs.effectiveDwell(def) * 1000L
        dwellLeftMs = dwellTotalMs
        updateProgress()
        indexLabel.text = "${index + 1}/${roster.size} · ${dwellTotalMs / 1000}s"
        handler.post(dwellTick)
    }

    private fun updateProgress() {
        val p = if (dwellTotalMs <= 0) 0f else 1f - (dwellLeftMs.toFloat() / dwellTotalMs.toFloat())
        val full = progressTrack.width.takeIf { it > 0 } ?: root.width
        val w = (full * p.coerceIn(0f, 1f)).toInt()
        val lp = progressFill.layoutParams
        lp.width = w
        progressFill.layoutParams = lp
        progressFill.setBackgroundColor(Theme.accent())
        progressTrack.setBackgroundColor(0x38FFFFFF.toInt())
    }

    private fun turnBy(delta: Int) {
        if (transitioning || roster.isEmpty()) return
        transitioning = true
        handler.removeCallbacks(dwellTick)
        val travel = pageHost.width.coerceAtLeast(root.width).coerceAtLeast(1).toFloat()
        val forward = delta >= 0
        val style = Math.floorMod(index + if (forward) 1 else 0, 3)
        pageHost.animate().cancel()
        pageHost.animate()
            .translationX(if (style == 1) 0f else (if (forward) -travel else travel) * 0.22f)
            .translationY(if (style == 1) (if (forward) -48f else 48f) else 0f)
            .alpha(0f)
            .setDuration(240)
            .withEndAction {
                showPage(index + delta, resetDwell = true)
                pageHost.translationX = if (style == 1) 0f else (if (forward) travel else -travel) * 0.18f
                pageHost.translationY = if (style == 1) (if (forward) 56f else -56f) else 0f
                pageHost.alpha = 0f
                pageHost.scaleX = if (style == 2) 0.94f else 1f
                pageHost.scaleY = if (style == 2) 0.94f else 1f
                pageHost.animate()
                    .translationX(0f)
                    .translationY(0f)
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(340)
                    .withEndAction { transitioning = false }
                    .start()
            }
            .start()
    }

    private fun setChromeHidden(hidden: Boolean) {
        chromeHidden = hidden
        chrome.visibility = if (hidden) View.GONE else View.VISIBLE
        progressTrack.visibility = if (hidden) View.GONE else View.VISIBLE
        progressFill.visibility = if (hidden) View.GONE else View.VISIBLE
        chromePeek.visibility = if (hidden) View.VISIBLE else View.GONE
        val lp = pageHost.layoutParams as ViewGroup.MarginLayoutParams
        if (hidden) {
            lp.topMargin = 0
            lp.bottomMargin = 0
        } else {
            lp.topMargin = pageHostTop
            lp.bottomMargin = pageHostBottom
        }
        pageHost.layoutParams = lp
        layoutEdgeCatchers()
    }

    private fun layoutEdgeCatchers() {
        root.post {
            val w = root.width
            val h = root.height
            val strip = maxOf((w * 0.20f).toInt(), 72)
            val top = if (chromeHidden) 0 else chrome.bottom
            val bottom = if (chromeHidden) h else progressTrack.top.coerceAtLeast(top)
            val eh = (bottom - top).coerceAtLeast(0)
            edgeLeft.layoutParams = FrameLayout.LayoutParams(strip, eh).apply {
                gravity = android.view.Gravity.START or android.view.Gravity.TOP
                topMargin = top
            }
            edgeRight.layoutParams = FrameLayout.LayoutParams(strip, eh).apply {
                gravity = android.view.Gravity.END or android.view.Gravity.TOP
                topMargin = top
            }
            edgeLeft.requestLayout()
            edgeRight.requestLayout()
            edgeLeft.bringToFront()
            edgeRight.bringToFront()
            if (chromeHidden) chromePeek.bringToFront()
            if (!chromeHidden) {
                chrome.bringToFront()
                progressTrack.bringToFront()
                progressFill.bringToFront()
            }
        }
    }

    private fun openSettings() {
        startActivity(Intent(this, SettingsActivity::class.java))
    }

    fun askPhotos() {
        val need = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (ContextCompat.checkSelfPermission(this, need) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(need), 1001)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001 && grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) {
            Toast.makeText(this, "未授予相册权限，本地相册页将为空", Toast.LENGTH_LONG).show()
        }
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            runCatching { currentPage?.bind(FeedRepository.lastState) }
            currentPage?.onAppear()
        }
    }
}
