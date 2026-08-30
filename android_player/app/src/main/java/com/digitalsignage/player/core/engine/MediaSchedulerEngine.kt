package com.digitalsignage.player.core.engine

import com.digitalsignage.player.core.cache.MediaCacheManager
import com.digitalsignage.player.data.remote.models.PlaylistItemDto
import com.digitalsignage.player.data.remote.models.PlaylistDto
import com.digitalsignage.player.data.remote.models.ScheduleRuleDto
import com.digitalsignage.player.data.remote.models.SyncResponse
import java.io.File
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter

enum class MediaType {
    VIDEO,
    IMAGE,
    HTML,
    STREAM,
    UNKNOWN
}

data class ScheduledPlaybackItem(
    val mediaId: Long,
    val playlistId: Long,
    val playlistName: String,
    val filename: String,
    val hashMd5: String,
    val type: MediaType,
    val durationSec: Int,
    val localFile: File,
    val isFallback: Boolean,
    val transition: String
)

class MediaSchedulerEngine(
    private val cacheManager: MediaCacheManager
) {
    private var syncData: SyncResponse? = null
    private var currentPlayingIndex: Int = 0
    private var currentItemRemainingSeconds: Int = 0
    private var activePlaybackItem: ScheduledPlaybackItem? = null

    private val dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    private val timeFormatter = DateTimeFormatter.ofPattern("HH:mm:ss")

    fun updateSchedule(newSyncData: SyncResponse) {
        synchronized(this) {
            this.syncData = newSyncData
        }
    }

    /**
     * Avalia a regra ativa e calcula o item exato para o segundo atual
     */
    fun evaluateCurrentSecond(now: LocalDateTime = LocalDateTime.now()): ScheduledPlaybackItem? {
        synchronized(this) {
            val data = syncData ?: return null

            // 1. Identificar o agendamento de MAIOR prioridade ativo no momento
            val bestSchedule = data.schedules
                ?.filter { isScheduleActiveAt(it, now) }
                ?.maxByOrNull { it.priority }

            val targetPlaylist: PlaylistDto?
            val isFallback: Boolean

            if (bestSchedule != null && bestSchedule.playlist.items.isNotEmpty()) {
                targetPlaylist = bestSchedule.playlist
                isFallback = false
            } else {
                targetPlaylist = data.fallbackPlaylist
                isFallback = true
            }

            if (targetPlaylist == null || targetPlaylist.items.isEmpty()) {
                activePlaybackItem = null
                return null
            }

            val items = targetPlaylist.items.sortedBy { it.order }
            val itemIndex = (currentPlayingIndex % items.size).coerceAtLeast(0)
            val currentDto = items[itemIndex]

            val file = cacheManager.getLocalMediaFile(currentDto.hashMd5, currentDto.filename)
            val mediaType = when (currentDto.type.uppercase()) {
                "VIDEO" -> MediaType.VIDEO
                "IMAGE" -> MediaType.IMAGE
                "HTML" -> MediaType.HTML
                "STREAM" -> MediaType.STREAM
                else -> MediaType.UNKNOWN
            }

            val playbackItem = ScheduledPlaybackItem(
                mediaId = currentDto.mediaId,
                playlistId = targetPlaylist.id,
                playlistName = targetPlaylist.name,
                filename = currentDto.filename,
                hashMd5 = currentDto.hashMd5,
                type = mediaType,
                durationSec = currentDto.durationSec,
                localFile = file,
                isFallback = isFallback,
                transition = currentDto.transition ?: "CUT"
            )

            activePlaybackItem = playbackItem
            return playbackItem
        }
    }

    /**
     * Avança para o próximo item da playlist ativa
     */
    fun advanceToNextItem(): ScheduledPlaybackItem? {
        synchronized(this) {
            currentPlayingIndex++
            return evaluateCurrentSecond()
        }
    }

    /**
     * Valida se um agendamento específico é aplicável para a data/hora fornecida
     */
    private fun isScheduleActiveAt(rule: ScheduleRuleDto, now: LocalDateTime): Boolean {
        try {
            val currentDate = now.toLocalDate()
            val currentTime = now.toLocalTime()

            // 1. Validação de Intervalo de Datas
            val startDate = LocalDate.parse(rule.startDate, dateFormatter)
            val endDate = LocalDate.parse(rule.endDate, dateFormatter)
            if (currentDate.isBefore(startDate) || currentDate.isAfter(endDate)) {
                return false
            }

            // 2. Validação de Dia da Semana (Máscara "0111110" -> Dom=0, Seg=1, ..., Sab=6)
            // Java DayOfWeek: 1 (Mon) .. 7 (Sun)
            val mask = rule.daysOfWeek
            if (mask.length == 7) {
                val maskIndex = when (now.dayOfWeek.value) {
                    7 -> 0 // Domingo
                    else -> now.dayOfWeek.value // 1 (Seg) a 6 (Sab)
                }
                if (mask[maskIndex] != '1') {
                    return false
                }
            }

            // 3. Validação de Janela Horária (HH:mm:ss)
            val startTime = LocalTime.parse(rule.startTime, timeFormatter)
            val endTime = LocalTime.parse(rule.endTime, timeFormatter)

            if (!startTime.isAfter(endTime)) {
                // Janela normal no mesmo dia (ex: 08:00 às 18:00)
                if (currentTime.isBefore(startTime) || currentTime.isAfter(endTime)) {
                    return false
                }
            } else {
                // Janela que cruza a meia-noite (ex: 22:00 às 04:00)
                if (currentTime.isBefore(startTime) && currentTime.isAfter(endTime)) {
                    return false
                }
            }

            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    fun getCurrentPlaybackItem(): ScheduledPlaybackItem? = activePlaybackItem

    fun getAllRequiredHashes(): Set<String> {
        val hashes = mutableSetOf<String>()
        syncData?.fallbackPlaylist?.items?.forEach { hashes.add(it.hashMd5.lowercase()) }
        syncData?.schedules?.forEach { schedule ->
            schedule.playlist.items.forEach { hashes.add(it.hashMd5.lowercase()) }
        }
        return hashes
    }
}
