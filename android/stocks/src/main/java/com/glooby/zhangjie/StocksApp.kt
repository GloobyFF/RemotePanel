package com.glooby.zhangjie

import android.app.Application

class StocksApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Store.init(this)
        SetupServer.start()
    }
}
