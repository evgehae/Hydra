package app.hydra

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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Карточка-контейнер с мягкими углами. */
@Composable
fun HCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(Modifier.padding(16.dp), content = content)
    }
}

@Composable
fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
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
