package com.digitalsignage.player.ui

import android.app.AlertDialog
import android.content.pm.ActivityInfo
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.PointerIcon
import android.view.WindowManager
import android.widget.EditText
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.digitalsignage.player.core.player.ExoPlayerController

class MainActivity : ComponentActivity() {

    private val viewModel: PlayerViewModel by viewModels()
    private lateinit var exoPlayerController: ExoPlayerController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 0. Bloquear Orientação (Landscape) em código para evitar avisos no Manifest (Android 16+)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE

        // 1. Forçar Tela Sempre Ligada (24/7 Kiosk Operation)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // 2. Aplicar Modo Imersivo Completo (Ocultar Barra de Status e Navegação)
        enableImmersiveStickyMode()

        // 3. Ocultar Cursor do Mouse (em TV Boxes)
        hideMousePointer()

        exoPlayerController = ExoPlayerController(this)

        setContent {
            val uiState by viewModel.uiState.collectAsState()

            PlayerScreen(
                uiState = uiState,
                exoPlayerController = exoPlayerController,
                onVideoCompleted = {
                    viewModel.onVideoPlaybackCompleted()
                },
                onOpenSettings = {
                    viewModel.openSettings()
                },
                onCloseSettings = {
                    viewModel.closeSettings()
                },
                onSaveSettings = { host, port, name ->
                    viewModel.saveServerConfig(host, port, name)
                },
                onTestConnection = { host, port ->
                    viewModel.testConnection(host, port)
                }
            )
        }
    }

    override fun onResume() {
        super.onResume()
        enableImmersiveStickyMode()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            enableImmersiveStickyMode()
        }
    }

    private fun enableImmersiveStickyMode() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }

    private fun hideMousePointer() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                window.decorView.pointerIcon = PointerIcon.getSystemIcon(this, PointerIcon.TYPE_NULL)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            // Tecla DPAD Center, OK ou F1: Alternar OSD de diagnóstico
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_F1 -> {
                viewModel.toggleOsd()
                true
            }
            // Tecla MENU ou F5: Forçar sincronização imediata com o CMS
            KeyEvent.KEYCODE_MENU,
            KeyEvent.KEYCODE_F5 -> {
                viewModel.registerAndSync()
                Toast.makeText(this, "Sincronização iniciada...", Toast.LENGTH_SHORT).show()
                true
            }
            // Tecla BACK: Solicitar senha de administrador para sair do Kiosk
            KeyEvent.KEYCODE_BACK -> {
                promptAdminExit()
                true
            }
            else -> super.onKeyDown(keyCode, event)
        }
    }

    private fun promptAdminExit() {
        val input = EditText(this).apply {
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
            hint = "Senha de Administrador"
        }

        AlertDialog.Builder(this)
            .setTitle("Digital Signage Kiosk")
            .setMessage("Digite a senha de administrador para encerrar o Player:")
            .setView(input)
            .setPositiveButton("Sair") { _, _ ->
                val enteredPassword = input.text.toString()
                if (enteredPassword == viewModel.getAdminPassword()) {
                    finishAffinity()
                } else {
                    Toast.makeText(this, "Senha incorreta!", Toast.LENGTH_SHORT).show()
                    enableImmersiveStickyMode()
                }
            }
            .setNegativeButton("Cancelar") { dialog, _ ->
                dialog.dismiss()
                enableImmersiveStickyMode()
            }
            .setCancelable(false)
            .show()
    }

    override fun onDestroy() {
        super.onDestroy()
        exoPlayerController.release()
    }
}
