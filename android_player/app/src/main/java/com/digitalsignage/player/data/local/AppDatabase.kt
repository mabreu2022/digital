package com.digitalsignage.player.data.local

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import android.content.Context

@Entity(tableName = "proof_of_play_logs")
data class ProofOfPlayEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val mediaId: Long,
    val playlistId: Long,
    val startTime: String,
    val endTime: String,
    val secondsPlayed: Int,
    val status: String,
    val errorMessage: String,
    val createdAtTimestamp: Long = System.currentTimeMillis()
)

@Dao
interface ProofOfPlayDao {
    @Insert
    suspend fun insertLog(log: ProofOfPlayEntity): Long

    @Query("SELECT * FROM proof_of_play_logs ORDER BY id ASC LIMIT :limit")
    suspend fun getPendingLogs(limit: Int = 50): List<ProofOfPlayEntity>

    @Delete
    suspend fun deleteLogs(logs: List<ProofOfPlayEntity>)

    @Query("SELECT COUNT(*) FROM proof_of_play_logs")
    suspend fun getCount(): Int
}

@Database(entities = [ProofOfPlayEntity::class], version = 1, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun proofOfPlayDao(): ProofOfPlayDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getDatabase(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "digital_signage_local.db"
                ).fallbackToDestructiveMigration().build()
                INSTANCE = instance
                instance
            }
        }
    }
}
