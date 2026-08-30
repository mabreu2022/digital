"""
Digital Signage Database Engine - Pure Python / SQLite Embedded with Firebird compatibility
Armazena dados de Telas, Mídias, Playlists, Agendamentos e Logs de Exibição.
"""

import sqlite3
import os
import json
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(__file__), 'digitalsign.db')

def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn

def init_db():
    conn = get_db()
    with conn:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS TELAS (
            ID INTEGER PRIMARY KEY AUTOINCREMENT,
            UUID VARCHAR(36) UNIQUE NOT NULL,
            NOME VARCHAR(100) NOT NULL,
            IP_LOCAL VARCHAR(45),
            IP_PUBLICO VARCHAR(45),
            MAC_ADDRESS VARCHAR(17),
            SISTEMA_OPERACIONAL VARCHAR(50),
            VERSAO_PLAYER VARCHAR(20),
            LARGURA_PX INTEGER DEFAULT 1920,
            ALTURA_PX INTEGER DEFAULT 1080,
            STATUS VARCHAR(20) DEFAULT 'ONLINE',
            VOLUME_AUDIO INTEGER DEFAULT 100,
            ESPACO_DISCO_LIVRE_MB BIGINT DEFAULT 0,
            ULTIMO_HEARTBEAT TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            CRIADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            ATUALIZADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS MIDIAS (
            ID INTEGER PRIMARY KEY AUTOINCREMENT,
            NOME_EXIBICAO VARCHAR(150) NOT NULL,
            NOME_ARQUIVO VARCHAR(255) NOT NULL,
            HASH_MD5 VARCHAR(32) UNIQUE NOT NULL,
            TAMANHO_BYTES BIGINT NOT NULL,
            TIPO_MIDIA VARCHAR(20) NOT NULL, -- 'VIDEO', 'IMAGE', 'STREAM'
            MIME_TYPE VARCHAR(100),
            DURACAO_PADRAO_SEG INTEGER DEFAULT 10,
            LARGURA_PX INTEGER DEFAULT 1920,
            ALTURA_PX INTEGER DEFAULT 1080,
            URL_DOWNLOAD VARCHAR(1000) NOT NULL,
            STATUS VARCHAR(20) DEFAULT 'READY',
            CRIADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            ATUALIZADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS PLAYLISTS (
            ID INTEGER PRIMARY KEY AUTOINCREMENT,
            NOME VARCHAR(100) NOT NULL,
            DESCRICAO VARCHAR(255),
            IS_PADRAO INTEGER DEFAULT 0,
            ATIVA INTEGER DEFAULT 1,
            CRIADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            ATUALIZADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS PLAYLIST_ITENS (
            ID INTEGER PRIMARY KEY AUTOINCREMENT,
            PLAYLIST_ID INTEGER NOT NULL REFERENCES PLAYLISTS(ID) ON DELETE CASCADE,
            MIDIA_ID INTEGER NOT NULL REFERENCES MIDIAS(ID) ON DELETE CASCADE,
            ORDEM INTEGER NOT NULL,
            DURACAO_SEG INTEGER NOT NULL,
            TRANSICAO VARCHAR(20) DEFAULT 'CUT',
            CRIADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS AGENDAMENTOS (
            ID INTEGER PRIMARY KEY AUTOINCREMENT,
            NOME_EVENTO VARCHAR(100) NOT NULL,
            PLAYLIST_ID INTEGER NOT NULL REFERENCES PLAYLISTS(ID) ON DELETE CASCADE,
            TELA_ID INTEGER REFERENCES TELAS(ID) ON DELETE SET NULL,
            DATA_INICIO DATE NOT NULL,
            DATA_FIM DATE NOT NULL,
            HORA_INICIO TIME NOT NULL,
            HORA_FIM TIME NOT NULL,
            DIAS_SEMANA VARCHAR(20) DEFAULT '1,2,3,4,5,6,7',
            PRIORIDADE INTEGER DEFAULT 10,
            ATIVO INTEGER DEFAULT 1,
            CRIADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            ATUALIZADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS LOGS_EXIBICAO (
            ID INTEGER PRIMARY KEY AUTOINCREMENT,
            TELA_ID INTEGER REFERENCES TELAS(ID) ON DELETE SET NULL,
            MIDIA_ID INTEGER REFERENCES MIDIAS(ID) ON DELETE SET NULL,
            PLAYLIST_ID INTEGER REFERENCES PLAYLISTS(ID) ON DELETE SET NULL,
            DATA_HORA_INICIO TIMESTAMP NOT NULL,
            DATA_HORA_FIM TIMESTAMP NOT NULL,
            SEGUNDOS_EXIBIDOS INTEGER NOT NULL,
            STATUS_EXIBICAO VARCHAR(20) DEFAULT 'COMPLETED',
            MENSAGEM_ERRO VARCHAR(255),
            CRIADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """)

        # Insere dados padrão caso o banco esteja vazio
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM PLAYLISTS")
        if cur.fetchone()[0] == 0:
            # Seed Mídias
            cur.execute("""
                INSERT INTO MIDIAS (NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, TIPO_MIDIA, MIME_TYPE, DURACAO_PADRAO_SEG, URL_DOWNLOAD)
                VALUES 
                ('Comercial em Vídeo 1 (HD)', 'video_comercial_1.mp4', 'e4d909c290d0fb1ca068ffaddf22cbd0', 1150000, 'VIDEO', 'video/mp4', 10, '/media/video_comercial_1.mp4'),
                ('Banner Institucional 2026', 'banner_demo.jpg', 'c81e728d9d4c2f636f067f89cc14862c', 88000, 'IMAGE', 'image/jpeg', 8, '/media/banner_demo.jpg'),
                ('YouTube - EFpIdBsq-jY', 'youtube_EFpIdBsq-jY', '1a79a4d60de6718e8e5b326e338ae533', 0, 'STREAM', 'video/youtube', 360, 'https://www.youtube.com/watch?v=EFpIdBsq-jY'),
                ('YouTube - eZuH0S_-PwQ', 'youtube_eZuH0S_-PwQ', 'eccbc87e4b5ce2fe28308fd9f2a7baf3', 0, 'STREAM', 'video/youtube', 0, 'https://www.youtube.com/watch?v=eZuH0S_-PwQ')
            """)
            
            # Seed Playlists
            cur.execute("INSERT INTO PLAYLISTS (NOME, DESCRICAO, IS_PADRAO, ATIVA) VALUES ('Grade Geral', 'Playlist Padrão de Fallback', 1, 1)")
            pl_geral = cur.lastrowid
            cur.execute("INSERT INTO PLAYLISTS (NOME, DESCRICAO, IS_PADRAO, ATIVA) VALUES ('Tarde', 'Programação para Android', 0, 1)")
            pl_tarde = cur.lastrowid
            cur.execute("INSERT INTO PLAYLISTS (NOME, DESCRICAO, IS_PADRAO, ATIVA) VALUES ('hoje', 'Programação para PC Linux (YouTube)', 0, 1)")
            pl_hoje = cur.lastrowid

            # Itens das Playlists
            cur.execute("INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_SEG, TRANSICAO) VALUES (?, 1, 1, 10, 'CUT')", (pl_geral,))
            cur.execute("INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_SEG, TRANSICAO) VALUES (?, 2, 2, 8, 'FADE')", (pl_geral,))

            cur.execute("INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_SEG, TRANSICAO) VALUES (?, 1, 1, 10, 'CUT')", (pl_tarde,))

            cur.execute("INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_SEG, TRANSICAO) VALUES (?, 4, 1, 0, 'CUT')", (pl_hoje,))
            cur.execute("INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_SEG, TRANSICAO) VALUES (?, 3, 2, 360, 'FADE')", (pl_hoje,))

            # Telas
            cur.execute("INSERT INTO TELAS (UUID, NOME, IP_LOCAL, IP_PUBLICO, SISTEMA_OPERACIONAL, STATUS) VALUES ('0c95bd18-4eef-4bb7-8b1d-088568ea73bc', 'pc linux', '127.0.0.1', '127.0.0.1', 'WebBrowser (Chrome)', 'ONLINE')")
            tela_linux = cur.lastrowid
            cur.execute("INSERT INTO TELAS (UUID, NOME, IP_LOCAL, IP_PUBLICO, SISTEMA_OPERACIONAL, STATUS) VALUES ('a928dcb4-4c72-41ed-9fb2-095bbe7f6ab9', 'Android', '192.168.1.220', '187.75.162.220', 'Android TV / Chrome', 'ONLINE')")
            tela_android = cur.lastrowid

            # Agendamentos Direcionados por Tela
            cur.execute("""
                INSERT INTO AGENDAMENTOS (NOME_EVENTO, PLAYLIST_ID, TELA_ID, DATA_INICIO, DATA_FIM, HORA_INICIO, HORA_FIM, DIAS_SEMANA, PRIORIDADE, ATIVO)
                VALUES 
                ('pc linux', ?, ?, date('now'), date('now', '+1 year'), '00:00:00', '23:59:59', '1,2,3,4,5,6,7', 10, 1),
                ('Android', ?, ?, date('now'), date('now', '+1 year'), '00:00:00', '23:59:59', '1,2,3,4,5,6,7', 10, 1)
            """, (pl_hoje, tela_linux, pl_tarde, tela_android))

    conn.close()

# Inicializa ao importar
init_db()
