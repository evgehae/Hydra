package app.hydra

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.Canvas as GfxCanvas
import androidx.compose.material3.Text
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

// Неоновая палитра Гидры.
val NeonCyan = Color(0xFF47D4FF)
val NeonViolet = Color(0xFFA98BFF)
val NeonPink = Color(0xFFFF7AD9)
val NeonGreen = Color(0xFF84E36B)
val NeonAmber = Color(0xFFFFC857)
val NeonOrange = Color(0xFFFF9A62)

/** Радуга для заголовков: голубой → синий → фиолетовый → розовый → оранжевый → янтарный. */
val RainbowColors = listOf(
    Color(0xFF4DD2FF), Color(0xFF7C8CFF), Color(0xFFB06BFF),
    Color(0xFFFF6BD6), Color(0xFFFF9A62), Color(0xFFFFD166)
)
val HydraGreen = NeonGreen

private val HydraColors = darkColorScheme(
    primary = Color(0xFF2F6BFF),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF0F2A57),
    onPrimaryContainer = Color(0xFFCFE8FF),
    secondary = Color(0xFF3949D8),
    onSecondary = Color.White,
    tertiary = NeonGreen,
    background = Color.Black,
    onBackground = Color.White,
    surface = Color.Black,
    onSurface = Color.White,
    surfaceVariant = Color(0xFF1E1E1E),
    onSurfaceVariant = Color(0xFF9E9E9E),
    outline = Color(0xFF3A3A3A),
    error = Color(0xFFFF6B6B),
    onError = Color(0xFF410002)
)

/** Гидра всегда тёмная: неон на карбоне. */
@Composable
fun HydraTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = HydraColors, content = content)
}

/** Фон приложения: чистый чёрный, как у 1.1.1.1. */
@Composable
fun HydraBackground(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black)) { content() }
}

/** Заголовок экрана: обычный жирный белый текст (имя оставлено для совместимости). */
@Composable
fun RainbowText(text: String, fontSize: TextUnit = 28.sp, letterSpacing: TextUnit = 0.sp) {
    Text(text, style = TextStyle(fontSize = fontSize, fontWeight = FontWeight.Bold, letterSpacing = letterSpacing))
}
