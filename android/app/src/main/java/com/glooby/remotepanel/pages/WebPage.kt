package com.glooby.remotepanel.pages

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.view.LayoutInflater
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.TextView
import com.glooby.remotepanel.R
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Prefs

class WebPage(
    context: android.content.Context,
    private val pageId: String
) : PanelPage {
    override val root = LayoutInflater.from(context).inflate(R.layout.page_web, null)
    private val web: WebView = root.findViewById(R.id.webView)
    private val status: TextView = root.findViewById(R.id.status)
    private var lastUrl: String? = null

    init {
        @SuppressLint("SetJavaScriptEnabled")
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.settings.mediaPlaybackRequiresUserGesture = false
        web.webChromeClient = WebChromeClient()
        web.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                status.visibility = View.VISIBLE
                status.text = "正在打开网页…"
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                status.visibility = View.GONE
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                if (request?.isForMainFrame == true) {
                    status.visibility = View.VISIBLE
                    status.text = root.context.getString(R.string.web_fail) + "\n" + (error?.description ?: "")
                }
            }
        }
    }

    override fun bind(state: PanelState) {
        reload()
    }

    override fun onAppear() {
        reload()
    }

    override fun onDisappear() {
        web.stopLoading()
        web.loadUrl("about:blank")
        lastUrl = null
    }

    private fun reload() {
        val cfg = Prefs.findWebPage(pageId)
        var url = cfg?.url?.trim().orEmpty()
        if (url.isEmpty()) {
            web.visibility = View.GONE
            status.visibility = View.VISIBLE
            status.text = root.context.getString(R.string.web_empty)
            return
        }
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            url = "http://$url"
        }
        web.visibility = View.VISIBLE
        if (url == lastUrl) {
            status.visibility = View.GONE
            return
        }
        lastUrl = url
        web.loadUrl(url)
    }
}
