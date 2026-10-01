package com.bucks.app

import android.app.Application
import com.bucks.app.data.BucksRepository
import com.bucks.app.data.FakeBucksRepository

class BucksApp : Application() {
    lateinit var repository: BucksRepository
        private set
    override fun onCreate() {
        super.onCreate()
        com.bucks.app.data.Cloud.init(this)
        com.bucks.app.data.AppLife.init(this)
        com.bucks.app.data.Prefs.init(this)
        com.bucks.app.data.Push.ensureChannels(this)
        repository = FakeBucksRepository(this)
    }
}
