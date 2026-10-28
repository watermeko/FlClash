package icu.watermeko.clash

import android.app.Application
import android.content.Context
import icu.watermeko.clash.common.GlobalState

class FlClashApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}
