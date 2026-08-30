package com.digitalsignage.player.ui

import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.digitalsignage.player.core.engine.MediaType
import com.digitalsignage.player.core.player.ExoPlayerController
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(
    uiState: PlayerUiState,
    exoPlayerController: ExoPlayerController,
    onVideoCompleted: () -> Unit,
    onOpenSettings: () -> Unit,
    onCloseSettings: () -> Unit,
    onSaveSettings: (host: String, port: Int, name: String) -> Unit,
    onTestConnection: (host: String, port: Int) -> Unit
) {
    val context = LocalContext.current
    val exoPlayer = remember { exoPlayerController.initializePlayer() }

    DisposableEffect(Unit) {
        exoPlayerController.onMediaEnded = onVideoCompleted
        onDispose {
            exoPlayerController.stop()
        }
    }

    LaunchedEffect(uiState.currentItem, uiState.playbackSessionId) {
        val item = uiState.currentItem
        if (item != null && item.type == MediaType.VIDEO) {
            exoPlayerController.playFile(item.localFile)
        } else {
            exoPlayerController.stop()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        Crossfade(
            targetState = uiState.currentItem,
            animationSpec = tween(500),
            label = "MediaCrossfade"
        ) { currentItem ->
            if (currentItem != null) {
                when (currentItem.type) {
                    MediaType.VIDEO -> {
                        AndroidView(
                            factory = { ctx ->
                                PlayerView(ctx).apply {
                                    player = exoPlayer
                                    useController = false
                                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                                    layoutParams = FrameLayout.LayoutParams(
                                        ViewGroup.LayoutParams.MATCH_PARENT,
                                        ViewGroup.LayoutParams.MATCH_PARENT
                                    )
                                }
                            },
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    MediaType.IMAGE -> {
                        AsyncImage(
                            model = ImageRequest.Builder(context)
                                .data(currentItem.localFile)
                                .crossfade(true)
                                .build(),
                            contentDescription = "Signage Image",
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    else -> {
                        IdlePlaceholder(
                            message = uiState.statusMessage,
                            onOpenSettings = onOpenSettings
                        )
                    }
                }
            } else {
                IdlePlaceholder(
                    message = uiState.statusMessage,
                    onOpenSettings = onOpenSettings
                )
            }
        }

        // Botão de acesso rápido a Configurações no canto superior direito
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            contentAlignment = Alignment.TopEnd
        ) {
            Button(
                onClick = onOpenSettings,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0x88212121),
                    contentColor = Color.White
                ),
                shape = RoundedCornerShape(8.dp)
            ) {
                Text(text = "⚙️ Configurar Servidor", fontSize = 12.sp)
            }
        }

        // On-Screen Display (OSD) Bar para depuração e telemetria
        if (uiState.isOsdVisible) {
            OsdOverlay(uiState = uiState)
        }

        // Diálogo de Configuração de IP e Porta
        if (uiState.isSettingsOpen) {
            SettingsDialog(
                uiState = uiState,
                onDismiss = onCloseSettings,
                onSave = onSaveSettings,
                onTestConnection = onTestConnection
            )
        }
    }
}

@Composable
fun IdlePlaceholder(
    message: String,
    onOpenSettings: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F0F14))
            .padding(24.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            CircularProgressIndicator(
                color = Color(0xFF388E3C),
                modifier = Modifier.size(48.dp)
            )
            Spacer(modifier = Modifier.height(20.dp))
            Text(
                text = "Digital Signage Player",
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = message,
                color = Color(0xFFAAAAAA),
                fontSize = 15.sp,
                modifier = Modifier.padding(horizontal = 32.dp)
            )
            Spacer(modifier = Modifier.height(24.dp))
            Button(
                onClick = onOpenSettings,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF1976D2),
                    contentColor = Color.White
                )
            ) {
                Text("⚙️ Configurar IP e Porta do Servidor")
            }
        }
    }
}

