package com.digitalsignage.player.data.local

import android.content.Context
import android.content.SharedPreferences
import java.util.UUID

class PlayerPreferences(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("player_prefs", Context.MODE_PRIVATE)

    companion object {
        private const val KEY_UUID = "player_uuid"
        private const val KEY_SERVER_URL = "server_url"
        private const val KEY_SERVER_HOST = "server_host"
        private const val KEY_SERVER_PORT = "server_port"
        private const val KEY_PLAYER_NAME = "player_name"
        private const val KEY_CACHED_SCHEDULE = "cached_schedule_json"
        private const val KEY_ADMIN_PASSWORD = "admin_password"

        const val DEFAULT_HOST = "192.168.15.119"
        const val DEFAULT_PORT = 8080
    }

    var playerUuid: String
        get() {
            var id = prefs.getString(KEY_UUID, null)
            if (id.isNullOrBlank()) {
                id = UUID.randomUUID().toString()
                prefs.edit().putString(KEY_UUID, id).apply()
            }
            return id
        }
        set(value) = prefs.edit().putString(KEY_UUID, value).apply()

    var serverHost: String
        get() {
            val host = prefs.getString(KEY_SERVER_HOST, null)
            if (!host.isNullOrBlank()) return host

            // Fallback para extrair do serverUrl se existir
            val url = prefs.getString(KEY_SERVER_URL, null)
            if (!url.isNullOrBlank()) {
                return try {
                    val clean = url.removePrefix("http://").removePrefix("https://").substringBefore("/")
                    val h = clean.substringBefore(":")
                    if (h.isNotEmpty() && h != "10.0.2.2") h else DEFAULT_HOST
                } catch (e: Exception) {
                    DEFAULT_HOST
                }
            }
            return DEFAULT_HOST
        }
        set(value) {
            prefs.edit().putString(KEY_SERVER_HOST, value.trim()).apply()
            updateServerUrl()
        }

    var serverPort: Int
        get() {
            val port = prefs.getInt(KEY_SERVER_PORT, 0)
            if (port in 1..65535) return port

            // Fallback para extrair do serverUrl se existir
            val url = prefs.getString(KEY_SERVER_URL, null)
            if (!url.isNullOrBlank()) {
                return try {
                    val clean = url.removePrefix("http://").removePrefix("https://").substringBefore("/")
                    if (clean.contains(":")) clean.substringAfter(":").toIntOrNull() ?: DEFAULT_PORT else DEFAULT_PORT
                } catch (e: Exception) {
                    DEFAULT_PORT
                }
            }
            return DEFAULT_PORT
        }
        set(value) {
            prefs.edit().putInt(KEY_SERVER_PORT, value).apply()
            updateServerUrl()
        }

    var serverUrl: String
        get() {
            val host = serverHost
            val port = serverPort
            return "http://$host:$port"
        }
        set(value) {
            try {
                var clean = value.trim()
                if (clean.endsWith("/")) clean = clean.dropLast(1)
                val withoutScheme = clean.removePrefix("http://").removePrefix("https://").substringBefore("/")
                val hostPart = withoutScheme.substringBefore(":")
                val portPart = if (withoutScheme.contains(":")) withoutScheme.substringAfter(":").toIntOrNull() ?: DEFAULT_PORT else DEFAULT_PORT

                prefs.edit()
                    .putString(KEY_SERVER_HOST, hostPart)
                    .putInt(KEY_SERVER_PORT, portPart)
                    .putString(KEY_SERVER_URL, "http://$hostPart:$portPart")
                    .apply()
            } catch (e: Exception) {
                prefs.edit().putString(KEY_SERVER_URL, value).apply()
            }
        }

    private fun updateServerUrl() {
        val url = "http://$serverHost:$serverPort"
        prefs.edit().putString(KEY_SERVER_URL, url).apply()
    }

    var playerName: String
        get() = prefs.getString(KEY_PLAYER_NAME, "Android TV Display 01") ?: "Android TV Display 01"
        set(value) = prefs.edit().putString(KEY_PLAYER_NAME, value).apply()

    var cachedScheduleJson: String?
        get() = prefs.getString(KEY_CACHED_SCHEDULE, null)
        set(value) = prefs.edit().putString(KEY_CACHED_SCHEDULE, value).apply()

    var adminPassword: String
        get() = prefs.getString(KEY_ADMIN_PASSWORD, "admin123") ?: "admin123"
        set(value) = prefs.edit().putString(KEY_ADMIN_PASSWORD, value).apply()
}
