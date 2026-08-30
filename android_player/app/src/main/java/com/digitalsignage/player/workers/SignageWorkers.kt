package com.digitalsignage.player.workers

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.digitalsignage.player.core.cache.MediaCacheManager
import com.digitalsignage.player.data.local.AppDatabase
import com.digitalsignage.player.data.local.PlayerPreferences
import com.digitalsignage.player.data.remote.NetworkClient
import com.digitalsignage.player.data.remote.models.HeartbeatRequest
import com.digitalsignage.player.data.remote.models.ProofOfPlayItemDto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class HeartbeatWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val prefs = PlayerPreferences(applicationContext)
        val cacheManager = MediaCacheManager(applicationContext)
        val apiService = NetworkClient.createService(prefs.serverUrl)

        try {
            val req = HeartbeatRequest(
                status = "ONLINE",
                version = "1.0.0",
                freeSpaceMb = cacheManager.getFreeSpaceMb(),
                currentMedia = ""
            )

            val response = apiService.sendHeartbeat(prefs.playerUuid, req)
            if (response.isSuccessful) {
                Result.success()
            } else {
                Result.retry()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            Result.retry()
        }
    }
}

class ProofOfPlaySyncWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val prefs = PlayerPreferences(applicationContext)
        val database = AppDatabase.getDatabase(applicationContext)
        val dao = database.proofOfPlayDao()
        val apiService = NetworkClient.createService(prefs.serverUrl)

        try {
            val pendingLogs = dao.getPendingLogs(50)
            if (pendingLogs.isEmpty()) {
                return@withContext Result.success()
            }

            val dtoList = pendingLogs.map {
                ProofOfPlayItemDto(
                    mediaId = it.mediaId,
                    playlistId = it.playlistId,
                    startTime = it.startTime,
                    endTime = it.endTime,
                    secondsPlayed = it.secondsPlayed,
                    status = it.status,
                    errorMessage = it.errorMessage
                )
            }

            val response = apiService.sendProofOfPlayBatch(prefs.playerUuid, dtoList)
            if (response.isSuccessful) {
                // Remove os registros confirmados do banco local
                dao.deleteLogs(pendingLogs)
                Result.success()
            } else {
                Result.retry()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            Result.retry()
        }
    }
}
