/*============================================================================
  SCRIPT DE CARGA INICIAL / SEED DE DADOS DE TESTE (FIREBIRD 5.0)
============================================================================*/

-- 1. Inserir Tela de Demonstração
INSERT INTO TELAS (
    UUID, NOME, IP_LOCAL, IP_PUBLICO, MAC_ADDRESS, SISTEMA_OPERACIONAL, VERSAO_PLAYER, STATUS, ULTIMO_HEARTBEAT
) VALUES (
    'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    'Display Hall de Entrada - Matriz',
    '192.168.1.105',
    '200.180.55.12',
    '00:1A:2B:3C:4D:5E',
    'Ubuntu 24.04 LTS (x86_64)',
    '1.0.0',
    'ONLINE',
    CURRENT_TIMESTAMP
);

-- 2. Inserir Mídias de Demonstração (Vídeos e Imagens)
INSERT INTO MIDIAS (
    NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, TIPO_MIDIA, MIME_TYPE, DURACAO_PADRAO_SEG, URL_DOWNLOAD
) VALUES (
    'Vídeo Institucional 2026',
    'video_institucional_2026.mp4',
    'e99a18c428cb38d5f260853678922e03',
    25400120,
    'VIDEO',
    'video/mp4',
    30,
    'http://cms.signage.corp/media/e99a18c428cb38d5f260853678922e03.mp4'
);

INSERT INTO MIDIAS (
    NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, TIPO_MIDIA, MIME_TYPE, DURACAO_PADRAO_SEG, URL_DOWNLOAD
) VALUES (
    'Aviso de Segurança do Trabalho',
    'banner_seguranca.jpg',
    '8b1a9953c4611296a827abf8c47804d7',
    1048576,
    'IMAGE',
    'image/jpeg',
    15,
    'http://cms.signage.corp/media/8b1a9953c4611296a827abf8c47804d7.jpg'
);

INSERT INTO MIDIAS (
    NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, TIPO_MIDIA, MIME_TYPE, DURACAO_PADRAO_SEG, URL_DOWNLOAD
) VALUES (
    'Cardápio do Restaurante Executivo',
    'cardapio_almoco.mp4',
    'c4ca4238a0b923820dcc509a6f75849b',
    15200000,
    'VIDEO',
    'video/mp4',
    20,
    'http://cms.signage.corp/media/c4ca4238a0b923820dcc509a6f75849b.mp4'
);

-- 3. Inserir Playlists
-- 3.1. Playlist Padrão de Fallback (Sempre roda quando não há campanhas pontuais)
INSERT INTO PLAYLISTS (NOME, DESCRICAO, IS_PADRAO, ATIVA) 
VALUES ('Playlist Padrão Geral', 'Conteúdo padrão de fallback quando não há eventos específicos', 1, 1);

-- 3.2. Playlist de Almoço (Campanha prioritária)
INSERT INTO PLAYLISTS (NOME, DESCRICAO, IS_PADRAO, ATIVA) 
VALUES ('Campanha Horário de Almoço', 'Exibição do cardápio e promoções das 11:30 às 14:00', 0, 1);

-- 4. Vincular Itens às Playlists
-- Itens da Playlist Padrão (ID 1)
INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_EXIBICAO_SEG, TRANSICAO)
VALUES (1, 1, 1, 30, 'CUT'); -- Vídeo Institucional

INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_EXIBICAO_SEG, TRANSICAO)
VALUES (1, 2, 2, 15, 'FADE'); -- Banner Segurança

-- Itens da Playlist de Almoço (ID 2)
INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_EXIBICAO_SEG, TRANSICAO)
VALUES (2, 3, 1, 20, 'CUT'); -- Cardápio Almoço

INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_EXIBICAO_SEG, TRANSICAO)
VALUES (2, 1, 2, 30, 'CUT'); -- Vídeo Institucional

-- 5. Inserir Agendamentos
-- Agendamento de Almoço de Segunda a Sexta ('0111110' -> Dom=0, Seg..Sex=1, Sab=0) com Prioridade 100
INSERT INTO AGENDAMENTOS (
    TELA_ID, PLAYLIST_ID, NOME_EVENTO, DATA_INICIO, DATA_FIM, HORA_INICIO, HORA_FIM, DIAS_SEMANA, PRIORIDADE, ATIVO
) VALUES (
    1,
    2,
    'Cardápio e Avisos de Almoço',
    '2026-01-01',
    '2026-12-31',
    '11:30:00',
    '14:00:00',
    '0111110',
    100,
    1
);

COMMIT;
