package com.bucks.app

import android.app.Application
import com.bucks.app.data.BucksRepository
import com.bucks.app.data.FakeBucksRepository
import kotlinx.coroutines.launch

class BucksApp : Application() {
    lateinit var repository: BucksRepository
        private set
    override fun onCreate() {
        super.onCreate()
        com.bucks.app.data.Cloud.init(this)
        com.bucks.app.data.AppLife.init(this)
        com.bucks.app.data.Countries.init(this)
        com.bucks.app.data.Str.init(this)
        com.bucks.app.data.Prefs.init(this)
        com.bucks.app.data.Prefs.countLaunch()
        com.bucks.app.data.Analytics.init(this)
        com.bucks.app.data.Push.ensureChannels(this)
        // Tier 1 of the assistant: restore the on-device model's state, then check the remote switch once sign-in has had time to restore.
        com.bucks.app.ai.IntentModel.init(this)
        com.bucks.app.data.AppLife.scope.launch { kotlinx.coroutines.delay(15_000); com.bucks.app.ai.IntentModel.refresh() }
        repository = FakeBucksRepository(this)
    }
}
