/**
 * Digital Signage Web Player Engine
 * Compatível com Smart TVs (Samsung Tizen, LG webOS), Kiosks, Chrome, Firefox, Safari
 */

(function () {
  'use strict';

  // Configuração & Estado
  const CONFIG = {
    storageKeyUuid: 'digitalsign_web_uuid',
    storageKeyName: 'digitalsign_web_name',
    defaultServerPort: 8080,
    syncIntervalMs: 60 * 1000,      // Sincroniza grade a cada 60s
    heartbeatIntervalMs: 20 * 1000, // Heartbeat a cada 20s
    osdHideTimeoutMs: 4000          // Esconde OSD após 4s de inatividade
  };

  class WebSignagePlayer {
    constructor() {
      this.uuid = this.getOrCreateUuid();
      this.name = this.getStoredName();
      this.serverBaseUrl = window.location.origin;
      this.syncData = null;
      this.currentPlaylist = null;
      this.currentIndex = 0;
      this.activeItem = null;
      this.itemStartTime = null;
      this.timerTicker = null;
      this.remainingSeconds = 0;
      this.isSyncing = false;
      this.isOnline = false;
      this.mouseIdleTimer = null;

      // Elementos DOM
      this.dom = {
        app: document.getElementById('app'),
        videoA: document.getElementById('videoLayerA'),
        videoB: document.getElementById('videoLayerB'),
        imgA: document.getElementById('imageLayerA'),
        imgB: document.getElementById('imageLayerB'),
        youtubeLayer: document.getElementById('youtubeLayer'),
        idleScreen: document.getElementById('idleScreen'),
        idleStatus: document.getElementById('idleStatus'),
        idleName: document.getElementById('idlePlayerName'),
        idleRes: document.getElementById('idleResolution'),
        osd: document.getElementById('osdHud'),
        osdDot: document.getElementById('statusDot'),
        osdClock: document.getElementById('osdClock'),
        osdLabel: document.getElementById('osdLabel'),
        floatingControls: document.getElementById('floatingControls'),
        settingsModal: document.getElementById('settingsModal'),
        inputName: document.getElementById('inputPlayerName'),
        inputUuid: document.getElementById('inputPlayerUuid'),
        btnSaveSettings: document.getElementById('btnSaveSettings'),
        btnCloseSettings: document.getElementById('btnCloseSettings'),
        btnOpenSettings: document.getElementById('btnOpenSettings'),
        btnFullscreen: document.getElementById('btnFullscreen'),
        btnForceSync: document.getElementById('btnForceSync')
      };

      this.activeVideo = this.dom.videoA;
      this.nextVideo = this.dom.videoB;
      this.activeImg = this.dom.imgA;
      this.nextImg = this.dom.imgB;

      this.init();
    }

    getOrCreateUuid() {
      const urlParams = new URLSearchParams(window.location.search);
      const queryUuid = urlParams.get('uuid');
      if (queryUuid && queryUuid.length <= 36) {
        localStorage.setItem(CONFIG.storageKeyUuid, queryUuid);
        return queryUuid;
      }

      let stored = localStorage.getItem(CONFIG.storageKeyUuid);
      // Se for nulo ou diferente de 36 caracteres, regenera no padrão UUID v4 de 36 caracteres
      if (!stored || stored.length !== 36) {
        stored = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
          const r = Math.random() * 16 | 0;
          const v = c === 'x' ? r : (r & 0x3 | 0x8);
          return v.toString(16);
        });
        localStorage.setItem(CONFIG.storageKeyUuid, stored);
      }
      return stored;
    }

    getStoredName() {
      const urlParams = new URLSearchParams(window.location.search);
      const queryName = urlParams.get('name');
      if (queryName) {
        localStorage.setItem(CONFIG.storageKeyName, queryName);
        return queryName;
      }
      return localStorage.getItem(CONFIG.storageKeyName) || ('Web Player ' + window.location.hostname);
    }

    init() {
      this.setupEventListeners();
      this.startClock();
      this.updateIdleMeta();

      // Registro inicial e sincronização
      this.registerPlayer().then(() => {
        this.fetchSync();
      });

      // Timers em segundo plano
      setInterval(() => this.fetchSync(), CONFIG.syncIntervalMs);
      setInterval(() => this.sendHeartbeat(), CONFIG.heartbeatIntervalMs);
    }

    setupEventListeners() {
      // Eventos de fim de vídeo
      [this.dom.videoA, this.dom.videoB].forEach(v => {
        v.addEventListener('ended', () => this.onMediaEnded());
        v.addEventListener('error', (e) => {
          console.warn('[WebPlayer] Erro no elemento de vídeo:', e);
          setTimeout(() => this.onMediaEnded(), 1000);
        });
      });

      // Mouse e interação na tela
      window.addEventListener('mousemove', () => this.showHudTemporarily());
      window.addEventListener('touchstart', () => this.showHudTemporarily());
      window.addEventListener('dblclick', () => this.toggleFullscreen());

      // Teclas de atalho (F = Tela Cheia, S/M = Configurações, R = Sincronizar)
      window.addEventListener('keydown', (e) => {
        if (e.key === 'f' || e.key === 'F') {
          this.toggleFullscreen();
        } else if (e.key === 's' || e.key === 'S' || e.key === 'm' || e.key === 'M') {
          this.openSettings();
        } else if (e.key === 'r' || e.key === 'R') {
          this.fetchSync(true);
        } else if (e.key === 'Escape') {
          this.closeSettings();
        }
      });

      // Botões da interface
      if (this.dom.btnFullscreen) {
        this.dom.btnFullscreen.addEventListener('click', () => this.toggleFullscreen());
      }
      if (this.dom.btnOpenSettings) {
        this.dom.btnOpenSettings.addEventListener('click', () => this.openSettings());
      }
      if (this.dom.btnCloseSettings) {
        this.dom.btnCloseSettings.addEventListener('click', () => this.closeSettings());
      }
      if (this.dom.btnSaveSettings) {
        this.dom.btnSaveSettings.addEventListener('click', () => this.saveSettings());
      }
      if (this.dom.btnForceSync) {
        this.dom.btnForceSync.addEventListener('click', () => this.fetchSync(true));
      }
    }

    updateIdleMeta() {
      if (this.dom.idleName) this.dom.idleName.textContent = `🖥️ ${this.name}`;
      if (this.dom.idleRes) this.dom.idleRes.textContent = `📐 ${window.screen.width}x${window.screen.height}`;
      if (this.dom.inputName) this.dom.inputName.value = this.name;
      if (this.dom.inputUuid) this.dom.inputUuid.value = this.uuid;
    }

    startClock() {
      const updateClock = () => {
        const now = new Date();
        const hrs = String(now.getHours()).padStart(2, '0');
        const mins = String(now.getMinutes()).padStart(2, '0');
        const secs = String(now.getSeconds()).padStart(2, '0');
        if (this.dom.osdClock) {
          this.dom.osdClock.textContent = `${hrs}:${mins}:${secs}`;
        }
      };
      updateClock();
      setInterval(updateClock, 1000);
    }

    showHudTemporarily() {
      this.dom.app.classList.add('show-cursor');
      this.dom.osd.classList.add('visible');
      this.dom.floatingControls.classList.add('visible');

      clearTimeout(this.mouseIdleTimer);
      this.mouseIdleTimer = setTimeout(() => {
        this.dom.app.classList.remove('show-cursor');
        this.dom.osd.classList.remove('visible');
        this.dom.floatingControls.classList.remove('visible');
      }, CONFIG.osdHideTimeoutMs);
    }

    // Auto-registro da tela no Servidor CMS
    async registerPlayer() {
      try {
        const payload = {
          uuid: this.uuid,
          name: this.name,
          local_ip: window.location.hostname || '127.0.0.1',
          mac_address: '00:00:00:00:00:00',
          os: 'WebBrowser (' + this.detectBrowser() + ')',
          version: '1.0.0 (Web)'
        };

        const res = await fetch(`${this.serverBaseUrl}/api/v1/players/register`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        if (res.ok) {
          this.isOnline = true;
          this.updateConnectionDot('online');
        }
      } catch (err) {
        console.warn('[WebPlayer] Falha ao registrar tela:', err);
        this.isOnline = false;
        this.updateConnectionDot('offline');
      }
    }

    detectBrowser() {
      const ua = navigator.userAgent;
      if (/Tizen/i.test(ua)) return 'Samsung Tizen';
      if (/Web0S|webOS/i.test(ua)) return 'LG webOS';
      if (/Android/i.test(ua)) return 'Android TV / Chrome';
      if (/iPhone|iPad/i.test(ua)) return 'Apple Safari';
      if (/Chrome/i.test(ua)) return 'Chrome';
      if (/Firefox/i.test(ua)) return 'Firefox';
      return 'Modern Browser';
    }

    // Sincronização de Grade com o Servidor
    async fetchSync(showFeedback = false) {
      if (this.isSyncing) return;
      this.isSyncing = true;
      this.updateConnectionDot('syncing');

      try {
        const res = await fetch(`${this.serverBaseUrl}/api/v1/players/${this.uuid}/sync`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);

        const data = await res.json();
        this.syncData = data;
        this.isOnline = true;
        this.updateConnectionDot('online');

        if (this.dom.idleStatus) {
          this.dom.idleStatus.textContent = 'Grade sincronizada com sucesso.';
        }

        // Se nada estiver tocando no momento, inicia o loop
        if (!this.activeItem) {
          this.evaluateScheduleAndAdvance();
        }

        if (showFeedback) {
          alert('Grade sincronizada com o Servidor com sucesso!');
        }
      } catch (err) {
        console.warn('[WebPlayer] Erro na sincronização:', err);
        this.isOnline = false;
        this.updateConnectionDot('offline');
        if (this.dom.idleStatus) {
          this.dom.idleStatus.textContent = 'Aguardando conexão com o Servidor CMS...';
        }
      } finally {
        this.isSyncing = false;
      }
    }

    // Heartbeat para o Servidor mostrar a tela ONLINE
    async sendHeartbeat() {
      try {
        const payload = {
          current_media_id: this.activeItem ? this.activeItem.mediaId : null,
          is_playing: !!this.activeItem,
          uptime_seconds: Math.floor(performance.now() / 1000)
        };

        const res = await fetch(`${this.serverBaseUrl}/api/v1/players/${this.uuid}/heartbeat`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        if (res.ok) {
          this.isOnline = true;
          this.updateConnectionDot('online');
        }
      } catch (err) {
        this.isOnline = false;
        this.updateConnectionDot('offline');
      }
    }

    // Avalia agendamentos ativos ou usa a playlist fallback
    evaluateScheduleAndAdvance() {
      if (!this.syncData) return;

      const now = new Date();
      let targetPlaylist = null;
      let isFallback = true;

      // 1. Verificar agendamentos ativos
      if (this.syncData.schedules && this.syncData.schedules.length > 0) {
        const activeRules = this.syncData.schedules.filter(rule => this.isRuleActive(rule, now));
        if (activeRules.length > 0) {
          // Escolher maior prioridade
          activeRules.sort((a, b) => (b.priority || 0) - (a.priority || 0));
          const best = activeRules[0];
          if (best.playlist && best.playlist.items && best.playlist.items.length > 0) {
            targetPlaylist = best.playlist;
            isFallback = false;
          }
        }
      }

      // 2. Se nenhum agendamento bateu, usa playlist padrão de Fallback
      if (!targetPlaylist && this.syncData.fallback_playlist && this.syncData.fallback_playlist.items) {
        targetPlaylist = this.syncData.fallback_playlist;
        isFallback = true;
      }

      if (!targetPlaylist || targetPlaylist.items.length === 0) {
        this.showIdleScreen('Nenhuma mídia configurada na playlist ativa.');
        return;
      }

      // Se trocou de playlist, reseta o índice
      if (!this.currentPlaylist || this.currentPlaylist.id !== targetPlaylist.id) {
        this.currentPlaylist = targetPlaylist;
        this.currentIndex = 0;
      }

      const items = [...targetPlaylist.items].sort((a, b) => a.order - b.order);
      const itemIndex = this.currentIndex % items.length;
      const currentDto = items[itemIndex];

      this.currentIndex++;
      this.playItem({
        mediaId: currentDto.media_id,
        playlistId: targetPlaylist.id,
        playlistName: targetPlaylist.name,
        filename: currentDto.filename,
        hashMd5: currentDto.hash_md5,
        type: (currentDto.type || 'IMAGE').toUpperCase(),
        durationSec: currentDto.duration_sec || 10,
        downloadUrl: currentDto.download_url || `/media/${currentDto.filename}`,
        isFallback: isFallback
      });
    }

    isRuleActive(rule, now) {
      try {
        // Validação de Data (AAAA-MM-DD)
        const dateStr = now.toISOString().split('T')[0];
        if (rule.start_date && dateStr < rule.start_date) return false;
        if (rule.end_date && dateStr > rule.end_date) return false;

        // Validação de Dia da Semana (Máscara 7 caracteres: Dom=0, Seg=1... Sab=6)
        if (rule.days_of_week && rule.days_of_week.length === 7) {
          const dayIdx = now.getDay(); // 0 = Domingo, 1 = Segunda ...
          if (rule.days_of_week[dayIdx] !== '1') return false;
        }

        // Validação de Janela de Horário (HH:MM:SS)
        const curTimeStr = String(now.getHours()).padStart(2, '0') + ':' +
                           String(now.getMinutes()).padStart(2, '0') + ':' +
                           String(now.getSeconds()).padStart(2, '0');

        if (rule.start_time && rule.end_time) {
          if (rule.start_time <= rule.end_time) {
            if (curTimeStr < rule.start_time || curTimeStr > rule.end_time) return false;
          } else {
            // Janela cruzando a meia-noite
            if (curTimeStr < rule.start_time && curTimeStr > rule.end_time) return false;
          }
        }

        return true;
      } catch (e) {
        return false;
      }
    }

    extractYouTubeId(url) {
      if (!url) return '';
      const str = url.trim();

      // 1. Caso formato youtube_ID
      if (str.startsWith('youtube_')) {
        return str.substring(8);
      }

      // 2. Caso youtu.be/ID
      if (str.includes('youtu.be/')) {
        const parts = str.split('youtu.be/')[1];
        return parts ? parts.split(/[?&#/]/)[0] : '';
      }

      // 3. Caso /shorts/ID, /embed/ID, /live/ID
      const matchSpecial = str.match(/\/(shorts|embed|live)\/([a-zA-Z0-9_-]{11})/);
      if (matchSpecial && matchSpecial[2]) {
        return matchSpecial[2];
      }

      // 4. Caso padrão v=ID
      const matchV = str.match(/[?&]v=([a-zA-Z0-9_-]{11})/);
      if (matchV && matchV[1]) {
        return matchV[1];
      }

      // 5. Se for o próprio ID de 11 caracteres
      if (str.length === 11 && !str.includes('/') && !str.includes('?')) {
        return str;
      }

      return '';
    }

    playItem(item) {
      this.activeItem = item;
      this.itemStartTime = new Date();
      this.remainingSeconds = item.durationSec;
      this.dom.idleScreen.classList.add('hidden');

      if (this.dom.osdLabel) {
        this.dom.osdLabel.textContent = `${item.playlistName} • ${item.filename}`;
      }

      const isYouTube = item.type === 'STREAM' || item.type === 'YOUTUBE' || 
                        item.filename.startsWith('youtube_') || 
                        item.downloadUrl.includes('youtube') || 
                        item.downloadUrl.includes('youtu.be');

      if (isYouTube) {
        this.playYouTube(item);
      } else if (item.type === 'VIDEO') {
        this.playVideo(item);
      } else {
        this.playImage(item);
      }

      this.startMediaTicker(item);
    }

    playYouTube(item) {
      const videoId = this.extractYouTubeId(item.downloadUrl) || this.extractYouTubeId(item.filename);

      // Ocultar camadas de vídeo local e imagem
      this.dom.videoA.classList.remove('active');
      this.dom.videoB.classList.remove('active');
      this.dom.imgA.classList.remove('active');
      this.dom.imgB.classList.remove('active');
      this.dom.videoA.pause();
      this.dom.videoB.pause();

      if (!videoId) {
        console.warn('[WebPlayer] ID do vídeo do YouTube não identificado:', item);
        setTimeout(() => this.onMediaEnded(), 2000);
        return;
      }

      // Embed limpo do YouTube em tela cheia com autoplay e mudo
      const embedUrl = `https://www.youtube.com/embed/${videoId}?autoplay=1&mute=1&controls=0&loop=1&playlist=${videoId}&enablejsapi=1&rel=0&iv_load_policy=3&modestbranding=1`;
      this.dom.youtubeLayer.src = embedUrl;
      this.dom.youtubeLayer.classList.add('active');
    }

    playVideo(item) {
      const video = this.activeVideo;
      const mediaUrl = item.downloadUrl.startsWith('http') ? item.downloadUrl : (this.serverBaseUrl + item.downloadUrl);

      // Ocultar imagens
      this.dom.imgA.classList.remove('active');
      this.dom.imgB.classList.remove('active');

      video.src = mediaUrl;
      video.muted = true; // Necessário para Autoplay em navegadores modernos
      video.load();

      video.play().then(() => {
        video.classList.add('active');
      }).catch(err => {
        console.warn('[WebPlayer] Autoplay bloqueado ou erro ao tocar vídeo:', err);
        // Fallback: se bloquear autoplay com áudio, tenta mudo ou avança
        video.muted = true;
        video.play().catch(() => setTimeout(() => this.onMediaEnded(), 2000));
      });
    }

    playImage(item) {
      const img = this.activeImg;
      const mediaUrl = item.downloadUrl.startsWith('http') ? item.downloadUrl : (this.serverBaseUrl + item.downloadUrl);

      // Ocultar vídeos
      this.dom.videoA.classList.remove('active');
      this.dom.videoB.classList.remove('active');
      this.dom.videoA.pause();
      this.dom.videoB.pause();

      img.src = mediaUrl;
      img.onload = () => {
        img.classList.add('active');
      };
      img.onerror = () => {
        console.warn('[WebPlayer] Erro ao carregar imagem:', mediaUrl);
        setTimeout(() => this.onMediaEnded(), 2000);
      };
    }

    startMediaTicker(item) {
      clearInterval(this.timerTicker);

      // Para imagens, conta os segundos até avançar.
      // Para vídeos, o evento 'ended' ou o timer máximo avança a mídia.
      this.timerTicker = setInterval(() => {
        this.remainingSeconds--;
        if (this.remainingSeconds <= 0) {
          clearInterval(this.timerTicker);
          this.onMediaEnded();
        }
      }, 1000);
    }

    onMediaEnded() {
      clearInterval(this.timerTicker);

      // Limpar camada do YouTube se ativa
      if (this.dom.youtubeLayer) {
        this.dom.youtubeLayer.classList.remove('active');
        this.dom.youtubeLayer.src = 'about:blank';
      }

      // Log Proof-of-Play
      if (this.activeItem && this.itemStartTime) {
        const playedSecs = Math.max(1, Math.round((new Date() - this.itemStartTime) / 1000));
        this.logProofOfPlay(this.activeItem, this.itemStartTime, new Date(), playedSecs);
      }

      // Avançar para próximo item
      this.evaluateScheduleAndAdvance();
    }

    async logProofOfPlay(item, startedAt, endedAt, playedSecs) {
      try {
        const payload = {
          records: [{
            media_id: item.mediaId,
            playlist_id: item.playlistId,
            start_time: startedAt.toISOString(),
            end_time: endedAt.toISOString(),
            seconds_played: playedSecs,
            status: 'COMPLETED',
            error_message: ''
          }]
        };

        await fetch(`${this.serverBaseUrl}/api/v1/players/${this.uuid}/proof-of-play`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
      } catch (err) {
        // Silencioso em caso de falha de telemetria pontual
      }
    }

    showIdleScreen(msg) {
      this.activeItem = null;
      clearInterval(this.timerTicker);
      this.dom.imgA.classList.remove('active');
      this.dom.imgB.classList.remove('active');
      this.dom.videoA.classList.remove('active');
      this.dom.videoB.classList.remove('active');
      if (this.dom.youtubeLayer) {
        this.dom.youtubeLayer.classList.remove('active');
        this.dom.youtubeLayer.src = 'about:blank';
      }
      this.dom.videoA.pause();
      this.dom.videoB.pause();

      this.dom.idleStatus.textContent = msg;
      this.dom.idleScreen.classList.remove('hidden');
    }

    updateConnectionDot(state) {
      this.dom.osdDot.className = 'status-dot';
      if (state === 'syncing') {
        this.dom.osdDot.classList.add('syncing');
      } else if (state === 'offline') {
        this.dom.osdDot.classList.add('offline');
      }
    }

    // Tela Cheia
    toggleFullscreen() {
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(() => {});
      } else {
        if (document.exitFullscreen) {
          document.exitFullscreen().catch(() => {});
        }
      }
    }

    // Configurações
    openSettings() {
      this.dom.settingsModal.classList.add('open');
      this.dom.inputName.value = this.name;
      this.dom.inputUuid.value = this.uuid;
    }

    closeSettings() {
      this.dom.settingsModal.classList.remove('open');
    }

    saveSettings() {
      const newName = this.dom.inputName.value.trim();
      if (newName) {
        this.name = newName;
        localStorage.setItem(CONFIG.storageKeyName, newName);
      }
      this.closeSettings();
      this.updateIdleMeta();
      this.registerPlayer();
      this.fetchSync(true);
    }
  }

  // Inicializa quando o DOM estiver pronto
  window.addEventListener('DOMContentLoaded', () => {
    window.playerApp = new WebSignagePlayer();
  });
})();
