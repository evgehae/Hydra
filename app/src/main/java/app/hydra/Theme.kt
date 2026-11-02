package app.hydra

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary = Color(0xFF3DDBB0),
    onPrimary = Color(0xFF00382A),
    primaryContainer = Color(0xFF0E3B31),
    onPrimaryContainer = Color(0xFFB9F6E4),
    secondary = Color(0xFF9CC4B8),
    onSecondary = Color(0xFF0B2A22),
    background = Color(0xFF0A110F),
    onBackground = Color(0xFFE1EAE6),
    surface = Color(0xFF0A110F),
    onSurface = Color(0xFFE1EAE6),
    surfaceVariant = Color(0xFF16221E),
    onSurfaceVariant = Color(0xFFAFC0BA),
    outline = Color(0xFF50635C),
    error = Color(0xFFFF8A80),
    onError = Color(0xFF410002)
)

private val LightColors = lightColorScheme(
    primary = Color(0xFF00796B),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFCDEFE6),
    onPrimaryContainer = Color(0xFF00201A),
    secondary = Color(0xFF4A635C),
    background = Color(0xFFF5FAF8),
    onBackground = Color(0xFF111917),
    surface = Color(0xFFF5FAF8),
    onSurface = Color(0xFF111917),
    surfaceVariant = Color(0xFFE2EDE9),
    onSurfaceVariant = Color(0xFF3E4E49),
    outline = Color(0xFF70827B),
    error = Color(0xFFBA1A1A)
)

@Composable
fun HydraTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}
