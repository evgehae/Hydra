package app.hydra

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AppItem(val pkg: String, val label: String, val icon: ImageBitmap?)

private fun loadApps(ctx: Context): List<AppItem> {
    val pm = ctx.packageManager
    val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
    return pm.queryIntentActivities(intent, 0)
        .distinctBy { it.activityInfo.packageName }
        .map { ri ->
            val icon = try {
                ri.loadIcon(pm).toBitmap(96, 96).asImageBitmap()
            } catch (t: Throwable) {
                null
            }
            AppItem(ri.activityInfo.packageName, ri.loadLabel(pm).toString(), icon)
        }
        .sortedBy { it.label.lowercase() }
}

@Composable
fun AppsScreen(prefs: Prefs) {
    val ctx = LocalContext.current
    var apps by remember { mutableStateOf<List<AppItem>>(emptyList()) }
    var selected by remember { mutableStateOf(prefs.splitApps) }
    var onlySelected by remember { mutableStateOf(prefs.splitOnlySelected) }
    var query by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        apps = withContext(Dispatchers.IO) { loadApps(ctx) }
    }

    val filtered = remember(apps, query) {
        val q = query.trim()
        if (q.isEmpty()) apps else apps.filter { it.label.contains(q, ignoreCase = true) }
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp)) {
            Text(
                stringResource(R.string.apps_title),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = onlySelected,
                    onClick = {
                        onlySelected = true
                        prefs.splitOnlySelected = true
                    },
                    label = { Text(stringResource(R.string.mode_only)) }
                )
                FilterChip(
                    selected = !onlySelected,
                    onClick = {
                        onlySelected = false
                        prefs.splitOnlySelected = false
                    },
                    label = { Text(stringResource(R.string.mode_except)) }
                )
            }
            Spacer(Modifier.height(6.dp))
            Text(
                stringResource(if (onlySelected) R.string.mode_only_hint else R.string.mode_except_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(10.dp))
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                singleLine = true,
                placeholder = { Text(stringResource(R.string.apps_search)) },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                modifier = Modifier.fillMaxWidth()
            )
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    stringResource(R.string.apps_selected, selected.size),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row {
                    TextButton(onClick = {
                        val n = selected + filtered.map { it.pkg }
                        selected = n
                        prefs.splitApps = n
                    }) { Text(stringResource(R.string.apps_all)) }
                    TextButton(onClick = {
                        val n = selected - filtered.map { it.pkg }.toSet()
                        selected = n
                        prefs.splitApps = n
                    }) { Text(stringResource(R.string.apps_none)) }
                }
            }
        }

        LazyColumn(Modifier.fillMaxSize()) {
            items(filtered, key = { it.pkg }) { a ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickable {
                            val n = if (a.pkg in selected) selected - a.pkg else selected + a.pkg
                            selected = n
                            prefs.splitApps = n
                        }
                        .padding(horizontal = 20.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (a.icon != null) {
                        Image(bitmap = a.icon, contentDescription = null, modifier = Modifier.size(40.dp))
                    } else {
                        Box(Modifier.size(40.dp))
                    }
                    Spacer(Modifier.width(14.dp))
                    Text(a.label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    Checkbox(checked = a.pkg in selected, onCheckedChange = null)
                }
            }
        }
    }
}
