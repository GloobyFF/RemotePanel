package com.glooby.remotepanel.pages

import android.content.Context
import android.view.View
import com.glooby.remotepanel.data.PanelState

interface PanelPage {
    val root: View
    fun bind(state: PanelState)
    fun onAppear() {}
    fun onDisappear() {}
}

interface PanelPageFactory {
    fun create(context: Context, pageId: String, title: String): PanelPage
}
