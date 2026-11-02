package app.hydra

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SettingsScreen(prefs: Prefs, account: AccountController, onLanguageChanged: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    var lang by remember { mutableStateOf(prefs.lang) }
    var block by remember { mutableStateOf(prefs.blockedColos) }
    var allow by remember { mutableStateOf(prefs.allowColos) }
    var auto by remember { mutableStateOf(prefs.autoStart) }
    var kill by remember { mutableStateOf(prefs.killSwitch) }
    var note by remember { mutableStateOf("") }

    val copiedMsg = stringResource(R.string.account_copied)
    val nothingMsg = stringResource(R.string.account_nothing)
    val importedMsg = stringResource(R.string.account_imported)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            stringResource(R.string.settings_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        // Язык
        HCard {
            SectionTitle(stringResource(R.string.settings_language))
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "system" to R.string.lang_system,
                    "en" to R.string.lang_en,
                    "ru" to R.string.lang_ru
                ).forEach { (code, res) ->
                    FilterChip(
                        selected = lang == code,
                        onClick = {
                            if (lang != code) {
                                lang = code
                                prefs.lang = code
                                onLanguageChanged()
                            }
                        },
                        label = { Text(stringResource(res)) }
                    )
                }
            }
        }

        // Дата-центры Cloudflare
        HCard {
            SectionTitle(stringResource(R.string.colo_title))
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = block,
                onValueChange = {
                    block = it.uppercase()
                    prefs.blockedColos = block
                },
                label = { Text(stringResource(R.string.colo_block)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = allow,
                onValueChange = {
                    allow = it.uppercase()
                    prefs.allowColos = allow
                },
                label = { Text(stringResource(R.string.colo_allow)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                stringResource(R.string.colo_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
            TextButton(onClick = {
                block = prefs.defaultBlockedColos()
                prefs.blockedColos = block
                allow = ""
                prefs.allowColos = ""
            }) { Text(stringResource(R.string.colo_reset)) }
        }

        // Аккаунт WARP
        HCard {
            SectionTitle(stringResource(R.string.account_title))
            Spacer(Modifier.height(4.dp))
            Text(
                if (account.id.isEmpty()) {
                    stringResource(R.string.step_account_none)
                } else {
                    stringResource(R.string.step_account_ok, account.id.take(8))
                },
                style = MaterialTheme.typography.bodyMedium
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = { account.register() },
                enabled = !account.busy && account.id.isEmpty(),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth().height(48.dp)
            ) {
                if (account.busy) {
                    CircularProgressIndicator(
                        Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                } else {
                    Text(stringResource(R.string.action_register))
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = {
                        val s = account.export()
                        if (s.isEmpty()) {
                            note = nothingMsg
                        } else {
                            clipboard.setText(AnnotatedString(s))
                            note = copiedMsg
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.account_copy)) }
                OutlinedButton(
                    onClick = {
                        val text = clipboard.getText()?.text.orEmpty()
                        val err = account.importFrom(text)
                        note = if (err.isEmpty()) importedMsg else err
                    },
                    modifier = Modifier.weight(1f)
                ) { Text(stringResource(R.string.account_paste)) }
            }
            Text(
                stringResource(R.string.account_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp)
            )
            if (note.isNotEmpty()) {
                Text(
                    note,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            if (account.failKind.isNotEmpty()) {
                Text(
                    failText(account.failKind),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            if (account.report.isNotEmpty()) {
                Text(
                    account.report,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }

        // Подключение
        HCard {
            SectionTitle(stringResource(R.string.conn_title))
            SwitchRow(stringResource(R.string.settings_autostart), auto) {
                auto = it
                prefs.autoStart = it
            }
            SwitchRow(stringResource(R.string.settings_killswitch), kill) {
                kill = it
                prefs.killSwitch = it
            }
            Text(
                stringResource(R.string.settings_soon),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // О программе
        HCard {
            SectionTitle(stringResource(R.string.about_title))
            Spacer(Modifier.height(4.dp))
            Text(stringResource(R.string.about_text), style = MaterialTheme.typography.bodySmall)
            val engine = remember { try { mobile.Mobile.version() } catch (t: Throwable) { "n/a" } }
            Text(
                stringResource(R.string.engine_label, engine),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}
