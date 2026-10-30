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
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import com.glooby.remotepanel.R
import com.glooby.remotepanel.data.FeedRepository
import com.glooby.remotepanel.data.PageCatalog
import com.glooby.remotepanel.data.PageDef
import com.glooby.remotepanel.data.Prefs
import com.glooby.remotepanel.data.Theme
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

    private val clockTick = object : Runnable {
        override fun run() {
            clockLabel.text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            applyThemeColors()
            handler.postDelayed(this, 1000L)
        }
    }

    private val dwellTick = object : Runnable {
        override fun run() {
            if (!transitioning) {
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
        hideSystemBars()
        pageHostTop = (pageHost.layoutParams as ViewGroup.MarginLayoutParams).topMargin
        pageHostBottom = (pageHost.layoutParams as ViewGroup.MarginLayoutParams).bottomMargin

        findViewById<ImageButton>(R.id.settingsBtn).setOnClickListener { openSettings() }
        edgeLeft.setOnClickListener { turnBy(-1) }
        edgeRight.setOnClickListener { turnBy(1) }
        val longOpen = View.OnLongClickListener {
            openSettings()
            true
        }
        edgeLeft.setOnLongClickListener(longOpen)
        edgeRight.setOnLongClickListener(longOpen)
        chromePeek.setOnLongClickListener(longOpen)

        ensurePhotoPermission()
        rebuildRoster()
        showPage(0, resetDwell = true)
        refreshFeed()
        handler.post(clockTick)
        handler.post(pollTick)
    }

    override fun onResume() {
        super.onResume()
        hideSystemBars()
        // Settings may have changed.
        val cur = roster.getOrNull(index)?.id
        rebuildRoster()
        val newIdx = roster.indexOfFirst { it.id == cur }.let { if (it >= 0) it else 0 }
        showPage(newIdx, resetDwell = true)
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

    private fun hideSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, root).let { c ->
            c.hide(WindowInsetsCompat.Type.systemBars())
            c.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    private fun applyThemeColors() {
        root.setBackgroundColor(Theme.bg())
        if (!chromeHidden) {
            // chrome stays translucent over themed bg
        }
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
                    currentPage?.bind(it)
                }
                .onFailure {
                    statusPill.text = getString(R.string.stale)
                    statusPill.setBackgroundColor(
                        ContextCompat.getColor(this@KioskActivity, R.color.rp_warn)
                    )
                }
        }
    }

    private fun showPage(idx: Int, resetDwell: Boolean) {
        if (roster.isEmpty()) return
        var i = idx
        if (i < 0) i = roster.lastIndex
        if (i > roster.lastIndex) i = 0
        index = i
        val def = roster[i]

        currentPage?.onDisappear()
        pageHost.removeAllViews()

        val page = DefaultPageFactory.create(this, def.id, def.title)
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
        page.bind(FeedRepository.lastState)
        page.onAppear()
        layoutEdgeCatchers()

        if (resetDwell) restartDwell()
        transitioning = false
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
        val w = (progressTrack.width * p.coerceIn(0f, 1f)).toInt()
        val lp = progressFill.layoutParams
        lp.width = w
        progressFill.layoutParams = lp
    }

    private fun turnBy(delta: Int) {
        if (transitioning || roster.isEmpty()) return
        transitioning = true
        handler.removeCallbacks(dwellTick)
        showPage(index + delta, resetDwell = true)
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

    private fun ensurePhotoPermission() {
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
    }
}
