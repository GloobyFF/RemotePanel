package com.glooby.remotepanel.pages

import android.content.Context
import com.glooby.remotepanel.data.PageCatalog

object DefaultPageFactory : PanelPageFactory {
    override fun create(context: Context, pageId: String, title: String): PanelPage {
        return when {
            PageCatalog.isWebId(pageId) -> WebPage(context, pageId)
            pageId.startsWith("person-photo-local") -> PhotoPage(context)
            pageId == "local-video" -> VideoPage(context)
            else -> BoardPage(context, pageId)
        }
    }
}
