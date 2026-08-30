package com.digitalsignage.player.data.remote.models

import com.google.gson.annotations.SerializedName

/**
 * Modelos de dados serializados para os contratos REST com o Backend Firebird 5.0
 */

data class SyncResponse(
    @SerializedName("status") val status: String,
    @SerializedName("server_time") val serverTime: String?,
    @SerializedName("player_uuid") val playerUuid: String?,
    @SerializedName("player_name") val playerName: String?,
    @SerializedName("volume") val volume: Int?,
    @SerializedName("fallback_playlist") val fallbackPlaylist: PlaylistDto?,
    @SerializedName("schedules") val schedules: List<ScheduleRuleDto>?,
    @SerializedName("required_medias") val requiredMedias: List<RequiredMediaDto>?
)

data class PlaylistDto(
    @SerializedName("id") val id: Long,
    @SerializedName("name") val name: String,
    @SerializedName("is_default") val isDefault: Int,
    @SerializedName("items") val items: List<PlaylistItemDto>
)

data class PlaylistItemDto(
    @SerializedName("item_id") val itemId: Long,
    @SerializedName("media_id") val mediaId: Long,
    @SerializedName("order") val order: Int,
    @SerializedName("duration_sec") val durationSec: Int,
    @SerializedName("transition") val transition: String?,
    @SerializedName("filename") val filename: String,
    @SerializedName("hash_md5") val hashMd5: String,
    @SerializedName("type") val type: String, // VIDEO, IMAGE, HTML, STREAM
    @SerializedName("size_bytes") val sizeBytes: Long,
    @SerializedName("download_url") val downloadUrl: String
)

data class ScheduleRuleDto(
    @SerializedName("id") val id: Long,
    @SerializedName("event_name") val eventName: String,
    @SerializedName("priority") val priority: Int,
    @SerializedName("start_date") val startDate: String, // YYYY-MM-DD
    @SerializedName("end_date") val endDate: String,     // YYYY-MM-DD
    @SerializedName("start_time") val startTime: String, // HH:mm:ss
    @SerializedName("end_time") val endTime: String,     // HH:mm:ss
    @SerializedName("days_of_week") val daysOfWeek: String, // e.g. "0111110" (Dom..Sab)
    @SerializedName("playlist") val playlist: PlaylistDto
)

data class RequiredMediaDto(
    @SerializedName("media_id") val mediaId: Long,
    @SerializedName("filename") val filename: String,
    @SerializedName("hash_md5") val hashMd5: String,
    @SerializedName("size_bytes") val sizeBytes: Long,
    @SerializedName("type") val type: String,
    @SerializedName("download_url") val downloadUrl: String
)

data class RegisterPlayerRequest(
    @SerializedName("uuid") val uuid: String,
    @SerializedName("name") val name: String,
    @SerializedName("local_ip") val localIp: String,
    @SerializedName("mac_address") val macAddress: String,
    @SerializedName("os") val os: String = "Android TV",
    @SerializedName("version") val version: String = "1.0.0",
    @SerializedName("width") val width: Int = 1920,
    @SerializedName("height") val height: Int = 1080
)

data class HeartbeatRequest(
    @SerializedName("status") val status: String = "ONLINE",
    @SerializedName("version") val version: String = "1.0.0",
    @SerializedName("free_space_mb") val freeSpaceMb: Long,
    @SerializedName("current_media") val currentMedia: String
)

data class HeartbeatResponse(
    @SerializedName("status") val status: String,
    @SerializedName("commands") val commands: List<String>?
)

data class ProofOfPlayItemDto(
    @SerializedName("media_id") val mediaId: Long,
    @SerializedName("playlist_id") val playlistId: Long,
    @SerializedName("start_time") val startTime: String,
    @SerializedName("end_time") val endTime: String,
    @SerializedName("seconds_played") val secondsPlayed: Int,
    @SerializedName("status") val status: String = "COMPLETED",
    @SerializedName("error_message") val errorMessage: String = ""
)

data class BaseResponse(
    @SerializedName("status") val status: String,
    @SerializedName("message") val message: String?,
    @SerializedName("records_inserted") val recordsInserted: Int?
)
