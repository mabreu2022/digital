/**
 * DIGITAL SIGNAGE WEB CMS - CLIENT APPLICATION ENGINE
 */

const App = {
  activeTab: 'dashboard',
  selectedPlaylistId: null,
  allMedias: [],
  allScreens: [],
  allPlaylists: [],

  init() {
    this.setupNavigation();
    this.setupClock();
    this.setupDropzone();
    this.loadAll();

    // Auto-refresh a cada 10 segundos
    setInterval(() => this.loadAll(false), 10000);
  },

  setupNavigation() {
    document.querySelectorAll('.nav-item').forEach(btn => {
      btn.addEventListener('click', () => {
        const tab = btn.dataset.tab;
        this.switchTab(tab);
      });
    });

    document.getElementById('btnGlobalRefresh').addEventListener('click', () => {
      this.loadAll(true);
      this.showToast('Dados atualizados com sucesso!');
    });
  },

  switchTab(tabName) {
    this.activeTab = tabName;
    document.querySelectorAll('.nav-item').forEach(b => {
      b.classList.toggle('active', b.dataset.tab === tabName);
    });
    document.querySelectorAll('.tab-content').forEach(c => {
      c.classList.toggle('active', c.id === `tab-${tabName}`);
    });

    const titles = {
      dashboard: ['Dashboard Geral', 'Visão geral em tempo real de telas, grades e exibições'],
      telas: ['Telas Players', 'Monitoramento, vinculação e status em tempo real de cada player'],
      midias: ['Catálogo de Mídias', 'Upload de vídeos MP4, imagens e integração com YouTube'],
      playlists: ['Playlists', 'Montagem de listas de reprodução, ordenação e transições'],
      agendamentos: ['Grade de Agendamentos', 'Regras de exibição por tela ou globais com horários'],
      logs: ['Logs & Relatórios', 'Histórico de exibições comprovadas (Proof-of-Play)']
    };

    const [t, sub] = titles[tabName] || ['Painel CMS', ''];
    document.getElementById('pageTitle').textContent = t;
    document.getElementById('pageSubtitle').textContent = sub;
  },

  setupClock() {
    const update = () => {
      const now = new Date();
      const str = now.toLocaleTimeString('pt-BR');
      document.getElementById('serverClock').textContent = str;
    };
    update();
    setInterval(update, 1000);
  },

  setupDropzone() {
    const dropzone = document.getElementById('mediaDropzone');
    if (!dropzone) return;

    ['dragenter', 'dragover'].forEach(name => {
      dropzone.addEventListener(name, (e) => {
        e.preventDefault();
        dropzone.classList.add('dragover');
      });
    });

    ['dragleave', 'drop'].forEach(name => {
      dropzone.addEventListener(name, (e) => {
        e.preventDefault();
        dropzone.classList.remove('dragover');
      });
    });

    dropzone.addEventListener('drop', (e) => {
      const files = e.dataTransfer.files;
      if (files && files.length > 0) {
        this.handleFileUpload(files);
      }
    });

    dropzone.addEventListener('click', () => {
      document.getElementById('fileUploadInput').click();
    });
  },

  async loadAll(showFeedback = false) {
    try {
      await Promise.all([
        this.loadDashboard(),
        this.loadTelas(),
        this.loadMedias(),
        this.loadPlaylists(),
        this.loadSchedules(),
        this.loadLogs()
      ]);
    } catch (e) {
      console.error('Erro ao carregar dados:', e);
    }
  },

  // ========================================================
  // DASHBOARD
  // ========================================================
  async loadDashboard() {
    const res = await fetch('/api/v1/dashboard/stats');
    if (!res.ok) return;
    const data = await res.json();

    document.getElementById('kpiOnlineScreens').textContent = data.online_screens;
    document.getElementById('kpiTotalScreens').textContent = data.total_screens;
    document.getElementById('badgeOnlineCount').textContent = data.online_screens;
    document.getElementById('kpiActivePlaylists').textContent = data.active_playlists;
    document.getElementById('kpiTotalMedias').textContent = data.total_medias;
    document.getElementById('kpiStorageMb').textContent = data.storage_mb;
    document.getElementById('kpiProofToday').textContent = data.proof_today;

    const resLogs = await fetch('/api/v1/dashboard/logs');
    if (resLogs.ok) {
      const logs = await resLogs.json();
      const body = document.getElementById('dashboardProofLogsBody');
      if (logs.length === 0) {
        body.innerHTML = '<tr><td colspan="5" class="text-center text-muted">Nenhuma exibição recente registrada.</td></tr>';
      } else {
        body.innerHTML = logs.slice(0, 5).map(l => `
          <tr>
            <td>${l.DATA_HORA_INICIO ? l.DATA_HORA_INICIO.split('.')[0] : '-'}</td>
            <td><strong>${l.TELA_NOME}</strong></td>
            <td>${l.MIDIA_NOME}</td>
            <td>${l.SEGUNDOS_EXIBIDOS}s</td>
            <td><span class="badge badge-online">OK</span></td>
          </tr>
        `).join('');
      }
    }
  },

  // ========================================================
  // TELAS
  // ========================================================
  async loadTelas() {
    const res = await fetch('/api/v1/screens');
    if (!res.ok) return;
    this.allScreens = await res.json();

    const tbody = document.getElementById('telasTableBody');
    const miniGrid = document.getElementById('dashboardScreensGrid');

    if (this.allScreens.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted">Nenhuma tela conectada até o momento.</td></tr>';
      miniGrid.innerHTML = '<p class="text-muted">Nenhuma tela conectada.</p>';
      return;
    }

    tbody.innerHTML = this.allScreens.map(s => `
      <tr>
        <td>
          <span class="badge ${s.status === 'ONLINE' ? 'badge-online' : 'badge-offline'}">
            ${s.status === 'ONLINE' ? '● ONLINE' : '○ OFFLINE'}
          </span>
        </td>
        <td><strong>${s.NOME}</strong></td>
        <td>${s.IP_LOCAL || '-'}</td>
        <td>${s.IP_PUBLICO || '-'}</td>
        <td>${s.SISTEMA_OPERACIONAL || 'Desconhecido'}</td>
        <td>${s.VERSAO_PLAYER || '1.0.0'}</td>
        <td>${s.ULTIMO_HEARTBEAT ? s.ULTIMO_HEARTBEAT.split('.')[0] : '-'}</td>
        <td>
          <button class="btn btn-sm btn-outline" onclick="App.openScreenPlayer('${encodeURIComponent(s.NOME)}')">Abrir Player</button>
          <button class="btn btn-sm btn-danger-outline" onclick="App.deleteScreen(${s.ID})">Excluir</button>
        </td>
      </tr>
    `).join('');

    miniGrid.innerHTML = this.allScreens.map(s => `
      <div class="screen-mini-card">
        <div class="screen-mini-info">
          <h4>${s.NOME}</h4>
          <span>IP: ${s.IP_LOCAL || '127.0.0.1'} • ${s.SISTEMA_OPERACIONAL || 'Web'}</span>
        </div>
        <span class="badge ${s.status === 'ONLINE' ? 'badge-online' : 'badge-offline'}">
          ${s.status === 'ONLINE' ? '● ONLINE' : '○ OFFLINE'}
        </span>
      </div>
    `).join('');

    // Preenche select do agendamento
    const select = document.getElementById('schedScreenSelect');
    if (select) {
      select.innerHTML = '<option value="">[TODAS AS TELAS - GLOBAL]</option>' + 
        this.allScreens.map(s => `<option value="${s.ID}">${s.NOME} (${s.IP_LOCAL})</option>`).join('');
    }
  },

  async deleteScreen(id) {
    if (!confirm('Deseja realmente excluir esta tela?')) return;
    const res = await fetch(`/api/v1/screens/${id}`, { method: 'DELETE' });
    if (res.ok) {
      this.showToast('Tela excluída com sucesso');
      this.loadTelas();
      this.loadDashboard();
    }
  },

  openScreenPlayer(screenName) {
    window.open(`/player?name=${screenName}`, '_blank');
  },

  openWebPlayerDirect() {
    window.open('/player', '_blank');
  },

  // ========================================================
  // MÍDIAS
  // ========================================================
  async loadMedias() {
    const res = await fetch('/api/v1/medias');
    if (!res.ok) return;
    this.allMedias = await res.json();

    const grid = document.getElementById('mediasGrid');
    if (this.allMedias.length === 0) {
      grid.innerHTML = '<p class="text-muted" style="grid-column: 1/-1;">Nenhuma mídia cadastrada. Faça upload de um vídeo ou adicione um link do YouTube.</p>';
      return;
    }

    grid.innerHTML = this.allMedias.map(m => {
      const isVideo = m.TIPO_MIDIA === 'VIDEO';
      const isStream = m.TIPO_MIDIA === 'STREAM' || m.URL_DOWNLOAD.includes('youtube');
      
      let thumbHtml = '';
      if (isStream) {
        let ytId = m.NOME_ARQUIVO.replace('youtube_', '');
        thumbHtml = `<img src="https://img.youtube.com/vi/${ytId}/hqdefault.jpg" class="media-thumbnail-img" alt="${m.NOME_EXIBICAO}">`;
      } else if (isVideo) {
        thumbHtml = `<div class="media-thumbnail-placeholder">🎬</div>`;
      } else {
        thumbHtml = `<img src="${m.URL_DOWNLOAD}" class="media-thumbnail-img" alt="${m.NOME_EXIBICAO}">`;
      }

      return `
        <div class="media-card">
          <div class="media-thumbnail-wrapper" onclick="App.previewMedia(${m.ID})">
            ${thumbHtml}
            <span class="media-duration-badge">${m.DURACAO_PADRAO_SEG > 0 ? m.DURACAO_PADRAO_SEG + 's' : 'Ao vivo'}</span>
          </div>
          <div class="media-card-body">
            <h4 class="media-card-title" title="${m.NOME_EXIBICAO}">${m.NOME_EXIBICAO}</h4>
            <div class="media-card-meta">
              <span class="badge badge-type">${m.TIPO_MIDIA}</span>
              <button class="btn-sm btn-danger-outline" onclick="App.deleteMedia(${m.ID})">🗑️</button>
            </div>
          </div>
        </div>
      `;
    }).join('');

    // Preenche select do modal de playlist
    const select = document.getElementById('selectMediaForPl');
    if (select) {
      select.innerHTML = this.allMedias.map(m => `
        <option value="${m.ID}" data-duration="${m.DURACAO_PADRAO_SEG}">
          ${m.NOME_EXIBICAO} (${m.TIPO_MIDIA} - ${m.DURACAO_PADRAO_SEG}s)
        </option>
      `).join('');
    }
  },

  async handleFileUpload(files) {
    if (!files || files.length === 0) return;
    for (let file of files) {
      this.showToast(`Enviando ${file.name}...`);
      const formData = new FormData();
      formData.append('file', file);
      try {
        const res = await fetch('/api/v1/medias/upload', {
          method: 'POST',
          body: formData
        });
        if (res.ok) {
          const data = await res.json();
          this.showToast(`Mídia ${file.name} cadastrada (${data.duration_sec}s)!`);
        } else {
          this.showToast(`Erro ao enviar ${file.name}`);
        }
      } catch (err) {
        this.showToast(`Erro na requisição: ${err.message}`);
      }
    }
    this.loadMedias();
    this.loadDashboard();
  },

  async saveYouTube(e) {
    e.preventDefault();
    const url = document.getElementById('ytUrl').value;
    const title = document.getElementById('ytTitle').value;

    const res = await fetch('/api/v1/medias/youtube', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url, title })
    });

    if (res.ok) {
      this.showToast('Vídeo do YouTube cadastrado com sucesso!');
      ModalManager.close('modalYouTube');
      document.getElementById('formYouTube').reset();
      this.loadMedias();
      this.loadDashboard();
    } else {
      const err = await res.json();
      alert(err.message || 'Erro ao cadastrar YouTube');
    }
  },

  async deleteMedia(id) {
    if (!confirm('Deseja realmente excluir esta mídia do catálogo?')) return;
    const res = await fetch(`/api/v1/medias/${id}`, { method: 'DELETE' });
    if (res.ok) {
      this.showToast('Mídia excluída');
      this.loadMedias();
      this.loadDashboard();
    }
  },

  previewMedia(mediaId) {
    const m = this.allMedias.find(x => x.ID == mediaId);
    if (!m) return;

    const container = document.getElementById('previewContainer');
    document.getElementById('previewTitle').textContent = m.NOME_EXIBICAO;

    if (m.TIPO_MIDIA === 'STREAM' || m.URL_DOWNLOAD.includes('youtube')) {
      let ytId = m.NOME_ARQUIVO.replace('youtube_', '');
      container.innerHTML = `<iframe src="https://www.youtube.com/embed/${ytId}?autoplay=1" allow="autoplay" allowfullscreen></iframe>`;
    } else if (m.TIPO_MIDIA === 'VIDEO') {
      container.innerHTML = `<video src="${m.URL_DOWNLOAD}" controls autoplay playsinline></video>`;
    } else {
      container.innerHTML = `<img src="${m.URL_DOWNLOAD}" alt="${m.NOME_EXIBICAO}">`;
    }

    ModalManager.open('modalMediaPreview');
  },

  // ========================================================
  // PLAYLISTS
  // ========================================================
  async loadPlaylists() {
    const res = await fetch('/api/v1/playlists');
    if (!res.ok) return;
    this.allPlaylists = await res.json();

    const list = document.getElementById('playlistsList');
    if (this.allPlaylists.length === 0) {
      list.innerHTML = '<p class="text-muted">Nenhuma playlist criada.</p>';
      return;
    }

    list.innerHTML = this.allPlaylists.map(p => `
      <div class="playlist-item-card ${this.selectedPlaylistId == p.ID ? 'selected' : ''}" onclick="App.selectPlaylist(${p.ID})">
        <h4>${p.NOME} ${p.IS_PADRAO ? '<span class="badge badge-default">Padrão</span>' : ''}</h4>
        <span class="text-muted">${p.items_count} mídias • ${p.total_duration_sec}s total</span>
      </div>
    `).join('');

    // Preenche select do agendamento
    const schedPlSelect = document.getElementById('schedPlaylistSelect');
    if (schedPlSelect) {
      schedPlSelect.innerHTML = this.allPlaylists.map(p => `
        <option value="${p.ID}">${p.NOME} (${p.items_count} mídias)</option>
      `).join('');
    }

    if (this.selectedPlaylistId) {
      this.loadPlaylistDetails(this.selectedPlaylistId);
    } else if (this.allPlaylists.length > 0) {
      this.selectPlaylist(this.allPlaylists[0].ID);
    }
  },

  selectPlaylist(plId) {
    this.selectedPlaylistId = plId;
    document.querySelectorAll('.playlist-item-card').forEach(el => el.classList.remove('selected'));
    this.loadPlaylists();
    this.loadPlaylistDetails(plId);
  },

  async loadPlaylistDetails(plId) {
    const res = await fetch(`/api/v1/playlists/${plId}`);
    if (!res.ok) return;
    const pl = await res.json();

    document.getElementById('selectedPlaylistTitle').innerHTML = `${pl.NOME} ${pl.IS_PADRAO ? '<span class="badge badge-default">Padrão</span>' : ''}`;
    document.getElementById('selectedPlaylistDesc').textContent = pl.DESCRICAO || 'Playlist configurada';
    document.getElementById('playlistEditorActions').style.display = 'flex';

    document.getElementById('btnSetDefaultPlaylist').onclick = () => this.setDefaultPlaylist(plId);
    document.getElementById('btnDeletePlaylist').onclick = () => this.deletePlaylist(plId);
    document.getElementById('btnAddItemToPlaylistBtn').onclick = () => this.openAddItemModal();

    const tbody = document.getElementById('playlistItemsTableBody');
    if (!pl.items || pl.items.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Nenhuma mídia adicionada a esta playlist. Clique em "Adicionar Mídia".</td></tr>';
      return;
    }

    tbody.innerHTML = pl.items.map((it, idx) => `
      <tr>
        <td><strong>#${it.order}</strong></td>
        <td><strong>${it.media_name}</strong></td>
        <td><span class="badge badge-type">${it.type}</span></td>
        <td>${it.duration_sec > 0 ? it.duration_sec + 's' : 'Total'}</td>
        <td>${it.transition}</td>
        <td>
          <button class="btn-sm btn-outline" onclick="App.movePlaylistItem(${it.item_id}, 'up')">⬆️</button>
          <button class="btn-sm btn-outline" onclick="App.movePlaylistItem(${it.item_id}, 'down')">⬇️</button>
          <button class="btn-sm btn-danger-outline" onclick="App.removePlaylistItem(${it.item_id})">🗑️</button>
        </td>
      </tr>
    `).join('');
  },

  openAddItemModal() {
    const select = document.getElementById('selectMediaForPl');
    if (select && select.options.length > 0) {
      this.onMediaSelectChange(select);
    }
    ModalManager.open('modalAddItemToPlaylist');
  },

  onMediaSelectChange(selectEl) {
    const mediaId = selectEl.value;
    const m = this.allMedias.find(x => x.ID == mediaId);
    const durationInput = document.getElementById('itemDuration');
    const groupDuration = document.getElementById('groupItemDuration');
    const durationText = document.getElementById('mediaDurationText');

    if (!m) return;

    if (m.TIPO_MIDIA === 'VIDEO') {
      groupDuration.style.display = 'none';
      durationInput.value = m.DURACAO_PADRAO_SEG || 10;
      durationText.textContent = `Vídeo: ${m.NOME_EXIBICAO} (duração total: ${m.DURACAO_PADRAO_SEG}s - reproduzirá o vídeo completo sem cortes)`;
    } else if (m.TIPO_MIDIA === 'STREAM' || m.URL_DOWNLOAD.includes('youtube')) {
      groupDuration.style.display = 'none';
      durationInput.value = 0;
      durationText.textContent = `YouTube / Stream: ${m.NOME_EXIBICAO} (reprodução contínua)`;
    } else {
      groupDuration.style.display = 'block';
      durationInput.value = 8;
      durationText.textContent = `Imagem: ${m.NOME_EXIBICAO} (defina o tempo de exibição do slide)`;
    }
  },

  async saveNewPlaylist(e) {
    e.preventDefault();
    const name = document.getElementById('plName').value;
    const desc = document.getElementById('plDesc').value;
    const isDefault = document.getElementById('plIsDefault').checked ? 1 : 0;

    const res = await fetch('/api/v1/playlists', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, description: desc, is_default: isDefault })
    });

    if (res.ok) {
      const data = await res.json();
      this.showToast('Playlist criada com sucesso!');
      ModalManager.close('modalNewPlaylist');
      document.getElementById('formNewPlaylist').reset();
      this.selectedPlaylistId = data.id;
      this.loadPlaylists();
      this.loadDashboard();
    }
  },

  async setDefaultPlaylist(plId) {
    const res = await fetch(`/api/v1/playlists/${plId}/default`, { method: 'POST' });
    if (res.ok) {
      this.showToast('Playlist definida como fallback padrão!');
      this.loadPlaylists();
    }
  },

  async deletePlaylist(plId) {
    if (!confirm('Deseja realmente excluir esta playlist?')) return;
    const res = await fetch(`/api/v1/playlists/${plId}`, { method: 'DELETE' });
    if (res.ok) {
      this.showToast('Playlist excluída');
      this.selectedPlaylistId = null;
      this.loadPlaylists();
      this.loadDashboard();
    }
  },

  async savePlaylistItem(e) {
    e.preventDefault();
    const mediaId = document.getElementById('selectMediaForPl').value;
    const m = this.allMedias.find(x => x.ID == mediaId);
    let duration = 0;
    
    if (m && m.TIPO_MIDIA === 'IMAGE') {
      duration = parseInt(document.getElementById('itemDuration').value) || 8;
    } else if (m) {
      duration = m.DURACAO_PADRAO_SEG || 0;
    }

    const transition = document.getElementById('itemTransition').value;

    const res = await fetch(`/api/v1/playlists/${this.selectedPlaylistId}/items`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ media_id: mediaId, duration_sec: duration, transition })
    });

    if (res.ok) {
      this.showToast('Mídia adicionada com a duração total!');
      ModalManager.close('modalAddItemToPlaylist');
      this.loadPlaylistDetails(this.selectedPlaylistId);
      this.loadPlaylists();
    }
  },

  async removePlaylistItem(itemId) {
    const res = await fetch(`/api/v1/playlist-items/${itemId}`, { method: 'DELETE' });
    if (res.ok) {
      this.showToast('Item removido');
      this.loadPlaylistDetails(this.selectedPlaylistId);
      this.loadPlaylists();
    }
  },

  async movePlaylistItem(itemId, direction) {
    const res = await fetch(`/api/v1/playlist-items/${itemId}/move`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ direction })
    });
    if (res.ok) {
      this.loadPlaylistDetails(this.selectedPlaylistId);
    }
  },

  // ========================================================
  // AGENDAMENTOS
  // ========================================================
  allSchedules: [],

  async loadSchedules() {
    const res = await fetch('/api/v1/schedules');
    if (!res.ok) return;
    this.allSchedules = await res.json();

    const tbody = document.getElementById('schedulesTableBody');
    if (this.allSchedules.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted">Nenhum agendamento ativo. Crie um novo agendamento.</td></tr>';
      return;
    }

    tbody.innerHTML = this.allSchedules.map(s => `
      <tr>
        <td><strong>${s.event_name}</strong></td>
        <td><span class="badge badge-type">📑 ${s.playlist_name}</span></td>
        <td><strong>${s.tela_target}</strong></td>
        <td>${s.start_date} até ${s.end_date}</td>
        <td>${s.start_time} - ${s.end_time}</td>
        <td>${s.days_of_week}</td>
        <td><span class="badge badge-default">Prio: ${s.priority}</span></td>
        <td>
          <button class="btn-sm btn-outline" onclick="App.editSchedule(${s.ID})" title="Editar Agendamento">✏️ Editar</button>
          <button class="btn-sm btn-danger-outline" onclick="App.deleteSchedule(${s.ID})" title="Excluir Agendamento">🗑️ Excluir</button>
        </td>
      </tr>
    `).join('');
  },

  openNewScheduleModal() {
    document.getElementById('formNewSchedule').reset();
    document.getElementById('schedId').value = '';
    document.getElementById('modalScheduleTitle').textContent = '📅 Novo Agendamento de Grade';
    document.getElementById('btnSubmitSchedule').textContent = 'Criar Agendamento';

    const now = new Date();
    const nextYear = new Date();
    nextYear.setFullYear(now.getFullYear() + 1);

    document.getElementById('schedStartDate').value = now.toISOString().split('T')[0];
    document.getElementById('schedEndDate').value = nextYear.toISOString().split('T')[0];
    document.getElementById('schedStartTime').value = '00:00:00';
    document.getElementById('schedEndTime').value = '23:59:59';
    document.getElementById('schedPriority').value = '10';

    document.querySelectorAll('input[name="schedDays"]').forEach(cb => cb.checked = true);
    ModalManager.open('modalNewSchedule');
  },

  editSchedule(id) {
    const s = this.allSchedules.find(x => x.ID == id);
    if (!s) return;

    document.getElementById('schedId').value = s.ID;
    document.getElementById('modalScheduleTitle').textContent = `✏️ Editar Agendamento: ${s.event_name}`;
    document.getElementById('btnSubmitSchedule').textContent = 'Salvar Alterações';

    document.getElementById('schedEventName').value = s.event_name;
    document.getElementById('schedPlaylistSelect').value = s.PLAYLIST_ID;
    document.getElementById('schedScreenSelect').value = s.TELA_ID || '';
    document.getElementById('schedStartDate').value = s.start_date;
    document.getElementById('schedEndDate').value = s.end_date;
    document.getElementById('schedStartTime').value = s.start_time;
    document.getElementById('schedEndTime').value = s.end_time;
    document.getElementById('schedPriority').value = s.priority;

    const days = (s.days_of_week || '').split(',').map(x => x.trim());
    document.querySelectorAll('input[name="schedDays"]').forEach(cb => {
      cb.checked = days.includes(cb.value);
    });

    ModalManager.open('modalNewSchedule');
  },

  async saveSchedule(e) {
    e.preventDefault();
    const id = document.getElementById('schedId').value;
    const event_name = document.getElementById('schedEventName').value;
    const playlist_id = document.getElementById('schedPlaylistSelect').value;
    const screen_id = document.getElementById('schedScreenSelect').value || null;
    const start_date = document.getElementById('schedStartDate').value;
    const end_date = document.getElementById('schedEndDate').value;
    const start_time = document.getElementById('schedStartTime').value;
    const end_time = document.getElementById('schedEndTime').value;
    const priority = document.getElementById('schedPriority').value;

    const days = [];
    document.querySelectorAll('input[name="schedDays"]:checked').forEach(cb => days.push(cb.value));

    const payload = {
      event_name,
      playlist_id,
      screen_id,
      start_date,
      end_date,
      start_time,
      end_time,
      days_of_week: days.join(','),
      priority
    };

    if (id) {
      payload.id = parseInt(id);
    }

    const res = await fetch('/api/v1/schedules', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    if (res.ok) {
      this.showToast(id ? 'Agendamento atualizado com sucesso!' : 'Agendamento criado com sucesso!');
      ModalManager.close('modalNewSchedule');
      document.getElementById('formNewSchedule').reset();
      this.loadSchedules();
    }
  },

  async deleteSchedule(id) {
    if (!confirm('Deseja realmente excluir este agendamento?')) return;
    const res = await fetch(`/api/v1/schedules/${id}`, { method: 'DELETE' });
    if (res.ok) {
      this.showToast('Agendamento excluído');
      this.loadSchedules();
    }
  },

  // ========================================================
  // LOGS
  // ========================================================
  async loadLogs() {
    const res = await fetch('/api/v1/dashboard/logs');
    if (!res.ok) return;
    const logs = await res.json();

    const tbody = document.getElementById('fullLogsTableBody');
    if (logs.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Nenhum log registrado.</td></tr>';
      return;
    }

    tbody.innerHTML = logs.map(l => `
      <tr>
        <td>#${l.ID}</td>
        <td>${l.DATA_HORA_INICIO ? l.DATA_HORA_INICIO.split('.')[0] : '-'}</td>
        <td><strong>${l.TELA_NOME}</strong></td>
        <td>${l.MIDIA_NOME}</td>
        <td>${l.PLAYLIST_NOME}</td>
        <td>${l.SEGUNDOS_EXIBIDOS}s</td>
        <td><span class="badge badge-online">${l.STATUS_EXIBICAO || 'COMPLETED'}</span></td>
      </tr>
    `).join('');
  },

  showToast(msg) {
    const el = document.getElementById('toastNotification');
    el.textContent = msg;
    el.classList.add('show');
    setTimeout(() => el.classList.remove('show'), 3500);
  }
};

const ModalManager = {
  open(id) {
    const m = document.getElementById(id);
    if (m) m.classList.add('open');
  },
  close(id) {
    const m = document.getElementById(id);
    if (m) {
      m.classList.remove('open');
      if (id === 'modalMediaPreview') {
        document.getElementById('previewContainer').innerHTML = '';
      }
    }
  }
};

document.addEventListener('DOMContentLoaded', () => App.init());
