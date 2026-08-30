package com.digitalsignage.player.core.cache

import android.content.Context
import com.digitalsignage.player.data.remote.SignageApiService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.ResponseBody
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest

object MD5Utils {
    fun calculateMD5(file: File): String? {
        if (!file.exists() || !file.isFile) return null
        return try {
            val digest = MessageDigest.getInstance("MD5")
            val buffer = ByteArray(8192)
            FileInputStream(file).use { fis ->
                var bytesRead: Int
                while (fis.read(buffer).also { bytesRead = it } != -1) {
                    digest.update(buffer, 0, bytesRead)
                }
            }
            val md5Bytes = digest.digest()
            val sb = StringBuilder()
            for (b in md5Bytes) {
                sb.append(String.format("%02x", b))
            }
            sb.toString().lowercase()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    fun verifyChecksum(file: File, expectedMd5: String): Boolean {
        val calculated = calculateMD5(file) ?: return false
        return calculated.equals(expectedMd5, ignoreCase = true)
    }
}

class MediaCacheManager(private val context: Context) {
    val cacheDir: File by lazy {
        val dir = File(context.filesDir, "media_cache")
        if (!dir.exists()) dir.mkdirs()
        dir
    }

    fun getLocalMediaFile(hashMd5: String, filename: String): File {
        val extension = filename.substringAfterLast('.', "")
        val targetName = if (extension.isNotEmpty()) "$hashMd5.$extension" else hashMd5
        return File(cacheDir, targetName)
    }

    fun isMediaCachedAndValid(hashMd5: String, filename: String): Boolean {
        val file = getLocalMediaFile(hashMd5, filename)
        if (!file.exists() || file.length() == 0L) return false
        return MD5Utils.verifyChecksum(file, hashMd5)
    }

    fun normalizeDownloadUrl(rawUrl: String, serverBaseUrl: String): String {
        val base = if (serverBaseUrl.endsWith("/")) serverBaseUrl.dropLast(1) else serverBaseUrl
        if (rawUrl.startsWith("/")) {
            return "$base$rawUrl"
        }
        if (!rawUrl.startsWith("http://") && !rawUrl.startsWith("https://")) {
            return "$base/$rawUrl"
        }
        try {
            val uri = java.net.URI(rawUrl)
            val path = uri.path
            val host = uri.host ?: ""
            if (host == "127.0.0.1" || host == "localhost" || host == "10.0.2.2" || host == "cms.signage.corp") {
                return "$base$path"
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return rawUrl
    }

    suspend fun downloadMediaFile(
        apiService: SignageApiService,
        downloadUrl: String,
        hashMd5: String,
        filename: String,
        serverBaseUrl: String = "",
        onProgress: ((progressPercent: Int) -> Unit)? = null
    ): Boolean = withContext(Dispatchers.IO) {
        if (isMediaCachedAndValid(hashMd5, filename)) return@withContext true

        val targetFile = getLocalMediaFile(hashMd5, filename)
        val tempFile = File(cacheDir, "${targetFile.name}.part")
        val effectiveUrl = if (serverBaseUrl.isNotBlank()) normalizeDownloadUrl(downloadUrl, serverBaseUrl) else downloadUrl

        try {
            val response = apiService.downloadMediaFile(effectiveUrl)
            if (!response.isSuccessful || response.body() == null) {
                return@withContext false
            }

            val body: ResponseBody = response.body()!!
            val totalBytes = body.contentLength()

            body.byteStream().use { input: InputStream ->
                FileOutputStream(tempFile).use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalRead = 0L

                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalRead += bytesRead
                        if (totalBytes > 0 && onProgress != null) {
                            val percent = ((totalRead * 100) / totalBytes).toInt()
                            onProgress(percent)
                        }
                    }
                    output.flush()
                }
            }

            // Validar MD5 após download completo
            if (MD5Utils.verifyChecksum(tempFile, hashMd5)) {
                if (targetFile.exists()) targetFile.delete()
                tempFile.renameTo(targetFile)
                true
            } else {
                tempFile.delete()
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            if (tempFile.exists()) tempFile.delete()
            false
        }
    }

    fun cleanObsoleteMedia(activeHashes: Set<String>) {
        val files = cacheDir.listFiles() ?: return
        for (file in files) {
            if (file.name.endsWith(".part")) {
                file.delete()
                continue
            }
            val baseName = file.nameWithoutExtension.lowercase()
            if (!activeHashes.contains(baseName)) {
                file.delete()
            }
        }
    }

    fun getFreeSpaceMb(): Long {
        return cacheDir.freeSpace / (1024 * 1024)
    }
}
