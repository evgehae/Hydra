package app.hydra

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/** Цвет «подключено». */
val HydraGreen = Color(0xFF35E0A1)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF3DB4FF),
    onPrimary = Color(0xFF00243D),
    primaryContainer = Color(0xFF0F2A57),
    onPrimaryContainer = Color(0xFFCFE8FF),
    secondary = Color(0xFF9B86FF),
    onSecondary = Color(0xFF1B0F52),
    background = Color(0xFF070C1A),
    onBackground = Color(0xFFE6ECFA),
    surface = Color(0xFF070C1A),
    onSurface = Color(0xFFE6ECFA),
    surfaceVariant = Color(0xFF111B33),
    onSurfaceVariant = Color(0xFFA9B6D3),
    outline = Color(0xFF3C4B70),
    error = Color(0xFFFF8A80),
    onError = Color(0xFF410002)
)

private val LightColors = lightColorScheme(
    primary = Color(0xFF0B73C9),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD3E6FF),
    onPrimaryContainer = Color(0xFF001C38),
    secondary = Color(0xFF5B45D6),
    background = Color(0xFFF4F7FF),
    onBackground = Color(0xFF101827),
    surface = Color(0xFFF4F7FF),
    onSurface = Color(0xFF101827),
    surfaceVariant = Color(0xFFE3EAFB),
    onSurfaceVariant = Color(0xFF3F4B66),
    outline = Color(0xFF7683A3),
    error = Color(0xFFBA1A1A)
)

@Composable
fun HydraTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}

/** Фон приложения: мягкий вертикальный градиент. */
@Composable
fun HydraBackground(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val brush = if (dark) {
        Brush.verticalGradient(listOf(Color(0xFF070C1A), Color(0xFF0B1735)))
    } else {
        Brush.verticalGradient(listOf(Color(0xFFF4F7FF), Color(0xFFE4ECFF)))
    }
    Box(Modifier.fillMaxSize().background(brush)) { content() }
}
