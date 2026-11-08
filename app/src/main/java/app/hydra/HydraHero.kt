package app.hydra

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import kotlin.math.PI
import kotlin.math.sin

/**
 * Что делает Гидра. Головы зажигаются по очереди и остаются гореть:
 * аккаунт готов — у левой горят глаза; регистрация — левая дышит огнём;
 * подключение — к левой добавляется правая; «подключено» — горят все три.
 */
enum class HeroMode { Off, Registered, Registering, Connecting, Connected, Failed }

private class HeadSpec(val eyes: List<Offset>, val mouth: Offset, val dir: Offset)

// Координаты — доли картинки hero_hydra (глаза, пасти, замочная скважина).
private val LEFT = HeadSpec(listOf(Offset(0.155f, 0.345f)), Offset(0.1125f, 0.4418f), Offset(-0.85f, 0.45f))
private val CENTER = HeadSpec(listOf(Offset(0.452f, 0.297f), Offset(0.554f, 0.297f)), Offset(0.5f, 0.4418f), Offset(0f, 1f))
private val RIGHT = HeadSpec(listOf(Offset(0.845f, 0.345f)), Offset(0.873f, 0.463f), Offset(0.85f, 0.45f))
private val KEYHOLE = Offset(0.49f, 0.713f)

// Огонь везде огненный: от белого жара к оранжевому и красному.
private val FIRE_IN = Color(0xFFFFF4B0)
private val FIRE_MID = Color(0xFFFF9A2E)
private val FIRE_OUT = Color(0xFFE8341A)

// уровни: 0 — тёмная, 1 — горят глаза, 2 — спокойный огонь, 3 — сильный огонь
private fun levels(mode: HeroMode): Triple<Int, Int, Int> = when (mode) {
    HeroMode.Off -> Triple(0, 0, 0)
    HeroMode.Registered -> Triple(1, 0, 0)
    HeroMode.Registering -> Triple(3, 0, 0)
    HeroMode.Connecting -> Triple(2, 0, 3)
    HeroMode.Connected -> Triple(2, 3, 2)
    HeroMode.Failed -> Triple(0, 0, 0)
}

@Composable
fun HydraHero(mode: HeroMode, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val inf = rememberInfiniteTransition(label = "hero")
    val t by inf.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1300, easing = LinearEasing)),
        label = "t"
    )
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(504f / 498f)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClick() }
    ) {
        Image(
            painter = painterResource(R.drawable.hero_hydra),
            contentDescription = null,
            contentScale = ContentScale.FillBounds,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    // растушёвка краёв, чтобы картинка растворялась в фоне
                    drawRect(
                        brush = Brush.radialGradient(
                            0.0f to Color.Black,
                            0.74f to Color.Black,
                            1.0f to Color.Transparent,
                            center = center,
                            radius = size.maxDimension * 0.62f
                        ),
                        blendMode = BlendMode.DstIn
                    )
                }
        )
        Canvas(Modifier.fillMaxSize()) {
            if (mode == HeroMode.Failed) {
                val red = Color(0xFFFF5A5A)
                head(LEFT, red, t, 1)
                head(CENTER, red, t, 1)
                head(RIGHT, red, t, 1)
                keyhole(red, t, 0.6f)
            } else {
                val (l, c, r) = levels(mode)
                head(LEFT, NeonAmber, t, l)
                head(RIGHT, NeonPink, t, r)
                head(CENTER, Color(0xFF4DFFD0), t, c)
                val k = maxOf(l, c, r)
                if (k > 0) keyhole(if (c > 0) NeonGreen else NeonAmber, t, if (c > 0) 1f else 0.6f)
            }
        }
    }
}

private fun DrawScope.at(o: Offset) = Offset(o.x * size.width, o.y * size.height)

/** Светящиеся глаза (level ≥ 1) и огонь изо рта (level ≥ 2; 3 — сильнее). */
private fun DrawScope.head(h: HeadSpec, eye: Color, t: Float, level: Int) {
    if (level <= 0) return
    val pulse = 0.78f + 0.22f * sin(t * 2f * PI.toFloat() * 2f)
    val r = size.width * 0.024f
    for (e in h.eyes) {
        val c = at(e)
        drawCircle(
            brush = Brush.radialGradient(
                listOf(eye.copy(alpha = 0.95f * pulse), Color.Transparent),
                center = c,
                radius = r * 3.4f
            ),
            radius = r * 3.4f,
            center = c,
            blendMode = BlendMode.Plus
        )
        drawCircle(Color.White.copy(alpha = pulse), r * 0.55f, c)
    }
    if (level < 2) return

    val strong = level >= 3
    val len = size.width * (if (strong) 0.36f else 0.22f)
    val n = if (strong) 40 else 24
    val dir = h.dir / h.dir.getDistance()
    val perp = Offset(-dir.y, dir.x)
    val origin = at(h.mouth)

    // раскалённое свечение у пасти
    drawCircle(
        brush = Brush.radialGradient(
            listOf(FIRE_MID.copy(alpha = 0.55f * pulse), Color.Transparent),
            center = origin,
            radius = len * 0.45f
        ),
        radius = len * 0.45f,
        center = origin,
        blendMode = BlendMode.Plus
    )
    // языки пламени
    for (i in 0 until n) {
        val ph = (t + i.toFloat() / n) % 1f
        val wob = sin(ph * 2f * PI.toFloat() * 2.2f + i * 1.9f) * len * 0.16f * ph
        val p = origin + dir * (ph * len) + perp * wob
        val pr = len * 0.20f * (1f - ph * 0.8f)
        val col = when {
            ph < 0.22f -> FIRE_IN
            ph < 0.55f -> FIRE_MID
            else -> FIRE_OUT
        }
        drawCircle(
            brush = Brush.radialGradient(
                listOf(col.copy(alpha = 0.95f * (1f - ph)), Color.Transparent),
                center = p,
                radius = pr * 2.1f
            ),
            radius = pr * 2.1f,
            center = p,
            blendMode = BlendMode.Plus
        )
    }
    // искры
    val sparks = if (strong) 10 else 5
    for (i in 0 until sparks) {
        val ph = (t * 1.5f + i * 0.37f) % 1f
        val side = sin(i * 12.9898f) * len * 0.35f * ph
        val p = origin + dir * (ph * len * 1.25f) + perp * side
        drawCircle(FIRE_IN.copy(alpha = 0.9f * (1f - ph)), size.width * 0.006f, p)
    }
}

private fun DrawScope.keyhole(color: Color, t: Float, strength: Float) {
    val c = at(KEYHOLE)
    val k = strength * (0.7f + 0.3f * sin(t * 2f * PI.toFloat()))
    drawCircle(
        brush = Brush.radialGradient(listOf(color.copy(alpha = 0.55f * k), Color.Transparent), center = c, radius = size.width * 0.09f),
        radius = size.width * 0.09f,
        center = c,
        blendMode = BlendMode.Plus
    )
}
