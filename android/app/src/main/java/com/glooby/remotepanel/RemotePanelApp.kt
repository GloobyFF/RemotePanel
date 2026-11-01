package com.glooby.remotepanel

import android.app.Application
import com.glooby.remotepanel.data.Prefs
import com.glooby.remotepanel.net.ImageFetch

class RemotePanelApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        ImageFetch.install(this)
    }
}
