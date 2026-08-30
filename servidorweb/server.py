#!/usr/bin/env python3
"""
Digital Signage Modern Web CMS Server
Servidor Web 100% autônomo com Dashboard, API REST, Web Player e Gerenciador de Mídias.
"""

import http.server
import socketserver
import os
import json
import urllib.parse
import hashlib
import mimetypes
import struct
from datetime import datetime, date

from db import get_db, DB_PATH

PORT = 8080
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PUBLIC_DIR = os.path.join(BASE_DIR, 'public')
MEDIA_DIR = os.path.join(BASE_DIR, 'media')

os.makedirs(MEDIA_DIR, exist_ok=True)
os.makedirs(PUBLIC_DIR, exist_ok=True)

def detect_mp4_duration(file_path):
    """Detecta duração de arquivo MP4 via ISO-BMFF mvhd atom."""
    if not os.path.exists(file_path):
        return 10
    try:
        with open(file_path, 'rb') as f:
            f.seek(0, 2)
            file_len = f.tell()
            f.seek(0, 0)
            while f.tell() < file_len - 8:
                pos = f.tell()
                buf = f.read(8)
                if len(buf) < 8:
                    break
                atom_size = struct.unpack('>I', buf[0:4])[0]
                atom_type = buf[4:8].decode('latin1', errors='ignore')

                if atom_size == 0:
                    atom_size = file_len - pos
                elif atom_size == 1:
                    f.seek(pos + 16)
                    continue

                if atom_type == 'moov':
                    continue
                elif atom_type == 'mvhd':
                    version = f.read(1)[0]
                    f.seek(3, 1) # flags
                    if version == 1:
                        f.seek(16, 1)
                        ts = struct.unpack('>I', f.read(4))[0]
                        f.seek(4, 1)
                        dur = struct.unpack('>I', f.read(4))[0]
                    else:
                        f.seek(8, 1)
                        ts = struct.unpack('>I', f.read(4))[0]
                        dur = struct.unpack('>I', f.read(4))[0]
                    if ts > 0 and dur > 0:
                        sec = round(dur / ts)
                        return max(1, sec)
                else:
                    if atom_size > 8 and pos + atom_size <= file_len:
                        f.seek(pos + atom_size)
                    else:
                        break
    except Exception as e:
        print(f"[Detector] Erro ao ler MP4 {file_path}: {e}")
    return 10

