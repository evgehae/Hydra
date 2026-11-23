package app.hydra

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

/** «Поддержать проект»: реквизиты автора. Номер копируется одним нажатием. */
object Support {
    const val BANK = "Сбербанк"
    const val CARD = "2202206277761198"
    val cardPretty: String get() = CARD.chunked(4).joinToString(" ")
}

@Composable
fun SupportDialog(onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Поддержать проект") },
        text = {
            Text(
                "Если Гидра пригодилась и хочется сказать спасибо — можно скинуть на развитие проекта.\n\n" +
                    "${Support.BANK}\n${Support.cardPretty}\n\nПриложение бесплатное, поддержка добровольная."
            )
        },
        confirmButton = {
            TextButton(onClick = {
                try {
                    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("card", Support.CARD))
                    Toast.makeText(ctx, "Номер карты скопирован. Спасибо!", Toast.LENGTH_LONG).show()
                } catch (_: Exception) {}
                onDismiss()
            }) { Text("Скопировать номер") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Закрыть") } }
    )
}
