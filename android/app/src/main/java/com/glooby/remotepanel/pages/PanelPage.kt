package com.glooby.remotepanel.pages

import android.content.Context
import android.view.View
import com.glooby.remotepanel.data.PanelState

interface PanelPage {
    val root: View
    fun bind(state: PanelState)
    fun onAppear() {}
    fun onDisappear() {}
    /** Called about once a second while the page is on screen. */
    fun tick() {}
}

interface PanelPageFactory {
    fun create(context: Context, pageId: String, title: String): PanelPage
}
