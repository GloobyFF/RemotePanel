package com.glooby.remotepanel.pages

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.bumptech.glide.Glide
import com.glooby.remotepanel.R
import com.glooby.remotepanel.data.PanelState

class PhotoPage(private val context: android.content.Context) : PanelPage {
    override val root = LayoutInflater.from(context).inflate(R.layout.page_photo, null)
    private val photoView: ImageView = root.findViewById(R.id.photoView)
    private val caption: TextView = root.findViewById(R.id.caption)
    private val empty: TextView = root.findViewById(R.id.empty)
    private val uris = mutableListOf<Uri>()
    private var index = 0
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            if (uris.size > 1) {
                index = (index + 1) % uris.size
                showCurrent()
            }
            handler.postDelayed(this, 8000L)
        }
    }

    override fun bind(state: PanelState) {
        // Photos are local; feed state unused.
    }

    override fun onAppear() {
        loadAlbum()
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, 8000L)
    }

    override fun onDisappear() {
        handler.removeCallbacks(tick)
        photoView.setImageDrawable(null)
    }

    private fun hasPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= 33) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_IMAGES) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun loadAlbum() {
        uris.clear()
        if (!hasPermission()) {
            empty.visibility = View.VISIBLE
            empty.text = "请授予照片读取权限（设置里也可再次触发）"
            caption.text = "无相册权限"
            return
        }
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATE_ADDED)
        context.contentResolver.query(
            collection,
            projection,
            null,
            null,
            "${MediaStore.Images.Media.DATE_ADDED} DESC"
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            var n = 0
            while (c.moveToNext() && n < 80) {
                val id = c.getLong(idCol)
                uris += ContentUris.withAppendedId(collection, id)
                n++
            }
        }
        if (uris.isEmpty()) {
            empty.visibility = View.VISIBLE
            caption.text = "相册 · 0"
        } else {
            empty.visibility = View.GONE
            index = 0
            showCurrent()
        }
    }

    private fun showCurrent() {
        if (uris.isEmpty()) return
        val uri = uris[index]
        Glide.with(photoView).load(uri).centerCrop().into(photoView)
        caption.text = "本地相册 · ${index + 1}/${uris.size}"
    }
}
