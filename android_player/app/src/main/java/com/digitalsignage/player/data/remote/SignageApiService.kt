package com.digitalsignage.player.data.remote

import com.digitalsignage.player.data.remote.models.BaseResponse
import com.digitalsignage.player.data.remote.models.HeartbeatRequest
import com.digitalsignage.player.data.remote.models.HeartbeatResponse
import com.digitalsignage.player.data.remote.models.ProofOfPlayItemDto
import com.digitalsignage.player.data.remote.models.RegisterPlayerRequest
import com.digitalsignage.player.data.remote.models.SyncResponse
import okhttp3.OkHttpClient
import okhttp3.ResponseBody
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Streaming
import retrofit2.http.Url
import java.util.concurrent.TimeUnit

interface SignageApiService {

    @POST("api/v1/players/register")
    suspend fun registerPlayer(@Body request: RegisterPlayerRequest): Response<BaseResponse>

    @GET("api/v1/players/{uuid}/sync")
    suspend fun fetchSyncSchedule(@Path("uuid") playerUuid: String): Response<SyncResponse>

    @POST("api/v1/players/{uuid}/heartbeat")
    suspend fun sendHeartbeat(
        @Path("uuid") playerUuid: String,
        @Body request: HeartbeatRequest
    ): Response<HeartbeatResponse>

    @POST("api/v1/players/{uuid}/proof-of-play")
    suspend fun sendProofOfPlayBatch(
        @Path("uuid") playerUuid: String,
        @Body items: List<ProofOfPlayItemDto>
    ): Response<BaseResponse>

    @Streaming
    @GET
    suspend fun downloadMediaFile(@Url fileUrl: String): Response<ResponseBody>
}

object NetworkClient {
    private const val DEFAULT_BASE_URL = "http://10.0.2.2:8080/" // Ajustável para o IP real do servidor

    fun createService(baseUrl: String = DEFAULT_BASE_URL): SignageApiService {
        val logging = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }

        val okHttpClient = OkHttpClient.Builder()
            .addInterceptor(logging)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()

        val normalizedUrl = if (baseUrl.endsWith("/")) baseUrl else "$baseUrl/"

        return Retrofit.Builder()
            .baseUrl(normalizedUrl)
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(SignageApiService::class.java)
    }
}
