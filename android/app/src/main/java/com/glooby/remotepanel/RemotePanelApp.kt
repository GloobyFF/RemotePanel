package com.glooby.remotepanel

import android.app.Application
import com.glooby.remotepanel.data.Prefs

class RemotePanelApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
    }
}
