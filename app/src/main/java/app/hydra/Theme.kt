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
    primary = NeonViolet,
    onPrimary = Color(0xFF1B0F52),
    primaryContainer = Color(0xFF0F2A57),
    onPrimaryContainer = Color(0xFFCFE8FF),
    secondary = NeonCyan,
    onSecondary = Color(0xFF00243D),
    tertiary = NeonGreen,
    background = Color(0xFF080C18),
    onBackground = Color(0xFFE6ECFA),
    surface = Color(0xFF080C18),
    onSurface = Color(0xFFE6ECFA),
    surfaceVariant = Color(0xFF111B33),
    onSurfaceVariant = Color(0xFFA9B6D3),
    outline = Color(0xFF3C4B70),
    error = Color(0xFFFF8A80),
    onError = Color(0xFF410002)
)

/** Гидра всегда тёмная: неон на карбоне. */
@Composable
fun HydraTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = HydraColors, content = content)
}

/** Плитка «карбона» 24×24: тёмные и чуть светлее квадраты в шахматном порядке. */
private fun carbonTile(): ImageBitmap {
    val bmp = ImageBitmap(24, 24)
    val c = GfxCanvas(bmp)
    val dark = Paint().apply { color = Color(0xFF0A0F1D) }
    val light = Paint().apply { color = Color(0xFF0F1628) }
    c.drawRect(0f, 0f, 24f, 24f, dark)
    c.drawRect(0f, 0f, 12f, 12f, light)
    c.drawRect(12f, 12f, 24f, 24f, light)
    return bmp
}

/** Фон приложения: карбон с мягким неоновым свечением сверху. */
@Composable
fun HydraBackground(content: @Composable () -> Unit) {
    val tile = remember { carbonTile() }
    val carbon = remember(tile) { ShaderBrush(ImageShader(tile, TileMode.Repeated, TileMode.Repeated)) }
    Box(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF080C18))
            .drawBehind { drawRect(brush = carbon) }
            .background(
                Brush.verticalGradient(
                    listOf(NeonPink.copy(alpha = 0.10f), Color.Transparent, NeonOrange.copy(alpha = 0.07f))
                )
            )
    ) { content() }
}

/** Заголовок с радужной заливкой, как у RotatorOS. */
@Composable
fun RainbowText(text: String, fontSize: TextUnit = 28.sp, letterSpacing: TextUnit = 0.sp) {
    Text(
        text,
        style = TextStyle(
            brush = Brush.linearGradient(RainbowColors),
            fontSize = fontSize,
            fontWeight = FontWeight.Bold,
            letterSpacing = letterSpacing
        )
    )
}
