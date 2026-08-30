package com.digitalsignage.player.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.digitalsignage.player.core.cache.MediaCacheManager
import com.digitalsignage.player.core.engine.MediaSchedulerEngine
import com.digitalsignage.player.core.engine.MediaType
import com.digitalsignage.player.core.engine.ScheduledPlaybackItem
import com.digitalsignage.player.data.local.AppDatabase
import com.digitalsignage.player.data.local.PlayerPreferences
import com.digitalsignage.player.data.local.ProofOfPlayEntity
import com.digitalsignage.player.data.remote.NetworkClient
import com.digitalsignage.player.data.remote.SignageApiService
import com.digitalsignage.player.data.remote.models.RegisterPlayerRequest
import com.digitalsignage.player.data.remote.models.SyncResponse
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

data class PlayerUiState(
    val currentItem: ScheduledPlaybackItem? = null,
    val playbackSessionId: Long = 0L,
    val mediaType: MediaType = MediaType.UNKNOWN,
    val isPlaying: Boolean = false,
    val statusMessage: String = "Iniciando Player...",
    val remainingSeconds: Int = 0,
    val isOsdVisible: Boolean = false,
    val isSettingsOpen: Boolean = false,
    val isSyncing: Boolean = false,
    val testConnectionStatus: String? = null,
    val playerUuid: String = "",
    val playerName: String = "",
    val serverHost: String = "",
    val serverPort: Int = 8080,
    val serverUrl: String = ""
)

class PlayerViewModel(application: Application) : AndroidViewModel(application) {

    private val prefs = PlayerPreferences(application)
    private val database = AppDatabase.getDatabase(application)
    private val proofOfPlayDao = database.proofOfPlayDao()
    private val cacheManager = MediaCacheManager(application)
    private val schedulerEngine = MediaSchedulerEngine(cacheManager)
    private var apiService: SignageApiService = NetworkClient.createService(prefs.serverUrl)

    private val _uiState = MutableStateFlow(
        PlayerUiState(
            playerUuid = prefs.playerUuid,
            playerName = prefs.playerName,
            serverHost = prefs.serverHost,
            serverPort = prefs.serverPort,
            serverUrl = prefs.serverUrl
        )
    )
    val uiState: StateFlow<PlayerUiState> = _uiState.asStateFlow()

    private var tickerJob: Job? = null
    private var currentItemStartTime: LocalDateTime? = null
    private var currentItemSecondsRemaining: Int = 0
    private var sessionCounter: Long = 0L

    init {
        loadCachedSchedule()
        registerAndSync()
        startPlaybackTicker()
    }

