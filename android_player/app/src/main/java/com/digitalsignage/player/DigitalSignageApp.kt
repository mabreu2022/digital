package com.digitalsignage.player

import android.app.Application
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.digitalsignage.player.workers.HeartbeatWorker
import com.digitalsignage.player.workers.ProofOfPlaySyncWorker
import java.util.concurrent.TimeUnit

class DigitalSignageApp : Application() {

    override fun onCreate() {
        super.onCreate()
        scheduleBackgroundTasks()
    }

    private fun scheduleBackgroundTasks() {
        val workManager = WorkManager.getInstance(this)

        // 1. Heartbeat Periódico (A cada 15 minutos em background via WorkManager)
        val heartbeatRequest = PeriodicWorkRequestBuilder<HeartbeatWorker>(
            15, TimeUnit.MINUTES
        ).build()

        workManager.enqueueUniquePeriodicWork(
            "HeartbeatWork",
            ExistingPeriodicWorkPolicy.KEEP,
            heartbeatRequest
        )

        // 2. Envio em Lote de Proof-of-Play
        val popRequest = PeriodicWorkRequestBuilder<ProofOfPlaySyncWorker>(
            15, TimeUnit.MINUTES
        ).build()

        workManager.enqueueUniquePeriodicWork(
            "ProofOfPlayWork",
            ExistingPeriodicWorkPolicy.KEEP,
            popRequest
        )
    }
}