@Composable
fun SettingsDialog(
    uiState: PlayerUiState,
    onDismiss: () -> Unit,
    onSave: (host: String, port: Int, name: String) -> Unit,
    onTestConnection: (host: String, port: Int) -> Unit
) {
    var hostText by remember(uiState.serverHost) { mutableStateOf(uiState.serverHost) }
    var portText by remember(uiState.serverPort) { mutableStateOf(uiState.serverPort.toString()) }
    var nameText by remember(uiState.playerName) { mutableStateOf(uiState.playerName) }

    val currentCalculatedUrl = remember(hostText, portText) {
        val p = portText.toIntOrNull() ?: 8080
        "http://${hostText.trim()}:$p"
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth(0.9f)
                .padding(16.dp),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(
                containerColor = Color(0xFF1E1E26)
            )
        ) {
            Column(
                modifier = Modifier
                    .padding(24.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    text = "Configuração do Servidor CMS",
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Defina o endereço IP e porta onde o servidor backend Lazarus está rodando:",
                    color = Color(0xFFB0B0B0),
                    fontSize = 13.sp
                )

                Spacer(modifier = Modifier.height(16.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    OutlinedTextField(
                        value = hostText,
                        onValueChange = { hostText = it },
                        label = { Text("IP ou Host do Servidor") },
                        placeholder = { Text("ex: 192.168.15.119") },
                        singleLine = true,
                        modifier = Modifier.weight(0.7f),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedBorderColor = Color(0xFF2196F3),
                            unfocusedBorderColor = Color(0xFF555566),
                            focusedLabelColor = Color(0xFF2196F3),
                            unfocusedLabelColor = Color(0xFFAAAAAA)
                        )
                    )

                    OutlinedTextField(
                        value = portText,
                        onValueChange = { portText = it.filter { ch -> ch.isDigit() } },
                        label = { Text("Porta") },
                        placeholder = { Text("8080") },
                        singleLine = true,
                        modifier = Modifier.weight(0.3f),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedBorderColor = Color(0xFF2196F3),
                            unfocusedBorderColor = Color(0xFF555566),
                            focusedLabelColor = Color(0xFF2196F3),
                            unfocusedLabelColor = Color(0xFFAAAAAA)
                        )
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                OutlinedTextField(
                    value = nameText,
                    onValueChange = { nameText = it },
                    label = { Text("Nome de Identificação da Tela") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedBorderColor = Color(0xFF2196F3),
                        unfocusedBorderColor = Color(0xFF555566),
                        focusedLabelColor = Color(0xFF2196F3),
                        unfocusedLabelColor = Color(0xFFAAAAAA)
                    )
                )

                Spacer(modifier = Modifier.height(12.dp))

                // Detalhes da URL e UUID
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF14141B), RoundedCornerShape(8.dp))
                        .padding(12.dp)
                ) {
                    Column {
                        Text(
                            text = "URL Final: $currentCalculatedUrl",
                            color = Color(0xFF64B5F6),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "UUID: ${uiState.playerUuid}",
                            color = Color(0xFF888899),
                            fontSize = 11.sp,
                            fontFamily = FontFamily.Monospace
                        )
                    }
                }

                // Status do Teste de Conexão
                if (uiState.testConnectionStatus != null) {
                    Spacer(modifier = Modifier.height(12.dp))
                    val status = uiState.testConnectionStatus
                    val isTesting = status == "TESTING"
                    val isSuccess = status.startsWith("SUCCESS")

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(
                                if (isSuccess) Color(0xFF1B3B2B) else if (isTesting) Color(0xFF2A2A38) else Color(0xFF3E1B1B),
                                RoundedCornerShape(8.dp)
                            )
                            .padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (isTesting) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                color = Color(0xFF2196F3),
                                strokeWidth = 2.dp
                            )
                            Spacer(modifier = Modifier.width(10.dp))
                            Text(
                                text = "Testando conexão com o servidor...",
                                color = Color.White,
                                fontSize = 13.sp
                            )
                        } else {
                            Text(
                                text = status,
                                color = if (isSuccess) Color(0xFF81C784) else Color(0xFFE57373),
                                fontSize = 12.sp
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(20.dp))

                // Botões de Ação
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    OutlinedButton(
                        onClick = {
                            val p = portText.toIntOrNull() ?: 8080
                            onTestConnection(hostText, p)
                        },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = Color(0xFF64B5F6)
                        )
                    ) {
                        Text("Testar Conexão", fontSize = 13.sp)
                    }

                    Button(
                        onClick = {
                            val p = portText.toIntOrNull() ?: 8080
                            onSave(hostText, p, nameText)
                        },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFF388E3C),
                            contentColor = Color.White
                        )
                    ) {
                        Text("Salvar e Sincronizar", fontSize = 13.sp)
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                OutlinedButton(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = Color(0xFFAAAAAA)
                    )
                ) {
                    Text("Cancelar / Fechar", fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
fun OsdOverlay(uiState: PlayerUiState) {
    val currentTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm:ss"))
    Box(
        modifier = Modifier
            .fillMaxSize(),
        contentAlignment = Alignment.BottomCenter
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0xCC111111))
                .padding(horizontal = 24.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "${uiState.playerName} | Servidor: ${uiState.serverUrl}",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = "Tempo: ${uiState.remainingSeconds}s",
                color = Color(0xFF64B5F6),
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
            Text(
                text = currentTime,
                color = Color(0xFFE0E0E0),
                fontSize = 13.sp
            )
        }
    }
}

