package com.digitalsignage.player.core.player

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import java.io.File

@OptIn(UnstableApi::class)
class ExoPlayerController(private val context: Context) {

    private var exoPlayer: ExoPlayer? = null
    var onMediaEnded: (() -> Unit)? = null
    var onMediaError: ((errorMsg: String) -> Unit)? = null

    fun initializePlayer(): ExoPlayer {
        if (exoPlayer == null) {
            // Força decodificação por hardware com prioridade máxima
            val renderersFactory = DefaultRenderersFactory(context).apply {
                setEnableDecoderFallback(true)
                setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            }

            exoPlayer = ExoPlayer.Builder(context, renderersFactory)
                .build()
                .apply {
                    repeatMode = Player.REPEAT_MODE_OFF
                    playWhenReady = true

                    addListener(object : Player.Listener {
                        override fun onPlaybackStateChanged(playbackState: Int) {
                            when (playbackState) {
                                Player.STATE_ENDED -> {
                                    onMediaEnded?.invoke()
                                }
                                else -> {}
                            }
                        }

                        override fun onPlayerError(error: PlaybackException) {
                            onMediaError?.invoke(error.message ?: "Erro desconhecido na reprodução do vídeo")
                        }
                    })
                }
        }
        return exoPlayer!!
    }

    fun playFile(file: File) {
        val player = exoPlayer ?: initializePlayer()
        if (!file.exists()) {
            onMediaError?.invoke("Arquivo de vídeo não encontrado no cache: ${file.name}")
            return
        }

        val mediaItem = MediaItem.fromUri(Uri.fromFile(file))
        player.setMediaItem(mediaItem)
        player.prepare()
        player.seekTo(0)
        player.play()
    }

    fun stop() {
        exoPlayer?.stop()
        exoPlayer?.clearMediaItems()
    }

    fun pause() {
        exoPlayer?.pause()
    }

    fun resume() {
        exoPlayer?.play()
    }

    fun setVolume(volumeFloat: Float) {
        exoPlayer?.volume = volumeFloat.coerceIn(0f, 1f)
    }

    fun release() {
        exoPlayer?.release()
        exoPlayer = null
    }

    fun getPlayer(): ExoPlayer? = exoPlayer
}
