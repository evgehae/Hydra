package app.hydra
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Плоская тёмно-серая карточка (accent оставлен для совместимости и не используется). */
@Composable
fun HCard(
    modifier: Modifier = Modifier,
    accent: Color = NeonCyan,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(Modifier.padding(16.dp), content = content)
    }
}

@Composable
fun SectionTitle(text: String, color: Color = Color.Unspecified) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        color = color
    )
}

enum class StepState { Done, Pending, Failed }

/** Строка чек-листа: значок состояния, заголовок, пояснение и необязательное действие справа. */
@Composable
fun StepRow(
    state: StepState,
    title: String,
    subtitle: String,
    actionLabel: String? = null,
    onAction: () -> Unit = {}
) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val icon = when (state) {
            StepState.Done -> Icons.Filled.CheckCircle
            StepState.Failed -> Icons.Filled.Warning
            StepState.Pending -> Icons.Filled.Info
        }
        val tint = when (state) {
            StepState.Done -> MaterialTheme.colorScheme.primary
            StepState.Failed -> MaterialTheme.colorScheme.error
            StepState.Pending -> MaterialTheme.colorScheme.outline
        }
        Icon(icon, contentDescription = null, tint = tint)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (actionLabel != null) {
            TextButton(onClick = onAction) { Text(actionLabel) }
        }
    }
}

@Composable
fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
fun failText(kind: String): String = stringResource(
    when (kind) {
        "rate_limited" -> R.string.fail_rate_limited
        "blocked" -> R.string.fail_blocked
        "dns" -> R.string.fail_dns
        "api" -> R.string.fail_api
        else -> R.string.fail_other
    }
)

private val COLO_NAMES = mapOf(
    "DME" to "Moscow", "LED" to "Saint Petersburg", "SVX" to "Yekaterinburg",
    "KJA" to "Krasnoyarsk", "OVB" to "Novosibirsk", "KHV" to "Khabarovsk",
    "VVO" to "Vladivostok", "KZN" to "Kazan",
    "HEL" to "Helsinki", "FRA" to "Frankfurt", "AMS" to "Amsterdam",
    "ARN" to "Stockholm", "WAW" to "Warsaw", "VIE" to "Vienna",
    "PRG" to "Prague", "CDG" to "Paris", "LHR" to "London",
    "MAD" to "Madrid", "MXP" to "Milan", "ZRH" to "Zurich",
    "OSL" to "Oslo", "CPH" to "Copenhagen", "RIX" to "Riga",
    "VNO" to "Vilnius", "TLL" to "Tallinn", "IST" to "Istanbul"
)

/** "HEL · Helsinki" или просто код, если город неизвестен. */
fun coloLabel(code: String): String {
    val c = code.uppercase()
    val city = COLO_NAMES[c]
    return if (city != null) "$c · $city" else c
}

/** Разбирает "DME, led;fra" в множество кодов в верхнем регистре. */
fun parseColos(s: String): Set<String> =
    s.split(',', ';', ' ', '\n').map { it.trim().uppercase() }.filter { it.isNotEmpty() }.toSet()

// ---------- Экраны настроек в стиле 1.1.1.1 ----------

/** Страница с серой шапкой: стрелка «назад» и заголовок. */
@Composable
fun SubPage(title: String, onBack: () -> Unit, scroll: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .height(56.dp)
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null) }
            Spacer(Modifier.width(16.dp))
            Text(title, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        val m = if (scroll) Modifier.fillMaxSize().verticalScroll(rememberScrollState()) else Modifier.fillMaxSize()
        Column(m, content = content)
    }
}

@Composable
fun RowDivider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Color(0xFF2C2C2C)))
}

/** Строка списка: заголовок, необязательные пояснение и значение справа. */
@Composable
fun SettingRow(title: String, subtitle: String? = null, value: String? = null, onClick: (() -> Unit)? = null) {
    var m = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant)
    if (onClick != null) m = m.clickable { onClick() }
    Row(m.padding(horizontal = 16.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (value != null) {
            Spacer(Modifier.width(12.dp))
            Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(0.6f, fill = false))
        }
    }
    RowDivider()
}

@Composable
fun SettingSwitchRow(title: String, subtitle: String? = null, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable { onChange(!checked) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onChange)
    }
    RowDivider()
}

/** Мелкая подпись раздела на чёрном фоне. */
@Composable
fun SectionLabel(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(start = 16.dp, top = 22.dp, bottom = 8.dp)
    )
}

@Composable
fun NoteText(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
    )
}

/** Диалог с одной строкой ввода: «Сбросить» / «Применить». */
@Composable
fun TextDialog(
    title: String,
    initial: String,
    hint: String,
    onDismiss: () -> Unit,
    onApply: (String) -> Unit,
    onReset: (() -> Unit)? = null
) {
    var v by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(value = v, onValueChange = { v = it }, singleLine = true, placeholder = { Text(hint) })
        },
        confirmButton = { TextButton(onClick = { onApply(v.trim()) }) { Text(stringResource(R.string.btn_apply)) } },
        dismissButton = {
            if (onReset != null) TextButton(onClick = onReset) { Text(stringResource(R.string.btn_reset)) }
            else TextButton(onClick = onDismiss) { Text(stringResource(R.string.btn_cancel)) }
        }
    )
}

/** Подтверждение опасного действия. */
@Composable
fun ConfirmDialog(title: String, text: String, onDismiss: () -> Unit, onOk: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = { TextButton(onClick = onOk) { Text(stringResource(R.string.btn_ok)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.btn_cancel)) } }
    )
}
