package dev.ember.android

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import dev.ember.android.data.Auth
import dev.ember.android.ui.EmberTheme
import dev.ember.android.ui.Loading
import dev.ember.core.CoreException
import dev.ember.core.EmberCore
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private var app by mutableStateOf<AppState?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycleScope.launch {
            val core = EmberCore.start(applicationContext, BuildConfig.CLOUD_ORIGIN)
            app = AppState(core, getSharedPreferences("ember", Context.MODE_PRIVATE), BuildConfig.CLOUD_ORIGIN)
            handle(intent)
        }
        setContent {
            val current = app
            val dark = current?.dark ?: isSystemInDarkTheme()
            LaunchedEffect(dark) {
                val bars = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
                enableEdgeToEdge(bars, bars)
            }
            EmberTheme(dark) {
                if (current == null) Loading("正在启动…")
                else CompositionLocalProvider(LocalApp provides current) { EmberApp(current) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /** ember cloud's sign-in comes back as ember://auth/callback?…; the core finishes it. */
    private fun handle(intent: Intent?) {
        val uri = intent?.data ?: return
        val app = app ?: return
        if (uri.scheme != "ember" || uri.host != "auth") return
        setIntent(Intent())
        lifecycleScope.launch {
            try {
                Auth.complete(app.core, "?" + (uri.encodedQuery ?: ""))
                app.home()
            } catch (e: CoreException) {
                app.toast = "登录没有完成：${e.message}"
            }
        }
    }
}
