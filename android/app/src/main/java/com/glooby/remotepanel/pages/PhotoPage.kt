package com.glooby.remotepanel.pages

import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.bumptech.glide.Glide
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Prefs
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.net.NetShare
import com.glooby.remotepanel.ui.Ui
import kotlin.random.Random

/** Full-screen random photo from a network folder (SMB or HTTP directory). */
class PhotoPage(private val context: android.content.Context) : PanelPage {
    private val photoView = ImageView(context).apply {
        scaleType = ImageView.ScaleType.FIT_CENTER
        setBackgroundColor(Color.BLACK)
    }
    private val caption = Ui.text(context, "", Ui.BODY, Color.WHITE, lines = 2).apply {
        setBackgroundColor(0x99000000.toInt())
        setPadding(Ui.px(Ui.PAD), Ui.px(20), Ui.px(Ui.PAD), Ui.px(24))
    }
    override val root = FrameLayout(context).apply {
        setBackgroundColor(Theme.bg())
        addView(photoView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))
        addView(caption, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM
        ))
    }
    private val names = mutableListOf<NetShare.FileRef>()
    private var token = 0
    private val handler = Handler(Looper.getMainLooper())
    private val tick = Runnable { showRandom() }

    override fun bind(state: PanelState) = Unit

    override fun onAppear() {
        val dir = Prefs.photoDir()
        if (dir.isBlank()) {
            caption.text = "在设置里填写照片目录，例如 smb://192.168.1.10/share/photos 或 http://地址/photos/"
            photoView.setImageDrawable(null)
            return
        }
        caption.text = "正在读取 $dir"
        val mine = ++token
        Thread {
            val files = runCatching { NetShare.listImages(dir) }.getOrElse {
                handler.post {
                    if (mine == token) caption.text = "目录读不到：${it.message ?: "失败"}"
                }
                return@Thread
            }
            handler.post {
                if (mine != token) return@post
                names.clear()
                names += files
                if (names.isEmpty()) {
                    caption.text = "这个目录里没有 jpg / png / webp"
                } else {
                    showRandom()
                }
            }
        }.start()
    }

    override fun onDisappear() {
        token++
        handler.removeCallbacks(tick)
        photoView.setImageDrawable(null)
    }

    private fun showRandom() {
        if (names.isEmpty()) return
        val file = names[Random.nextInt(names.size)]
        caption.text = "${file.name}  ·  ${names.size} 张里随机"
        Thread {
            val bytes = runCatching { NetShare.readBytes(file.url) }.getOrNull()
            handler.post {
                if (bytes == null || bytes.isEmpty()) {
                    caption.text = "这张读不出来：${file.name}"
                } else {
                    Glide.with(context.applicationContext).load(bytes).fitCenter().into(photoView)
                }
                handler.removeCallbacks(tick)
                handler.postDelayed(tick, 8000L)
            }
        }.start()
    }
}
