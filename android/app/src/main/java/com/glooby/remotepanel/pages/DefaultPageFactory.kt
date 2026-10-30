package com.glooby.remotepanel.pages

import android.content.Context
import com.glooby.remotepanel.data.PageCatalog

object DefaultPageFactory : PanelPageFactory {
    override fun create(context: Context, pageId: String, title: String): PanelPage {
        return when {
            PageCatalog.isWebId(pageId) -> WebPage(context, pageId)
            pageId == "hello" -> HelloPage(context)
            pageId == "weather" -> WeatherPage(context)
            pageId == "daily-news" -> NewsPage(context)
            pageId == "stocks-cn" -> QuotePage(context, crypto = false)
            pageId == "crypto" -> QuotePage(context, crypto = true)
            pageId.startsWith("person-photo-local") -> PhotoPage(context)
            else -> HelloPage(context)
        }
    }
}
