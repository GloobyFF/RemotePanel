package com.glooby.remotepanel.pages

import android.graphics.Color
import android.net.Uri
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.VideoView
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Prefs
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.net.NetShare
import com.glooby.remotepanel.net.SmbStreamServer
import com.glooby.remotepanel.ui.KioskActivity
import kotlin.random.Random

/** Plays one random file from an SMB folder, then advances. */
class VideoPage(private val context: android.content.Context) : PanelPage {
    private val video = VideoView(context)
    private val status = TextView(context).apply {
        setTextColor(Color.WHITE)
        textSize = 16f
        gravity = Gravity.CENTER
        setPadding(36, 36, 36, 36)
    }
    override val root = FrameLayout(context).apply {
        setBackgroundColor(Color.BLACK)
        addView(video, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))
        addView(status, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))
    }
    private val bridge = SmbStreamServer()
    private var token = 0
    private var lastName: String? = null

    override fun bind(state: PanelState) = Unit

    override fun onAppear() {
        val dir = Prefs.videoSmb()
        if (dir.isBlank() || !dir.startsWith("smb", ignoreCase = true)) {
            status.text = "在设置里填写视频的 SMB 文件夹，例如 smb://192.168.1.10/share/videos"
            (context as? KioskActivity)?.holdForVideo(false)
            return
        }
        status.text = "正在打开共享文件夹…"
        val mine = ++token
        Thread {
            val files = runCatching { NetShare.listVideos(dir) }.getOrElse {
                post(mine) {
                    status.text = "SMB 读不到：${it.message ?: "失败"}"
                    (context as? KioskActivity)?.holdForVideo(false)
                }
                return@Thread
            }
            val pick = files.filter { it.name != lastName }.ifEmpty { files }.let {
                if (it.isEmpty()) null else it[Random.nextInt(it.size)]
            }
            post(mine) {
                if (pick == null) {
                    status.text = "这个文件夹里没有 mp4 / mov / m4v"
                    (context as? KioskActivity)?.holdForVideo(false)
                    return@post
                }
                lastName = pick.name
                status.text = pick.name
                val local = runCatching { bridge.start(pick.url) }.getOrNull()
                if (local == null) {
                    status.text = "这段视频打不开"
                    (context as? KioskActivity)?.holdForVideo(false)
                    return@post
                }
                video.setOnPreparedListener {
                    status.text = ""
                    (context as? KioskActivity)?.holdForVideo(true)
                }
                video.setOnCompletionListener {
                    (context as? KioskActivity)?.holdForVideo(false)
                    (context as? KioskActivity)?.turnFromPage()
                }
                video.setOnErrorListener { _, _, _ ->
                    status.text = "播不了：${pick.name}"
                    (context as? KioskActivity)?.holdForVideo(false)
                    true
                }
                video.setVideoURI(Uri.parse(local))
                video.start()
            }
        }.start()
    }

    override fun onDisappear() {
        token++
        video.stopPlayback()
        bridge.stop()
        (context as? KioskActivity)?.holdForVideo(false)
    }

    private fun post(mine: Int, block: () -> Unit) {
        root.post { if (mine == token) block() }
    }
}