class SignageWebHandler(http.server.BaseHTTPRequestHandler):
    server_version = "DigitalSignageWebCMS/2.0"

    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False, default=str).encode('utf-8')
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, message, status=400):
        self.send_json({"status": "error", "message": message}, status=status)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        # 1. API: Dashboard
        if path == "/api/v1/dashboard/stats":
            self.api_dashboard_stats()
            return
        elif path == "/api/v1/dashboard/logs":
            self.api_dashboard_logs()
            return
        elif path == "/api/v1/server/test-db":
            self.send_json({"status": "ok", "message": "Banco de dados SQLite/Firebird operacional"})
            return

        # 2. API: Telas
        elif path in ("/api/v1/screens", "/api/v1/players"):
            self.api_list_screens()
            return

        # 3. API: Mídias
        elif path == "/api/v1/medias":
            self.api_list_medias()
            return

        # 4. API: Playlists
        elif path == "/api/v1/playlists":
            self.api_list_playlists()
            return
        elif path.startswith("/api/v1/playlists/") and not path.endswith("/items") and not path.endswith("/default"):
            pl_id = path.replace("/api/v1/playlists/", "")
            self.api_get_playlist(pl_id)
            return

        # 5. API: Agendamentos
        elif path == "/api/v1/schedules":
            self.api_list_schedules()
            return

        # 6. API: Player Sync Protocol
        elif path.startswith("/api/v1/players/") and path.endswith("/sync"):
            uuid = path.replace("/api/v1/players/", "").replace("/sync", "").strip()
            pname = query.get('name', [''])[0]
            self.api_player_sync(uuid, pname)
            return

        # 7. Download & Streaming de Mídias
        elif path.startswith("/media/"):
            filename = os.path.basename(path.replace("/media/", ""))
            self.serve_media_file(filename)
            return

        # 8. Arquivos Estáticos do CMS e Web Player
        self.serve_static(path)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # 1. Upload de Mídia (Multipart)
        if path == "/api/v1/medias/upload":
            self.api_upload_media()
            return

        # 2. Cadastro de YouTube
        elif path == "/api/v1/medias/youtube":
            body = self.read_json_body()
            self.api_add_youtube(body)
            return

        # 3. Criar Playlist
        elif path == "/api/v1/playlists":
            body = self.read_json_body()
            self.api_create_playlist(body)
            return

        # 4. Definir Playlist Padrão
        elif path.startswith("/api/v1/playlists/") and path.endswith("/default"):
            pl_id = path.replace("/api/v1/playlists/", "").replace("/default", "")
            self.api_set_default_playlist(pl_id)
            return

        # 5. Adicionar Item à Playlist
        elif path.startswith("/api/v1/playlists/") and path.endswith("/items"):
            pl_id = path.replace("/api/v1/playlists/", "").replace("/items", "")
            body = self.read_json_body()
            self.api_add_playlist_item(pl_id, body)
            return

        # 6. Reordenar Item da Playlist
        elif path.startswith("/api/v1/playlist-items/") and path.endswith("/move"):
            item_id = path.replace("/api/v1/playlist-items/", "").replace("/move", "")
            body = self.read_json_body()
            self.api_move_playlist_item(item_id, body.get('direction', 'up'))
            return

        # 7. Criar Agendamento
        elif path == "/api/v1/schedules":
            body = self.read_json_body()
            self.api_create_schedule(body)
            return

        # 8. Player: Registro
        elif path == "/api/v1/players/register":
            body = self.read_json_body()
            self.api_player_register(body)
            return

        # 9. Player: Heartbeat
        elif path.startswith("/api/v1/players/") and path.endswith("/heartbeat"):
            uuid = path.replace("/api/v1/players/", "").replace("/heartbeat", "").strip()
            body = self.read_json_body()
            self.api_player_heartbeat(uuid, body)
            return

        # 10. Player: Proof of Play
        elif path.startswith("/api/v1/players/") and path.endswith("/proof-of-play"):
            uuid = path.replace("/api/v1/players/", "").replace("/proof-of-play", "").strip()
            body = self.read_json_body()
            self.api_player_proof_of_play(uuid, body)
            return

        self.send_error_json(f"Endpoint não encontrado: {path}", 404)

    def do_DELETE(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path.startswith("/api/v1/screens/"):
            s_id = path.replace("/api/v1/screens/", "")
            self.api_delete_screen(s_id)
            return
        elif path.startswith("/api/v1/medias/"):
            m_id = path.replace("/api/v1/medias/", "")
            self.api_delete_media(m_id)
            return
        elif path.startswith("/api/v1/playlists/"):
            pl_id = path.replace("/api/v1/playlists/", "")
            self.api_delete_playlist(pl_id)
            return
        elif path.startswith("/api/v1/playlist-items/"):
            item_id = path.replace("/api/v1/playlist-items/", "")
            self.api_remove_playlist_item(item_id)
            return
        elif path.startswith("/api/v1/schedules/"):
            sch_id = path.replace("/api/v1/schedules/", "")
            self.api_delete_schedule(sch_id)
            return

        self.send_error_json(f"Endpoint DELETE não encontrado: {path}", 404)

    def read_json_body(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length == 0:
                return {}
            raw = self.rfile.read(length).decode('utf-8')
            return json.loads(raw)
        except Exception:
            return {}

    # ==========================================
    # API HANDLERS
    # ==========================================

    def api_dashboard_stats(self):
        conn = get_db()
        cur = conn.cursor()
        
        cur.execute("SELECT COUNT(*) FROM TELAS")
        total_screens = cur.fetchone()[0]
        
        cur.execute("SELECT COUNT(*) FROM TELAS WHERE ULTIMO_HEARTBEAT >= datetime('now', '-2 minutes')")
        online_screens = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM PLAYLISTS WHERE ATIVA = 1")
        total_playlists = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*), COALESCE(SUM(TAMANHO_BYTES), 0) FROM MIDIAS WHERE STATUS = 'READY'")
        row = cur.fetchone()
        total_medias = row[0]
        total_bytes = row[1]

        cur.execute("SELECT COUNT(*) FROM LOGS_EXIBICAO WHERE date(DATA_HORA_INICIO) = date('now')")
        proof_today = cur.fetchone()[0]

        conn.close()

        self.send_json({
            "total_screens": total_screens,
            "online_screens": online_screens,
            "offline_screens": total_screens - online_screens,
            "active_playlists": total_playlists,
            "total_medias": total_medias,
            "storage_bytes": total_bytes,
            "storage_mb": round(total_bytes / (1024 * 1024), 1),
            "proof_today": proof_today,
            "server_time": datetime.now().isoformat()
        })

    def api_dashboard_logs(self):
        conn = get_db()
        cur = conn.cursor()
        cur.execute("""
            SELECT l.ID, l.DATA_HORA_INICIO, l.SEGUNDOS_EXIBIDOS, l.STATUS_EXIBICAO,
                   COALESCE(t.NOME, 'Tela Desconhecida') AS TELA_NOME,
                   COALESCE(m.NOME_EXIBICAO, 'Mídia') AS MIDIA_NOME,
                   COALESCE(p.NOME, 'Playlist') AS PLAYLIST_NOME
            FROM LOGS_EXIBICAO l
            LEFT JOIN TELAS t ON t.ID = l.TELA_ID
            LEFT JOIN MIDIAS m ON m.ID = l.MIDIA_ID
            LEFT JOIN PLAYLISTS p ON p.ID = l.PLAYLIST_ID
            ORDER BY l.ID DESC LIMIT 50
        """)
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        self.send_json(rows)

    def api_list_screens(self):
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM TELAS ORDER BY NOME")
        rows = []
        for r in cur.fetchall():
            d = dict(r)
            # Verifica status Online baseado em heartbeat de 2 minutos
            if d.get('ULTIMO_HEARTBEAT'):
                try:
                    hb = datetime.fromisoformat(d['ULTIMO_HEARTBEAT'].replace(' ', 'T'))
                    diff = (datetime.now() - hb).total_seconds()
                    d['status'] = 'ONLINE' if diff < 120 else 'OFFLINE'
                except Exception:
                    d['status'] = d.get('STATUS', 'ONLINE')
            else:
                d['status'] = 'OFFLINE'
            rows.append(d)
        conn.close()
        self.send_json(rows)

    def api_delete_screen(self, s_id):
        conn = get_db()
        with conn:
            conn.execute("DELETE FROM LOGS_EXIBICAO WHERE TELA_ID = ?", (s_id,))
            conn.execute("DELETE FROM AGENDAMENTOS WHERE TELA_ID = ?", (s_id,))
            conn.execute("DELETE FROM TELAS WHERE ID = ?", (s_id,))
        conn.close()
        self.send_json({"status": "ok", "message": "Tela excluída com sucesso"})

    def api_list_medias(self):
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM MIDIAS ORDER BY ID DESC")
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        self.send_json(rows)

    def api_upload_media(self):
        try:
            content_type = self.headers.get('Content-Type', '')
            if 'multipart/form-data' not in content_type:
                self.send_error_json("Requisição precisa ser multipart/form-data")
                return

            boundary_str = content_type.split('boundary=')[1].strip()
            if boundary_str.startswith('"') and boundary_str.endswith('"'):
                boundary_str = boundary_str[1:-1]
            boundary = boundary_str.encode('utf-8')

            length = int(self.headers.get('Content-Length', 0))
            raw_data = self.rfile.read(length)

            delimiter = b'--' + boundary
            parts = raw_data.split(delimiter)

            filename = None
            file_content = None

            for part in parts:
                if not part or part == b'--\r\n' or part == b'--':
                    continue
                if b'\r\n\r\n' in part:
                    header_part, body_part = part.split(b'\r\n\r\n', 1)
                    if body_part.endswith(b'\r\n'):
                        body_part = body_part[:-2]
                    head_str = header_part.decode('latin1', errors='ignore')
                    if 'filename="' in head_str:
                        fn = head_str.split('filename="')[1].split('"')[0]
                        filename = os.path.basename(fn)
                        file_content = body_part
                        break

            if not filename or file_content is None:
                self.send_error_json("Nenhum arquivo válido encontrado no envio")
                return

            dest_path = os.path.join(MEDIA_DIR, filename)
            with open(dest_path, 'wb') as f:
                f.write(file_content)

            size = len(file_content)
            md5_hash = hashlib.md5(file_content).hexdigest()

            ext = os.path.splitext(filename)[1].lower()
            if ext in ('.mp4', '.mkv', '.avi', '.mov', '.webm'):
                media_type = 'VIDEO'
                mime = 'video/mp4'
                duration = detect_mp4_duration(dest_path)
            elif ext in ('.jpg', '.jpeg'):
                media_type = 'IMAGE'
                mime = 'image/jpeg'
                duration = 8
            elif ext == '.png':
                media_type = 'IMAGE'
                mime = 'image/png'
                duration = 8
            else:
                media_type = 'IMAGE'
                mime = 'application/octet-stream'
                duration = 8

            conn = get_db()
            with conn:
                cur = conn.cursor()
                cur.execute("""
                    INSERT OR REPLACE INTO MIDIAS 
                    (NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, TIPO_MIDIA, MIME_TYPE, DURACAO_PADRAO_SEG, URL_DOWNLOAD)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (filename, filename, md5_hash, size, media_type, mime, duration, f"/media/{filename}"))
                new_id = cur.lastrowid
            conn.close()

            self.send_json({"status": "ok", "id": new_id, "filename": filename, "duration_sec": duration})
        except Exception as e:
            self.send_error_json(f"Erro no upload: {e}", 500)

    def api_add_youtube(self, body):
        url = body.get('url', '').strip()
        title = body.get('title', '').strip()
        if not url:
            self.send_error_json("URL do YouTube é obrigatória")
            return

        video_id = ""
        if "v=" in url:
            video_id = url.split("v=")[1][:11]
        elif "youtu.be/" in url:
            video_id = url.split("youtu.be/")[1][:11]
        elif len(url) == 11:
            video_id = url

        if not video_id:
            self.send_error_json("ID de vídeo do YouTube não encontrado na URL")
            return

        if not title:
            title = f"YouTube - {video_id}"

        filename = f"youtube_{video_id}"
        md5_hash = hashlib.md5(filename.encode('utf-8')).hexdigest()

        conn = get_db()
        with conn:
            cur = conn.cursor()
            cur.execute("""
                INSERT OR REPLACE INTO MIDIAS 
                (NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, TIPO_MIDIA, MIME_TYPE, DURACAO_PADRAO_SEG, URL_DOWNLOAD)
                VALUES (?, ?, ?, 0, 'STREAM', 'video/youtube', 0, ?)
            """, (title, filename, md5_hash, f"https://www.youtube.com/watch?v={video_id}"))
            new_id = cur.lastrowid
        conn.close()

        self.send_json({"status": "ok", "id": new_id, "video_id": video_id})

    def api_delete_media(self, m_id):
        conn = get_db()
        with conn:
            conn.execute("DELETE FROM PLAYLIST_ITENS WHERE MIDIA_ID = ?", (m_id,))
            conn.execute("DELETE FROM LOGS_EXIBICAO WHERE MIDIA_ID = ?", (m_id,))
            conn.execute("DELETE FROM MIDIAS WHERE ID = ?", (m_id,))
        conn.close()
        self.send_json({"status": "ok", "message": "Mídia excluída com sucesso"})

    def api_list_playlists(self):
        conn = get_db()
        cur = conn.cursor()
        cur.execute("""
            SELECT p.*, COUNT(pi.ID) AS items_count, COALESCE(SUM(pi.DURACAO_SEG), 0) AS total_duration_sec
            FROM PLAYLISTS p
            LEFT JOIN PLAYLIST_ITENS pi ON pi.PLAYLIST_ID = p.ID
            GROUP BY p.ID
            ORDER BY p.ID ASC
        """)
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        self.send_json(rows)

    def api_get_playlist(self, pl_id):
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM PLAYLISTS WHERE ID = ?", (pl_id,))
        pl = cur.fetchone()
        if not pl:
            conn.close()
            self.send_error_json("Playlist não encontrada", 404)
            return

        res = dict(pl)
        cur.execute("""
            SELECT pi.ID AS item_id, pi.ORDEM AS `order`, pi.DURACAO_SEG AS duration_sec, pi.TRANSICAO AS transition,
                   m.ID AS media_id, m.NOME_EXIBICAO AS media_name, m.NOME_ARQUIVO AS filename, m.TIPO_MIDIA AS type, m.URL_DOWNLOAD AS url
            FROM PLAYLIST_ITENS pi
            JOIN MIDIAS m ON m.ID = pi.MIDIA_ID
            WHERE pi.PLAYLIST_ID = ?
            ORDER BY pi.ORDEM ASC
        """, (pl_id,))
        res['items'] = [dict(r) for r in cur.fetchall()]
        conn.close()
        self.send_json(res)

    def api_create_playlist(self, body):
        name = body.get('name', 'Nova Playlist').strip()
        desc = body.get('description', '').strip()
        is_default = int(body.get('is_default', 0))

        conn = get_db()
        with conn:
            cur = conn.cursor()
            if is_default == 1:
                cur.execute("UPDATE PLAYLISTS SET IS_PADRAO = 0")
            cur.execute("INSERT INTO PLAYLISTS (NOME, DESCRICAO, IS_PADRAO, ATIVA) VALUES (?, ?, ?, 1)", (name, desc, is_default))
            new_id = cur.lastrowid
        conn.close()
        self.send_json({"status": "ok", "id": new_id})

    def api_set_default_playlist(self, pl_id):
        conn = get_db()
        with conn:
            conn.execute("UPDATE PLAYLISTS SET IS_PADRAO = 0")
            conn.execute("UPDATE PLAYLISTS SET IS_PADRAO = 1 WHERE ID = ?", (pl_id,))
        conn.close()
        self.send_json({"status": "ok", "message": "Playlist definida como padrão"})

    def api_delete_playlist(self, pl_id):
        conn = get_db()
        with conn:
            conn.execute("DELETE FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = ?", (pl_id,))
            conn.execute("DELETE FROM AGENDAMENTOS WHERE PLAYLIST_ID = ?", (pl_id,))
            conn.execute("DELETE FROM PLAYLISTS WHERE ID = ?", (pl_id,))
        conn.close()
        self.send_json({"status": "ok", "message": "Playlist excluída com sucesso"})

    def api_add_playlist_item(self, pl_id, body):
        media_id = body.get('media_id')
        duration = body.get('duration_sec', 10)
        transition = body.get('transition', 'CUT')

        conn = get_db()
        with conn:
            cur = conn.cursor()
            cur.execute("SELECT COALESCE(MAX(ORDEM), 0) + 1 FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = ?", (pl_id,))
            next_ord = cur.fetchone()[0]
            cur.execute("""
                INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_SEG, TRANSICAO)
                VALUES (?, ?, ?, ?, ?)
            """, (pl_id, media_id, next_ord, duration, transition))
        conn.close()
        self.send_json({"status": "ok", "message": "Item adicionado à playlist"})

    def api_remove_playlist_item(self, item_id):
        conn = get_db()
        with conn:
            conn.execute("DELETE FROM PLAYLIST_ITENS WHERE ID = ?", (item_id,))
        conn.close()
        self.send_json({"status": "ok", "message": "Item removido da playlist"})

    def api_move_playlist_item(self, item_id, direction):
        conn = get_db()
        with conn:
            cur = conn.cursor()
            cur.execute("SELECT PLAYLIST_ID, ORDEM FROM PLAYLIST_ITENS WHERE ID = ?", (item_id,))
            row = cur.fetchone()
            if not row:
                conn.close()
                self.send_error_json("Item não encontrado", 404)
                return

            pl_id, cur_ord = row[0], row[1]
            if direction == 'up':
                cur.execute("SELECT ID, ORDEM FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = ? AND ORDEM < ? ORDER BY ORDEM DESC LIMIT 1", (pl_id, cur_ord))
            else:
                cur.execute("SELECT ID, ORDEM FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = ? AND ORDEM > ? ORDER BY ORDEM ASC LIMIT 1", (pl_id, cur_ord))
            
            target = cur.fetchone()
            if target:
                t_id, t_ord = target[0], target[1]
                cur.execute("UPDATE PLAYLIST_ITENS SET ORDEM = ? WHERE ID = ?", (t_ord, item_id))
                cur.execute("UPDATE PLAYLIST_ITENS SET ORDEM = ? WHERE ID = ?", (cur_ord, t_id))
        conn.close()
        self.send_json({"status": "ok", "message": "Ordem atualizada"})

    def api_list_schedules(self):
        conn = get_db()
        cur = conn.cursor()
        cur.execute("""
            SELECT a.ID, a.NOME_EVENTO AS event_name, a.PLAYLIST_ID, p.NOME AS playlist_name,
                   a.TELA_ID, COALESCE(t.NOME, '[TODAS AS TELAS - GLOBAL]') AS tela_target,
                   a.DATA_INICIO AS start_date, a.DATA_FIM AS end_date,
                   a.HORA_INICIO AS start_time, a.HORA_FIM AS end_time,
                   a.DIAS_SEMANA AS days_of_week, a.PRIORIDADE AS priority, a.ATIVO AS is_active
            FROM AGENDAMENTOS a
            JOIN PLAYLISTS p ON p.ID = a.PLAYLIST_ID
            LEFT JOIN TELAS t ON t.ID = a.TELA_ID
            ORDER BY a.PRIORIDADE DESC, a.ID DESC
        """)
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        self.send_json(rows)

    def api_create_schedule(self, body):
        event_name = body.get('event_name', 'Campanha').strip()
        pl_id = body.get('playlist_id')
        screen_id = body.get('screen_id') or None
        start_date = body.get('start_date', date.today().isoformat())
        end_date = body.get('end_date', '2030-12-31')
        start_time = body.get('start_time', '00:00:00')
        end_time = body.get('end_time', '23:59:59')
        days = body.get('days_of_week', '1,2,3,4,5,6,7')
        priority = int(body.get('priority', 10))

        conn = get_db()
        with conn:
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO AGENDAMENTOS (NOME_EVENTO, PLAYLIST_ID, TELA_ID, DATA_INICIO, DATA_FIM, HORA_INICIO, HORA_FIM, DIAS_SEMANA, PRIORIDADE, ATIVO)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            """, (event_name, pl_id, screen_id, start_date, end_date, start_time, end_time, days, priority))
            new_id = cur.lastrowid
        conn.close()
        self.send_json({"status": "ok", "id": new_id})

    def api_delete_schedule(self, sch_id):
        conn = get_db()
        with conn:
            conn.execute("DELETE FROM AGENDAMENTOS WHERE ID = ?", (sch_id,))
        conn.close()
        self.send_json({"status": "ok", "message": "Agendamento excluído"})

    # ==========================================
    # PLAYER SYNC PROTOCOL
    # ==========================================

    def api_player_register(self, body):
        uuid_str = body.get('uuid', '').strip()
        name = body.get('name', 'Web Player').strip()
        local_ip = body.get('local_ip', self.client_address[0])
        mac = body.get('mac_address', '')
        os_name = body.get('os', 'WebBrowser')
        version = body.get('version', '2.0.0')

        if not uuid_str:
            self.send_error_json("UUID obrigatório")
            return

        conn = get_db()
        with conn:
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO TELAS (UUID, NOME, IP_LOCAL, IP_PUBLICO, MAC_ADDRESS, SISTEMA_OPERACIONAL, VERSAO_PLAYER, STATUS, ULTIMO_HEARTBEAT)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'ONLINE', CURRENT_TIMESTAMP)
                ON CONFLICT(UUID) DO UPDATE SET
                NOME = excluded.NOME,
                IP_LOCAL = excluded.IP_LOCAL,
                IP_PUBLICO = excluded.IP_PUBLICO,
                SISTEMA_OPERACIONAL = excluded.SISTEMA_OPERACIONAL,
                VERSAO_PLAYER = excluded.VERSAO_PLAYER,
                STATUS = 'ONLINE',
                ULTIMO_HEARTBEAT = CURRENT_TIMESTAMP
            """, (uuid_str, name, local_ip, self.client_address[0], mac, os_name, version))
        conn.close()
        self.send_json({"status": "ok", "uuid": uuid_str})

    def api_player_heartbeat(self, uuid_str, body):
        status = body.get('status', 'ONLINE')
        version = body.get('version', '2.0.0')
        free_mb = body.get('free_space_mb', 0)

        conn = get_db()
        with conn:
            conn.execute("""
                UPDATE TELAS SET STATUS = ?, VERSAO_PLAYER = ?, ESPACO_DISCO_LIVRE_MB = ?, ULTIMO_HEARTBEAT = CURRENT_TIMESTAMP
                WHERE UUID = ?
            """, (status, version, free_mb, uuid_str))
        conn.close()
        self.send_json({"status": "ok", "commands": []})

    def api_player_proof_of_play(self, uuid_str, body):
        conn = get_db()
        with conn:
            cur = conn.cursor()
            cur.execute("SELECT ID FROM TELAS WHERE UUID = ?", (uuid_str,))
            t_row = cur.fetchone()
            tela_id = t_row[0] if t_row else None

            if isinstance(body, list):
                for item in body:
                    cur.execute("""
                        INSERT INTO LOGS_EXIBICAO (TELA_ID, MIDIA_ID, PLAYLIST_ID, DATA_HORA_INICIO, DATA_HORA_FIM, SEGUNDOS_EXIBIDOS, STATUS_EXIBICAO, MENSAGEM_ERRO)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, (tela_id, item.get('media_id'), item.get('playlist_id'), item.get('start_time'), item.get('end_time'), item.get('seconds_played', 0), item.get('status', 'COMPLETED'), item.get('error_message', '')))
        conn.close()
        self.send_json({"status": "ok", "records": len(body) if isinstance(body, list) else 0})

    def api_player_sync(self, uuid_str, pname_override=""):
        conn = get_db()
        cur = conn.cursor()

        # 1. Identifica ou auto-cadastra a tela
        cur.execute("SELECT ID, UUID, NOME, STATUS, VOLUME_AUDIO FROM TELAS WHERE UUID = ? OR NOME = ?", (uuid_str, uuid_str))
        row = cur.fetchone()
        if not row:
            # Auto-registro transparente
            pname = pname_override or f"Web Player {uuid_str[:8]}"
            cur.execute("""
                INSERT INTO TELAS (UUID, NOME, IP_LOCAL, IP_PUBLICO, STATUS, ULTIMO_HEARTBEAT)
                VALUES (?, ?, '127.0.0.1', '127.0.0.1', 'ONLINE', CURRENT_TIMESTAMP)
            """, (uuid_str, pname))
            conn.commit()
            cur.execute("SELECT ID, UUID, NOME, STATUS, VOLUME_AUDIO FROM TELAS WHERE UUID = ?", (uuid_str,))
            row = cur.fetchone()

        player_id = row['ID']
        player_name = pname_override or row['NOME']
        volume = row['VOLUME_AUDIO']

        # 2. Busca Playlist Padrão de Fallback
        cur.execute("SELECT * FROM PLAYLISTS WHERE IS_PADRAO = 1 AND ATIVA = 1 LIMIT 1")
        fb_row = cur.fetchone()
        fallback_pl = None
        if fb_row:
            cur.execute("""
                SELECT pi.ID AS item_id, pi.ORDEM AS `order`, pi.DURACAO_SEG AS duration_sec, pi.TRANSICAO AS transition,
                       m.ID AS media_id, m.NOME_EXIBICAO AS media_name, m.NOME_ARQUIVO AS filename, m.HASH_MD5 AS hash_md5,
                       m.TIPO_MIDIA AS type, m.MIME_TYPE AS mime_type, m.URL_DOWNLOAD AS download_url
                FROM PLAYLIST_ITENS pi
                JOIN MIDIAS m ON m.ID = pi.MIDIA_ID
                WHERE pi.PLAYLIST_ID = ?
                ORDER BY pi.ORDEM ASC
            """, (fb_row['ID'],))
            fallback_pl = {
                "id": fb_row['ID'],
                "name": fb_row['NOME'],
                "is_default": 1,
                "items": [dict(r) for r in cur.fetchall()]
            }

        # 3. Busca Agendamentos com Isolamento Estrito por Tela
        cur.execute("""
            SELECT a.ID AS sched_id, a.NOME_EVENTO AS event_name, a.PRIORIDADE AS priority,
                   a.DATA_INICIO AS start_date, a.DATA_FIM AS end_date,
                   a.HORA_INICIO AS start_time, a.HORA_FIM AS end_time,
                   a.DIAS_SEMANA AS days_of_week,
                   p.ID AS playlist_id, p.NOME AS playlist_name
            FROM AGENDAMENTOS a
            JOIN PLAYLISTS p ON p.ID = a.PLAYLIST_ID
            LEFT JOIN TELAS t ON t.ID = a.TELA_ID
            WHERE (
                   a.TELA_ID = ? 
                OR LOWER(TRIM(t.NOME)) = LOWER(TRIM(?))
                OR LOWER(TRIM(a.NOME_EVENTO)) = LOWER(TRIM(?))
                OR (a.TELA_ID IS NULL AND NOT EXISTS (
                   SELECT 1 FROM AGENDAMENTOS a2 
                   LEFT JOIN TELAS t2 ON t2.ID = a2.TELA_ID
                   WHERE (a2.TELA_ID = ? OR LOWER(TRIM(t2.NOME)) = LOWER(TRIM(?)) OR LOWER(TRIM(a2.NOME_EVENTO)) = LOWER(TRIM(?)))
                     AND a2.ATIVO = 1 AND a2.DATA_FIM >= date('now')))
            )
              AND a.ATIVO = 1 AND p.ATIVA = 1 AND a.DATA_FIM >= date('now')
            ORDER BY a.PRIORIDADE DESC, a.ID ASC
        """, (player_id, player_name, player_name, player_id, player_name, player_name))

        schedules = []
        required_medias = []
        seen_media_ids = set()

        for s_row in cur.fetchall():
            s_dict = dict(s_row)
            pl_id = s_dict['playlist_id']

            cur2 = conn.cursor()
            cur2.execute("""
                SELECT pi.ID AS item_id, pi.ORDEM AS `order`, pi.DURACAO_SEG AS duration_sec, pi.TRANSICAO AS transition,
                       m.ID AS media_id, m.NOME_EXIBICAO AS media_name, m.NOME_ARQUIVO AS filename, m.HASH_MD5 AS hash_md5,
                       m.TIPO_MIDIA AS type, m.MIME_TYPE AS mime_type, m.URL_DOWNLOAD AS download_url
                FROM PLAYLIST_ITENS pi
                JOIN MIDIAS m ON m.ID = pi.MIDIA_ID
                WHERE pi.PLAYLIST_ID = ?
                ORDER BY pi.ORDEM ASC
            """, (pl_id,))
            items = [dict(r) for r in cur2.fetchall()]

            for it in items:
                m_id = it['media_id']
                if m_id not in seen_media_ids:
                    seen_media_ids.add(m_id)
                    required_medias.append({
                        "id": m_id,
                        "filename": it['filename'],
                        "hash_md5": it['hash_md5'],
                        "mime_type": it['mime_type'],
                        "download_url": it['download_url']
                    })

            s_dict['playlist'] = {
                "id": pl_id,
                "name": s_dict['playlist_name'],
                "is_default": 0,
                "items": items
            }
            schedules.append(s_dict)

        conn.close()

        self.send_json({
            "status": "ok",
            "server_time": datetime.now().isoformat(),
            "player_id": player_id,
            "player_uuid": uuid_str,
            "player_name": player_name,
            "volume": volume,
            "fallback_playlist": fallback_pl or {"id": 0, "name": "Nenhuma", "is_default": 1, "items": []},
            "schedules": schedules,
            "required_medias": required_medias
        })

    # ==========================================
    # SERVING ESTÁTICO & VÍDEOS COM HTTP RANGE
    # ==========================================

    def serve_media_file(self, filename):
        file_path = os.path.join(MEDIA_DIR, filename)
        if not os.path.exists(file_path):
            # Fallback para server/media se necessário
            alt_path = os.path.join(BASE_DIR, '..', 'server', 'media', filename)
            if os.path.exists(alt_path):
                file_path = alt_path
            else:
                self.send_error_json(f"Mídia não encontrada: {filename}", 404)
                return

        file_size = os.path.getsize(file_path)
        mime_type, _ = mimetypes.guess_type(file_path)
        if not mime_type:
            mime_type = "video/mp4" if filename.lower().endswith('.mp4') else "application/octet-stream"

        range_header = self.headers.get('Range', None)
        if range_header:
            # Suporte a HTTP Range para streaming de vídeo no Android / iOS
            try:
                byte_range = range_header.strip().split('=')[1]
                start_str, end_str = byte_range.split('-')
                start = int(start_str) if start_str else 0
                end = int(end_str) if end_str else file_size - 1
                length = end - start + 1

                self.send_response(206)
                self.send_header("Content-Type", mime_type)
                self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
                self.send_header("Content-Length", str(length))
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()

                with open(file_path, 'rb') as f:
                    f.seek(start)
                    self.wfile.write(f.read(length))
                return
            except Exception as e:
                pass

        # Resposta 200 completa
        self.send_response(200)
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Length", str(file_size))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        with open(file_path, 'rb') as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def serve_static(self, path):
        clean_path = path.lstrip('/')
        if not clean_path or clean_path in ('admin', 'index.html'):
            clean_path = 'index.html'

        if clean_path in ('player', 'player/'):
            clean_path = 'player/index.html'

        file_path = os.path.join(PUBLIC_DIR, clean_path)
        if not os.path.exists(file_path):
            self.send_error_json(f"Arquivo estático não encontrado: {clean_path}", 404)
            return

        mime_type, _ = mimetypes.guess_type(file_path)
        if not mime_type:
            if file_path.endswith('.css'): mime_type = 'text/css'
            elif file_path.endswith('.js'): mime_type = 'application/javascript'
            elif file_path.endswith('.html'): mime_type = 'text/html; charset=utf-8'
            elif file_path.endswith('.json'): mime_type = 'application/json'
            elif file_path.endswith('.svg'): mime_type = 'image/svg+xml'
            else: mime_type = 'application/octet-stream'

        with open(file_path, 'rb') as f:
            content = f.read()

        self.send_response(200)
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(content)

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

def run():
    server = ThreadedHTTPServer(('0.0.0.0', PORT), SignageWebHandler)
    print(f"================================================================")
    print(f"  🚀 DIGITAL SIGNAGE WEB CMS & SERVER RODANDO NA PORTA {PORT}")
    print(f"  👉 Painel Web CMS:   http://localhost:{PORT}/")
    print(f"  👉 Web Signage Player: http://localhost:{PORT}/player")
    print(f"================================================================")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[Servidor] Encerrando...")
        server.server_close()

if __name__ == '__main__':
    run()