    private fun loadCachedSchedule() {
        val cachedJson = prefs.cachedScheduleJson
        if (!cachedJson.isNullOrBlank()) {
            try {
                val syncData = Gson().fromJson(cachedJson, SyncResponse::class.java)
                schedulerEngine.updateSchedule(syncData)
                _uiState.value = _uiState.value.copy(statusMessage = "Grade local carregada do cache")
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    fun openSettings() {
        _uiState.value = _uiState.value.copy(
            isSettingsOpen = true,
            serverHost = prefs.serverHost,
            serverPort = prefs.serverPort,
            playerName = prefs.playerName,
            testConnectionStatus = null
        )
    }

    fun closeSettings() {
        _uiState.value = _uiState.value.copy(
            isSettingsOpen = false,
            testConnectionStatus = null
        )
    }

    fun saveServerConfig(host: String, port: Int, name: String) {
        prefs.serverHost = host
        prefs.serverPort = port
        prefs.playerName = name
        apiService = NetworkClient.createService(prefs.serverUrl)

        _uiState.value = _uiState.value.copy(
            serverHost = prefs.serverHost,
            serverPort = prefs.serverPort,
            serverUrl = prefs.serverUrl,
            playerName = prefs.playerName,
            isSettingsOpen = false,
            statusMessage = "Configurações salvas. Conectando a ${prefs.serverUrl}..."
        )

        registerAndSync()
    }

    fun testConnection(host: String, port: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            _uiState.value = _uiState.value.copy(testConnectionStatus = "TESTING")
            val testUrl = "http://${host.trim()}:$port"
            try {
                val testService = NetworkClient.createService(testUrl)
                val regReq = RegisterPlayerRequest(
                    uuid = prefs.playerUuid,
                    name = prefs.playerName,
                    localIp = "127.0.0.1",
                    macAddress = "00:00:00:00:00:00",
                    os = "Android",
                    version = "1.0.0"
                )
                val resp = testService.registerPlayer(regReq)
                if (resp.isSuccessful) {
                    _uiState.value = _uiState.value.copy(
                        testConnectionStatus = "SUCCESS: Conexão estabelecida com sucesso com $testUrl!"
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        testConnectionStatus = "ERROR: Servidor respondeu com código HTTP ${resp.code()} (${resp.message()})"
                    )
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    testConnectionStatus = "ERROR: Falha ao conectar em $testUrl: ${e.localizedMessage ?: e.message}"
                )
            }
        }
    }

    fun registerAndSync() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                _uiState.value = _uiState.value.copy(
                    isSyncing = true,
                    statusMessage = "Conectando ao servidor em ${prefs.serverUrl}..."
                )

                // 1. Auto-registro
                val regReq = RegisterPlayerRequest(
                    uuid = prefs.playerUuid,
                    name = prefs.playerName,
                    localIp = "127.0.0.1",
                    macAddress = "00:00:00:00:00:00",
                    os = "Android",
                    version = "1.0.0"
                )
                apiService.registerPlayer(regReq)

                // 2. Sincronização de Grade
                val response = apiService.fetchSyncSchedule(prefs.playerUuid)
                if (response.isSuccessful && response.body() != null) {
                    val syncResponse = response.body()!!
                    val jsonStr = Gson().toJson(syncResponse)
                    prefs.cachedScheduleJson = jsonStr
                    schedulerEngine.updateSchedule(syncResponse)

                    val reqMedias = syncResponse.requiredMedias ?: emptyList()
                    if (reqMedias.isEmpty()) {
                        _uiState.value = _uiState.value.copy(
                            isSyncing = false,
                            statusMessage = "Grade sincronizada (Nenhuma mídia pendente)"
                        )
                    } else {
                        _uiState.value = _uiState.value.copy(
                            statusMessage = "Grade sincronizada. Verificando ${reqMedias.size} mídias..."
                        )

                        // 3. Download prévio de todas as mídias necessárias
                        var dlIndex = 0
                        reqMedias.forEach { reqMedia ->
                            dlIndex++
                            if (!cacheManager.isMediaCachedAndValid(reqMedia.hashMd5, reqMedia.filename)) {
                                _uiState.value = _uiState.value.copy(
                                    statusMessage = "Baixando mídia ($dlIndex/${reqMedias.size}): ${reqMedia.filename}"
                                )
                                cacheManager.downloadMediaFile(
                                    apiService = apiService,
                                    downloadUrl = reqMedia.downloadUrl,
                                    hashMd5 = reqMedia.hashMd5,
                                    filename = reqMedia.filename,
                                    serverBaseUrl = prefs.serverUrl,
                                    onProgress = { pct ->
                                        _uiState.value = _uiState.value.copy(
                                            statusMessage = "Baixando ($dlIndex/${reqMedias.size}): ${reqMedia.filename} ($pct%)"
                                        )
                                    }
                                )
                            }
                        }

                        // 4. Limpeza de mídias obsoletas
                        cacheManager.cleanObsoleteMedia(schedulerEngine.getAllRequiredHashes())

                        _uiState.value = _uiState.value.copy(
                            isSyncing = false,
                            statusMessage = "Mídias sincronizadas com sucesso"
                        )
                    }

                    // Tenta iniciar a reprodução imediatamente
                    launch(Dispatchers.Main) {
                        advanceToNextMediaItem()
                    }
                } else {
                    _uiState.value = _uiState.value.copy(
                        isSyncing = false,
                        statusMessage = "Servidor retornou erro HTTP ${response.code()}"
                    )
                }
            } catch (e: Exception) {
                e.printStackTrace()
                _uiState.value = _uiState.value.copy(
                    isSyncing = false,
                    statusMessage = "Não foi possível conectar em ${prefs.serverUrl}. Verifique o IP e Porta."
                )
            }
        }
    }

    private fun startPlaybackTicker() {
        tickerJob?.cancel()
        tickerJob = viewModelScope.launch(Dispatchers.Main) {
            while (isActive) {
                val current = _uiState.value.currentItem

                if (current == null || currentItemSecondsRemaining <= 0) {
                    advanceToNextMediaItem()
                } else {
                    currentItemSecondsRemaining--
                    _uiState.value = _uiState.value.copy(
                        remainingSeconds = currentItemSecondsRemaining
                    )
                }

                delay(1000)
            }
        }
    }

    fun onVideoPlaybackCompleted() {
        advanceToNextMediaItem()
    }

    private fun advanceToNextMediaItem() {
        val previousItem = _uiState.value.currentItem
        val previousStart = currentItemStartTime

        // Registrar Proof-of-Play da mídia anterior
        if (previousItem != null && previousStart != null) {
            val now = LocalDateTime.now()
            val playedSeconds = previousItem.durationSec - currentItemSecondsRemaining.coerceAtLeast(0)
            logProofOfPlay(previousItem, previousStart, now, playedSeconds, "COMPLETED")
        }

        // Avaliar próximo item no Scheduler Engine
        val nextItem = schedulerEngine.advanceToNextItem()
        if (nextItem != null && nextItem.localFile.exists()) {
            currentItemStartTime = LocalDateTime.now()
            currentItemSecondsRemaining = nextItem.durationSec
            sessionCounter++

            _uiState.value = _uiState.value.copy(
                currentItem = nextItem,
                playbackSessionId = sessionCounter,
                mediaType = nextItem.type,
                isPlaying = true,
                remainingSeconds = nextItem.durationSec
            )
        } else {
            val currentMsg = _uiState.value.statusMessage
            val fallbackMsg = if (schedulerEngine.getAllRequiredHashes().isEmpty()) {
                "Nenhuma grade de exibição ativa no servidor."
            } else {
                "Aguardando download de mídias..."
            }

            // Não substitui mensagens de download ou erro em andamento
            val newStatus = if (_uiState.value.isSyncing || currentMsg.startsWith("Baixando") || currentMsg.startsWith("Não foi possível")) {
                currentMsg
            } else {
                fallbackMsg
            }

            _uiState.value = _uiState.value.copy(
                currentItem = null,
                mediaType = MediaType.UNKNOWN,
                isPlaying = false,
                statusMessage = newStatus
            )
        }
    }

    private fun logProofOfPlay(
        item: ScheduledPlaybackItem,
        startedAt: LocalDateTime,
        endedAt: LocalDateTime,
        durationSec: Int,
        status: String
    ) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")
                val entity = ProofOfPlayEntity(
                    mediaId = item.mediaId,
                    playlistId = item.playlistId,
                    startTime = startedAt.format(fmt),
                    endTime = endedAt.format(fmt),
                    secondsPlayed = durationSec,
                    status = status,
                    errorMessage = ""
                )
                proofOfPlayDao.insertLog(entity)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    fun toggleOsd() {
        _uiState.value = _uiState.value.copy(
            isOsdVisible = !_uiState.value.isOsdVisible
        )
    }

    fun getAdminPassword(): String = prefs.adminPassword
}
