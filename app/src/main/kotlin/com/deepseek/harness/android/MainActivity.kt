package com.deepseek.harness.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.deepseek.harness.android.ui.chat.ChatRoute
import com.deepseek.harness.android.ui.theme.DeepSeekHarnessAndroidTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            DeepSeekHarnessAndroidTheme {
                ChatRoute()
            }
        }
    }
}
