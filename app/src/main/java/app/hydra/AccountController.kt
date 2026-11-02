package app.hydra

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Состояние аккаунта WARP, общее для экранов; регистрация идёт в Go-ядре. */
class AccountController(private val dir: String, private val scope: CoroutineScope) {

    var id by mutableStateOf(readId())
        private set
    var busy by mutableStateOf(false)
        private set
    var report by mutableStateOf("")
        private set

    private fun readId(): String =
        try { mobile.Mobile.accountID(dir) } catch (t: Throwable) { "" }

    /** "" если ошибки нет, иначе вид: rate_limited | blocked | api | storage | internal. */
    val failKind: String
        get() = if (report.startsWith("FAIL")) {
            report.lineSequence().first().removePrefix("FAIL").trim()
        } else {
            ""
        }

    fun register() {
        if (busy) return
        busy = true
        report = ""
        scope.launch {
            report = withContext(Dispatchers.IO) {
                try {
                    mobile.Mobile.registerReport(dir)
                } catch (t: Throwable) {
                    "FAIL internal\n" + t.message
                }
            }
            id = readId()
            busy = false
        }
    }

    fun export(): String =
        try { mobile.Mobile.exportAccount(dir) } catch (t: Throwable) { "" }

    /** Пустая строка — успех, иначе текст ошибки. */
    fun importFrom(text: String): String {
        val err = try {
            mobile.Mobile.importAccount(dir, text)
        } catch (t: Throwable) {
            t.message ?: "error"
        }
        id = readId()
        return err
    }
}
