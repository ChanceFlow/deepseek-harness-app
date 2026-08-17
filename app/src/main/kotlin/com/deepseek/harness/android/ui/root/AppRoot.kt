package com.deepseek.harness.android.ui.root

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.deepseek.harness.android.ui.chat.ChatRoute
import com.deepseek.harness.android.ui.models.ModelsRoute
import com.deepseek.harness.android.ui.workspace.WorkspaceRoute

private enum class AppDestination(val label: String) {
    CHAT("Chat"),
    WORKSPACES("Workspaces"),
    MODELS("Models"),
}

@Composable
fun AppRoot(modifier: Modifier = Modifier) {
    var selectedIndex by remember { mutableIntStateOf(0) }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        bottomBar = {
            NavigationBar {
                AppDestination.entries.forEachIndexed { index, destination ->
                    NavigationBarItem(
                        selected = selectedIndex == index,
                        onClick = { selectedIndex = index },
                        icon = { Text(destination.label.take(1)) },
                        label = { Text(destination.label) },
                    )
                }
            }
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when (AppDestination.entries[selectedIndex]) {
                AppDestination.CHAT -> ChatRoute()
                AppDestination.WORKSPACES -> WorkspaceRoute()
                AppDestination.MODELS -> ModelsRoute()
            }
        }
    }
}
