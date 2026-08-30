unit uDbQueries;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, sqldb, IBConnection, db, fpjson, jsonparser;

type
  { TSignageDbService - Serviços Completos de Banco de Dados Firebird 5.0 }
  TSignageDbService = class
  private
    class function FetchPlaylistItemsAsJson(APlaylistID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction; ARequiredMedias: TJSONArray): TJSONArray;
  public
    // 1. Dashboard
    class function GetDashboardStatsAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
    class function ListRecentLogsAsJson(ALimit: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): string;

    // 2. Telas
    class function ListScreensAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
    class function DeleteScreen(AScreenID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;

    // 3. Mídias
    class function ListMediasAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
    class function InsertMedia(const ANome, AArquivo, AMd5, ATipo, AMime, AUrl: string; ATamanho: Int64; ADuracao, ALargura, AAltura: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Int64;
    class function DeleteMedia(AMediaID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;

    // 4. Playlists
    class function ListPlaylistsAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
    class function GetPlaylistDetailsAsJson(APlaylistID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): string;
    class function CreatePlaylist(const ANome, ADescricao: string; AIsPadrao: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Int64;
    class function DeletePlaylist(APlaylistID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
    class function SetDefaultPlaylist(APlaylistID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
    class function AddPlaylistItem(APlaylistID, AMediaID: Int64; ADuracao: Integer; const ATransicao: string; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
    class function RemovePlaylistItem(AItemID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
    class function MovePlaylistItem(AItemID: Int64; ADirection: string; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;

    // 5. Agendamentos
    class function ListSchedulesAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
    class function CreateSchedule(const AEvento: string; APlaylistID, ATelaID: Int64; const ADataIni, ADataFim, AHoraIni, AHoraFim, ADias: string; APrioridade: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Int64;
    class function DeleteSchedule(AScheduleID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;

    // 6. Player API
    class function BuildPlayerSyncJson(const APlayerUUID: string; AConn: TIBConnection; ATrans: TSQLTransaction): string;
    class function RegisterPlayer(const AUUID, ANome, AIPLocal, AIPPublico, AMac, AOS, AVersao: string; ALargura, AAltura: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
    class function UpdatePlayerHeartbeat(const AUUID, AStatus, AVersao, ACurrentMedia: string; AFreeSpaceMB: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
    class function InsertBatchProofOfPlay(const APlayerUUID, AJsonBatch: string; AConn: TIBConnection; ATrans: TSQLTransaction): Integer;
  end;

implementation

{ TSignageDbService }

class function TSignageDbService.GetDashboardStatsAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
var
  Qry: TSQLQuery;
  Obj: TJSONObject;
  TotalScreens, OnlineScreens, PlaylistsCount, MediasCount, ProofCountToday: Int64;
  TotalStorageBytes: Int64;
begin
  Obj := TJSONObject.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;

    // Total Telas e Online
    Qry.SQL.Text := 'SELECT COUNT(*) AS TOTAL, ' +
                    'SUM(CASE WHEN ULTIMO_HEARTBEAT >= DATEADD(-2 MINUTE TO CURRENT_TIMESTAMP) THEN 1 ELSE 0 END) AS ONLINE_CNT ' +
                    'FROM TELAS';
    Qry.Open;
    TotalScreens := Qry.FieldByName('TOTAL').AsLargeInt;
    OnlineScreens := Qry.FieldByName('ONLINE_CNT').AsLargeInt;
    Qry.Close;

    // Total Playlists
    Qry.SQL.Text := 'SELECT COUNT(*) AS TOTAL FROM PLAYLISTS WHERE ATIVA = 1';
    Qry.Open;
    PlaylistsCount := Qry.FieldByName('TOTAL').AsLargeInt;
    Qry.Close;

    // Total Mídias e Espaço
    Qry.SQL.Text := 'SELECT COUNT(*) AS TOTAL, SUM(TAMANHO_BYTES) AS TOTAL_BYTES FROM MIDIAS WHERE STATUS = ''READY''';
    Qry.Open;
    MediasCount := Qry.FieldByName('TOTAL').AsLargeInt;
    TotalStorageBytes := Qry.FieldByName('TOTAL_BYTES').AsLargeInt;
    Qry.Close;

    // Exibições Hoje (Proof of Play)
    Qry.SQL.Text := 'SELECT COUNT(*) AS TOTAL FROM LOGS_EXIBICAO WHERE CAST(DATA_HORA_INICIO AS DATE) = CURRENT_DATE';
    Qry.Open;
    ProofCountToday := Qry.FieldByName('TOTAL').AsLargeInt;
    Qry.Close;

    Obj.Add('total_screens', TotalScreens);
    Obj.Add('online_screens', OnlineScreens);
    Obj.Add('offline_screens', TotalScreens - OnlineScreens);
    Obj.Add('active_playlists', PlaylistsCount);
    Obj.Add('total_medias', MediasCount);
    Obj.Add('storage_bytes', TotalStorageBytes);
    Obj.Add('storage_mb', FormatFloat('0.0', TotalStorageBytes / (1024 * 1024)));
    Obj.Add('proof_today', ProofCountToday);
    Obj.Add('server_time', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));

    Result := Obj.AsJSON;
  finally
    Qry.Free;
    Obj.Free;
  end;
end;

class function TSignageDbService.ListRecentLogsAsJson(ALimit: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): string;
var
  Qry: TSQLQuery;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  if ALimit <= 0 then ALimit := 50;
  Arr := TJSONArray.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := Format(
      'SELECT FIRST %d l.ID, l.DATA_HORA_INICIO, l.SEGUNDOS_EXIBIDOS, l.STATUS_EXIBICAO, ' +
      '       t.NOME AS TELA_NOME, m.NOME_EXIBICAO AS MIDIA_NOME, p.NOME AS PLAYLIST_NOME ' +
      'FROM LOGS_EXIBICAO l ' +
      'LEFT JOIN TELAS t ON t.ID = l.TELA_ID ' +
      'LEFT JOIN MIDIAS m ON m.ID = l.MIDIA_ID ' +
      'LEFT JOIN PLAYLISTS p ON p.ID = l.PLAYLIST_ID ' +
      'ORDER BY l.ID DESC', [ALimit]);
    Qry.Open;
    while not Qry.EOF do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', Qry.FieldByName('ID').AsLargeInt);
      if not Qry.FieldByName('DATA_HORA_INICIO').IsNull then
        Obj.Add('time', FormatDateTime('yyyy-mm-dd hh:nn:ss', Qry.FieldByName('DATA_HORA_INICIO').AsDateTime))
      else
        Obj.Add('time', '-');
      Obj.Add('screen', Qry.FieldByName('TELA_NOME').AsString);
      Obj.Add('media', Qry.FieldByName('MIDIA_NOME').AsString);
      Obj.Add('playlist', Qry.FieldByName('PLAYLIST_NOME').AsString);
      Obj.Add('duration', Qry.FieldByName('SEGUNDOS_EXIBIDOS').AsInteger);
      Obj.Add('status', Qry.FieldByName('STATUS_EXIBICAO').AsString);
      Arr.Add(Obj);
      Qry.Next;
    end;
    Result := Arr.AsJSON;
  finally
    Qry.Free;
    Arr.Free;
  end;
end;

class function TSignageDbService.ListScreensAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
var
  Qry: TSQLQuery;
  Arr: TJSONArray;
  Obj: TJSONObject;
  IsOnline: Boolean;
  LastHb: TDateTime;
begin
  Arr := TJSONArray.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'SELECT ID, UUID, NOME, IP_LOCAL, IP_PUBLICO, STATUS, SISTEMA_OPERACIONAL, ' +
                    '       VERSAO_PLAYER, VOLUME_AUDIO, ULTIMO_HEARTBEAT ' +
                    'FROM TELAS ORDER BY NOME';
    Qry.Open;
    while not Qry.EOF do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', Qry.FieldByName('ID').AsLargeInt);
      Obj.Add('uuid', Qry.FieldByName('UUID').AsString);
      Obj.Add('name', Qry.FieldByName('NOME').AsString);
      Obj.Add('ip_local', Qry.FieldByName('IP_LOCAL').AsString);
      Obj.Add('ip_publico', Qry.FieldByName('IP_PUBLICO').AsString);
      Obj.Add('os', Qry.FieldByName('SISTEMA_OPERACIONAL').AsString);
      Obj.Add('version', Qry.FieldByName('VERSAO_PLAYER').AsString);
      Obj.Add('volume', Qry.FieldByName('VOLUME_AUDIO').AsInteger);

      if not Qry.FieldByName('ULTIMO_HEARTBEAT').IsNull then
      begin
        LastHb := Qry.FieldByName('ULTIMO_HEARTBEAT').AsDateTime;
        Obj.Add('last_heartbeat', FormatDateTime('yyyy-mm-dd hh:nn:ss', LastHb));
        IsOnline := (Now - LastHb) < (2 / 1440); // 2 minutos
      end
      else
      begin
        Obj.Add('last_heartbeat', '-');
        IsOnline := False;
      end;

      if IsOnline then
        Obj.Add('status', 'ONLINE')
      else
        Obj.Add('status', 'OFFLINE');

      Arr.Add(Obj);
      Qry.Next;
    end;
    Result := Arr.AsJSON;
  finally
    Qry.Free;
    Arr.Free;
  end;
end;

class function TSignageDbService.DeleteScreen(AScreenID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'DELETE FROM LOGS_EXIBICAO WHERE TELA_ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AScreenID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM AGENDAMENTOS WHERE TELA_ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AScreenID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM TELAS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AScreenID;
    Qry.ExecSQL;

    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.ListMediasAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
var
  Qry: TSQLQuery;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  Arr := TJSONArray.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'SELECT ID, NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, ' +
                    '       TIPO_MIDIA, MIME_TYPE, DURACAO_PADRAO_SEG, LARGURA_PX, ALTURA_PX, URL_DOWNLOAD ' +
                    'FROM MIDIAS ORDER BY ID DESC';
    Qry.Open;
    while not Qry.EOF do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', Qry.FieldByName('ID').AsLargeInt);
      Obj.Add('name', Qry.FieldByName('NOME_EXIBICAO').AsString);
      Obj.Add('filename', Qry.FieldByName('NOME_ARQUIVO').AsString);
      Obj.Add('hash_md5', Qry.FieldByName('HASH_MD5').AsString);
      Obj.Add('size_bytes', Qry.FieldByName('TAMANHO_BYTES').AsLargeInt);
      Obj.Add('type', Qry.FieldByName('TIPO_MIDIA').AsString);
      Obj.Add('mime_type', Qry.FieldByName('MIME_TYPE').AsString);
      Obj.Add('duration_sec', Qry.FieldByName('DURACAO_PADRAO_SEG').AsInteger);
      Obj.Add('width', Qry.FieldByName('LARGURA_PX').AsInteger);
      Obj.Add('height', Qry.FieldByName('ALTURA_PX').AsInteger);
      Obj.Add('url', Qry.FieldByName('URL_DOWNLOAD').AsString);
      Arr.Add(Obj);
      Qry.Next;
    end;
    Result := Arr.AsJSON;
  finally
    Qry.Free;
    Arr.Free;
  end;
end;

class function TSignageDbService.InsertMedia(const ANome, AArquivo, AMd5, ATipo, AMime, AUrl: string; ATamanho: Int64; ADuracao, ALargura, AAltura: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Int64;
var
  Qry: TSQLQuery;
begin
  Result := 0;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'INSERT INTO MIDIAS (' +
                    ' NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, TIPO_MIDIA, ' +
                    ' MIME_TYPE, DURACAO_PADRAO_SEG, LARGURA_PX, ALTURA_PX, URL_DOWNLOAD, STATUS' +
                    ') VALUES (' +
                    ' :NOME, :ARQ, :MD5, :TAM, :TIPO, :MIME, :DUR, :LARG, :ALT, :URL, ''READY''' +
                    ') RETURNING ID';
    Qry.ParamByName('NOME').AsString := ANome;
    Qry.ParamByName('ARQ').AsString := AArquivo;
    Qry.ParamByName('MD5').AsString := AMd5;
    Qry.ParamByName('TAM').AsLargeInt := ATamanho;
    Qry.ParamByName('TIPO').AsString := ATipo;
    Qry.ParamByName('MIME').AsString := AMime;
    Qry.ParamByName('DUR').AsInteger := ADuracao;
    Qry.ParamByName('LARG').AsInteger := ALargura;
    Qry.ParamByName('ALT').AsInteger := AAltura;
    Qry.ParamByName('URL').AsString := AUrl;
    Qry.Open;
    if not Qry.EOF then
      Result := Qry.FieldByName('ID').AsLargeInt;
    Qry.Close;
    ATrans.CommitRetaining;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.DeleteMedia(AMediaID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'DELETE FROM PLAYLIST_ITENS WHERE MIDIA_ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AMediaID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM LOGS_EXIBICAO WHERE MIDIA_ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AMediaID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM MIDIAS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AMediaID;
    Qry.ExecSQL;

    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.ListPlaylistsAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
var
  Qry: TSQLQuery;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  Arr := TJSONArray.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'SELECT p.ID, p.NOME, p.DESCRICAO, p.IS_PADRAO, p.ATIVA, ' +
                    '       COUNT(pi.ID) AS TOTAL_ITENS, COALESCE(SUM(pi.DURACAO_SEG), 0) AS DURACAO_TOTAL ' +
                    'FROM PLAYLISTS p ' +
                    'LEFT JOIN PLAYLIST_ITENS pi ON pi.PLAYLIST_ID = p.ID ' +
                    'GROUP BY p.ID, p.NOME, p.DESCRICAO, p.IS_PADRAO, p.ATIVA ' +
                    'ORDER BY p.ID ASC';
    Qry.Open;
    while not Qry.EOF do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', Qry.FieldByName('ID').AsLargeInt);
      Obj.Add('name', Qry.FieldByName('NOME').AsString);
      Obj.Add('description', Qry.FieldByName('DESCRICAO').AsString);
      Obj.Add('is_default', Qry.FieldByName('IS_PADRAO').AsInteger);
      Obj.Add('is_active', Qry.FieldByName('ATIVA').AsInteger);
      Obj.Add('items_count', Qry.FieldByName('TOTAL_ITENS').AsInteger);
      Obj.Add('total_duration_sec', Qry.FieldByName('DURACAO_TOTAL').AsInteger);
      Arr.Add(Obj);
      Qry.Next;
    end;
    Result := Arr.AsJSON;
  finally
    Qry.Free;
    Arr.Free;
  end;
end;

class function TSignageDbService.GetPlaylistDetailsAsJson(APlaylistID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): string;
var
  Qry: TSQLQuery;
  RootObj: TJSONObject;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;

    Qry.SQL.Text := 'SELECT ID, NOME, DESCRICAO, IS_PADRAO, ATIVA FROM PLAYLISTS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := APlaylistID;
    Qry.Open;
    if not Qry.EOF then
    begin
      RootObj.Add('id', Qry.FieldByName('ID').AsLargeInt);
      RootObj.Add('name', Qry.FieldByName('NOME').AsString);
      RootObj.Add('description', Qry.FieldByName('DESCRICAO').AsString);
      RootObj.Add('is_default', Qry.FieldByName('IS_PADRAO').AsInteger);
      RootObj.Add('is_active', Qry.FieldByName('ATIVA').AsInteger);
    end;
    Qry.Close;

    Qry.SQL.Text := 'SELECT pi.ID AS ITEM_ID, pi.ORDEM, pi.DURACAO_SEG, pi.TRANSICAO, ' +
                    '       m.ID AS MIDIA_ID, m.NOME_EXIBICAO, m.NOME_ARQUIVO, m.TIPO_MIDIA, m.URL_DOWNLOAD ' +
                    'FROM PLAYLIST_ITENS pi ' +
                    'JOIN MIDIAS m ON m.ID = pi.MIDIA_ID ' +
                    'WHERE pi.PLAYLIST_ID = :ID ' +
                    'ORDER BY pi.ORDEM ASC';
    Qry.ParamByName('ID').AsLargeInt := APlaylistID;
    Qry.Open;
    while not Qry.EOF do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('item_id', Qry.FieldByName('ITEM_ID').AsLargeInt);
      Obj.Add('order', Qry.FieldByName('ORDEM').AsInteger);
      Obj.Add('duration_sec', Qry.FieldByName('DURACAO_SEG').AsInteger);
      Obj.Add('transition', Qry.FieldByName('TRANSICAO').AsString);
      Obj.Add('media_id', Qry.FieldByName('MIDIA_ID').AsLargeInt);
      Obj.Add('media_name', Qry.FieldByName('NOME_EXIBICAO').AsString);
      Obj.Add('filename', Qry.FieldByName('NOME_ARQUIVO').AsString);
      Obj.Add('type', Qry.FieldByName('TIPO_MIDIA').AsString);
      Obj.Add('url', Qry.FieldByName('URL_DOWNLOAD').AsString);
      Arr.Add(Obj);
      Qry.Next;
    end;
    RootObj.Add('items', Arr);
    Result := RootObj.AsJSON;
  finally
    Qry.Free;
    RootObj.Free;
  end;
end;

class function TSignageDbService.CreatePlaylist(const ANome, ADescricao: string; AIsPadrao: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Int64;
var
  Qry: TSQLQuery;
begin
  Result := 0;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;

    if AIsPadrao = 1 then
    begin
      Qry.SQL.Text := 'UPDATE PLAYLISTS SET IS_PADRAO = 0';
      Qry.ExecSQL;
    end;

    Qry.SQL.Text := 'INSERT INTO PLAYLISTS (NOME, DESCRICAO, IS_PADRAO, ATIVA) ' +
                    'VALUES (:NOME, :DESC, :PADRAO, 1) RETURNING ID';
    Qry.ParamByName('NOME').AsString := ANome;
    Qry.ParamByName('DESC').AsString := ADescricao;
    Qry.ParamByName('PADRAO').AsInteger := AIsPadrao;
    Qry.Open;
    if not Qry.EOF then
      Result := Qry.FieldByName('ID').AsLargeInt;
    Qry.Close;
    ATrans.CommitRetaining;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.DeletePlaylist(APlaylistID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;

    Qry.SQL.Text := 'DELETE FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := APlaylistID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM AGENDAMENTOS WHERE PLAYLIST_ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := APlaylistID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM PLAYLISTS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := APlaylistID;
    Qry.ExecSQL;

    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.SetDefaultPlaylist(APlaylistID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'UPDATE PLAYLISTS SET IS_PADRAO = 0';
    Qry.ExecSQL;

    Qry.SQL.Text := 'UPDATE PLAYLISTS SET IS_PADRAO = 1 WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := APlaylistID;
    Qry.ExecSQL;

    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.AddPlaylistItem(APlaylistID, AMediaID: Int64; ADuracao: Integer; const ATransicao: string; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
  NextOrder: Integer;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;

    Qry.SQL.Text := 'SELECT COALESCE(MAX(ORDEM), 0) + 1 AS NEXT_ORD FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = :PID';
    Qry.ParamByName('PID').AsLargeInt := APlaylistID;
    Qry.Open;
    NextOrder := Qry.FieldByName('NEXT_ORD').AsInteger;
    Qry.Close;

    Qry.SQL.Text := 'INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_SEG, TRANSICAO) ' +
                    'VALUES (:PID, :MID, :ORD, :DUR, :TRANS)';
    Qry.ParamByName('PID').AsLargeInt := APlaylistID;
    Qry.ParamByName('MID').AsLargeInt := AMediaID;
    Qry.ParamByName('ORD').AsInteger := NextOrder;
    Qry.ParamByName('DUR').AsInteger := ADuracao;
    if ATransicao <> '' then
      Qry.ParamByName('TRANS').AsString := ATransicao
    else
      Qry.ParamByName('TRANS').AsString := 'CUT';
    Qry.ExecSQL;

    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.RemovePlaylistItem(AItemID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'DELETE FROM PLAYLIST_ITENS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AItemID;
    Qry.ExecSQL;
    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.MovePlaylistItem(AItemID: Int64; ADirection: string; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
  PlID: Int64;
  CurOrder, TargetOrder: Integer;
  TargetItemID: Int64;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;

    Qry.SQL.Text := 'SELECT PLAYLIST_ID, ORDEM FROM PLAYLIST_ITENS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AItemID;
    Qry.Open;
    if Qry.EOF then Exit;
    PlID := Qry.FieldByName('PLAYLIST_ID').AsLargeInt;
    CurOrder := Qry.FieldByName('ORDEM').AsInteger;
    Qry.Close;

    if LowerCase(ADirection) = 'up' then
    begin
      Qry.SQL.Text := 'SELECT FIRST 1 ID, ORDEM FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = :PID AND ORDEM < :ORD ORDER BY ORDEM DESC';
    end
    else
    begin
      Qry.SQL.Text := 'SELECT FIRST 1 ID, ORDEM FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = :PID AND ORDEM > :ORD ORDER BY ORDEM ASC';
    end;
    Qry.ParamByName('PID').AsLargeInt := PlID;
    Qry.ParamByName('ORD').AsInteger := CurOrder;
    Qry.Open;
    if Qry.EOF then Exit;
    TargetItemID := Qry.FieldByName('ID').AsLargeInt;
    TargetOrder := Qry.FieldByName('ORDEM').AsInteger;
    Qry.Close;

    // Troca
    Qry.SQL.Text := 'UPDATE PLAYLIST_ITENS SET ORDEM = :ORD WHERE ID = :ID';
    Qry.ParamByName('ORD').AsInteger := TargetOrder;
    Qry.ParamByName('ID').AsLargeInt := AItemID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'UPDATE PLAYLIST_ITENS SET ORDEM = :ORD WHERE ID = :ID';
    Qry.ParamByName('ORD').AsInteger := CurOrder;
    Qry.ParamByName('ID').AsLargeInt := TargetItemID;
    Qry.ExecSQL;

    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.ListSchedulesAsJson(AConn: TIBConnection; ATrans: TSQLTransaction): string;
var
  Qry: TSQLQuery;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  Arr := TJSONArray.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'SELECT a.ID, a.NOME_EVENTO, a.PLAYLIST_ID, p.NOME AS PLAYLIST_NOME, ' +
                    '       a.TELA_ID, t.NOME AS TELA_NOME, t.IP_LOCAL AS TELA_IP, ' +
                    '       a.DATA_INICIO, a.DATA_FIM, a.HORA_INICIO, a.HORA_FIM, ' +
                    '       a.DIAS_SEMANA, a.PRIORIDADE, a.ATIVO ' +
                    'FROM AGENDAMENTOS a ' +
                    'JOIN PLAYLISTS p ON p.ID = a.PLAYLIST_ID ' +
                    'LEFT JOIN TELAS t ON t.ID = a.TELA_ID ' +
                    'ORDER BY a.PRIORIDADE DESC, a.ID DESC';
    Qry.Open;
    while not Qry.EOF do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', Qry.FieldByName('ID').AsLargeInt);
      Obj.Add('event_name', Qry.FieldByName('NOME_EVENTO').AsString);
      Obj.Add('playlist_id', Qry.FieldByName('PLAYLIST_ID').AsLargeInt);
      Obj.Add('playlist_name', Qry.FieldByName('PLAYLIST_NOME').AsString);

      if Qry.FieldByName('TELA_ID').IsNull or (Qry.FieldByName('TELA_ID').AsLargeInt = 0) then
      begin
        Obj.Add('tela_id', 0);
        Obj.Add('tela_target', '[TODAS AS TELAS - GLOBAL]');
      end
      else
      begin
        Obj.Add('tela_id', Qry.FieldByName('TELA_ID').AsLargeInt);
        Obj.Add('tela_target', Qry.FieldByName('TELA_NOME').AsString + ' (' + Qry.FieldByName('TELA_IP').AsString + ')');
      end;

      if not Qry.FieldByName('DATA_INICIO').IsNull then
        Obj.Add('start_date', FormatDateTime('yyyy-mm-dd', Qry.FieldByName('DATA_INICIO').AsDateTime))
      else
        Obj.Add('start_date', '');

      if not Qry.FieldByName('DATA_FIM').IsNull then
        Obj.Add('end_date', FormatDateTime('yyyy-mm-dd', Qry.FieldByName('DATA_FIM').AsDateTime))
      else
        Obj.Add('end_date', '');

      if not Qry.FieldByName('HORA_INICIO').IsNull then
        Obj.Add('start_time', FormatDateTime('hh:nn:ss', Qry.FieldByName('HORA_INICIO').AsDateTime))
      else
        Obj.Add('start_time', '');

      if not Qry.FieldByName('HORA_FIM').IsNull then
        Obj.Add('end_time', FormatDateTime('hh:nn:ss', Qry.FieldByName('HORA_FIM').AsDateTime))
      else
        Obj.Add('end_time', '');

      Obj.Add('days_of_week', Qry.FieldByName('DIAS_SEMANA').AsString);
      Obj.Add('priority', Qry.FieldByName('PRIORIDADE').AsInteger);
      Obj.Add('is_active', Qry.FieldByName('ATIVO').AsInteger);

      Arr.Add(Obj);
      Qry.Next;
    end;
    Result := Arr.AsJSON;
  finally
    Qry.Free;
    Arr.Free;
  end;
end;

class function TSignageDbService.CreateSchedule(const AEvento: string; APlaylistID, ATelaID: Int64; const ADataIni, ADataFim, AHoraIni, AHoraFim, ADias: string; APrioridade: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Int64;
var
  Qry: TSQLQuery;
begin
  Result := 0;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;

    if ATelaID > 0 then
    begin
      Qry.SQL.Text := 'INSERT INTO AGENDAMENTOS (' +
                      ' NOME_EVENTO, PLAYLIST_ID, TELA_ID, DATA_INICIO, DATA_FIM, HORA_INICIO, HORA_FIM, DIAS_SEMANA, PRIORIDADE, ATIVO' +
                      ') VALUES (' +
                      ' :NOME, :PID, :TELA, :DINI, :DFIM, :HINI, :HFIM, :DIAS, :PRIO, 1' +
                      ') RETURNING ID';
      Qry.ParamByName('TELA').AsLargeInt := ATelaID;
    end
    else
    begin
      Qry.SQL.Text := 'INSERT INTO AGENDAMENTOS (' +
                      ' NOME_EVENTO, PLAYLIST_ID, TELA_ID, DATA_INICIO, DATA_FIM, HORA_INICIO, HORA_FIM, DIAS_SEMANA, PRIORIDADE, ATIVO' +
                      ') VALUES (' +
                      ' :NOME, :PID, NULL, :DINI, :DFIM, :HINI, :HFIM, :DIAS, :PRIO, 1' +
                      ') RETURNING ID';
    end;

    Qry.ParamByName('NOME').AsString := AEvento;
    Qry.ParamByName('PID').AsLargeInt := APlaylistID;
    Qry.ParamByName('DINI').AsDate := ScanDateTime('yyyy-mm-dd', ADataIni);
    Qry.ParamByName('DFIM').AsDate := ScanDateTime('yyyy-mm-dd', ADataFim);
    Qry.ParamByName('HINI').AsTime := ScanDateTime('hh:nn:ss', AHoraIni);
    Qry.ParamByName('HFIM').AsTime := ScanDateTime('hh:nn:ss', AHoraFim);
    Qry.ParamByName('DIAS').AsString := ADias;
    Qry.ParamByName('PRIO').AsInteger := APrioridade;
    Qry.Open;
    if not Qry.EOF then
      Result := Qry.FieldByName('ID').AsLargeInt;
    Qry.Close;
    ATrans.CommitRetaining;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.DeleteSchedule(AScheduleID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text := 'DELETE FROM AGENDAMENTOS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AScheduleID;
    Qry.ExecSQL;
    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.FetchPlaylistItemsAsJson(APlaylistID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction; ARequiredMedias: TJSONArray): TJSONArray;
var
  Qry: TSQLQuery;
  ItemObj, MediaObj: TJSONObject;
  MediaID: Int64;
  i: Integer;
  AlreadyInReq: Boolean;
begin
  Result := TJSONArray.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text :=
      'SELECT pi.ID AS ITEM_ID, pi.ORDEM, pi.DURACAO_SEG, pi.TRANSICAO, ' +
      '       m.ID AS MIDIA_ID, m.NOME_EXIBICAO, m.NOME_ARQUIVO, m.HASH_MD5, ' +
      '       m.TAMANHO_BYTES, m.TIPO_MIDIA, m.MIME_TYPE, m.URL_DOWNLOAD ' +
      'FROM PLAYLIST_ITENS pi ' +
      'INNER JOIN MIDIAS m ON m.ID = pi.MIDIA_ID ' +
      'WHERE pi.PLAYLIST_ID = :PLAYLIST_ID AND m.STATUS = ''READY'' ' +
      'ORDER BY pi.ORDEM ASC';
    Qry.ParamByName('PLAYLIST_ID').AsLargeInt := APlaylistID;
    Qry.Open;

    while not Qry.EOF do
    begin
      MediaID := Qry.FieldByName('MIDIA_ID').AsLargeInt;

      ItemObj := TJSONObject.Create;
      ItemObj.Add('item_id', Qry.FieldByName('ITEM_ID').AsLargeInt);
      ItemObj.Add('order', Qry.FieldByName('ORDEM').AsInteger);
      ItemObj.Add('media_id', MediaID);
      ItemObj.Add('media_name', Qry.FieldByName('NOME_EXIBICAO').AsString);
      ItemObj.Add('filename', Qry.FieldByName('NOME_ARQUIVO').AsString);
      ItemObj.Add('hash_md5', Qry.FieldByName('HASH_MD5').AsString);
      ItemObj.Add('type', Qry.FieldByName('TIPO_MIDIA').AsString);
      ItemObj.Add('duration_sec', Qry.FieldByName('DURACAO_SEG').AsInteger);
      ItemObj.Add('transition', Qry.FieldByName('TRANSICAO').AsString);
      ItemObj.Add('download_url', Qry.FieldByName('URL_DOWNLOAD').AsString);
      Result.Add(ItemObj);

      if ARequiredMedias <> nil then
      begin
        AlreadyInReq := False;
        for i := 0 to ARequiredMedias.Count - 1 do
        begin
          if ARequiredMedias.Objects[i].Get('id', Int64(0)) = MediaID then
          begin
            AlreadyInReq := True;
            Break;
          end;
        end;

        if not AlreadyInReq then
        begin
          MediaObj := TJSONObject.Create;
          MediaObj.Add('id', MediaID);
          MediaObj.Add('filename', Qry.FieldByName('NOME_ARQUIVO').AsString);
          MediaObj.Add('hash_md5', Qry.FieldByName('HASH_MD5').AsString);
          MediaObj.Add('size_bytes', Qry.FieldByName('TAMANHO_BYTES').AsLargeInt);
          MediaObj.Add('mime_type', Qry.FieldByName('MIME_TYPE').AsString);
          MediaObj.Add('download_url', Qry.FieldByName('URL_DOWNLOAD').AsString);
          ARequiredMedias.Add(MediaObj);
        end;
      end;

      Qry.Next;
    end;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.BuildPlayerSyncJson(const APlayerUUID: string; AConn: TIBConnection; ATrans: TSQLTransaction): string;
var
  QryPlayer, QryFallback, QrySchedules: TSQLQuery;
  RootObj, FallbackPlObj, SchedObj, SchedPlObj: TJSONObject;
  SchedArr, RequiredMediasArr: TJSONArray;
  PlayerID, FallbackPlID, SchedPlID: Int64;
begin
  RootObj := TJSONObject.Create;
  SchedArr := TJSONArray.Create;
  RequiredMediasArr := TJSONArray.Create;

  QryPlayer := TSQLQuery.Create(nil);
  QryFallback := TSQLQuery.Create(nil);
  QrySchedules := TSQLQuery.Create(nil);

  try
    QryPlayer.Database := AConn;
    QryPlayer.Transaction := ATrans;
    QryFallback.Database := AConn;
    QryFallback.Transaction := ATrans;
    QrySchedules.Database := AConn;
    QrySchedules.Transaction := ATrans;

    // 1. Identificar Tela
    QryPlayer.SQL.Text := 'SELECT ID, UUID, NOME, STATUS, VOLUME_AUDIO FROM TELAS WHERE UUID = :UUID';
    QryPlayer.ParamByName('UUID').AsString := APlayerUUID;
    QryPlayer.Open;

    if QryPlayer.EOF then
    begin
      // Fallback de busca por NOME ou ID
      QryPlayer.Close;
      QryPlayer.SQL.Text := 'SELECT ID, UUID, NOME, STATUS, VOLUME_AUDIO FROM TELAS WHERE NOME = :UUID OR ID = :UUID_ID';
      QryPlayer.ParamByName('UUID').AsString := APlayerUUID;
      QryPlayer.ParamByName('UUID_ID').AsLargeInt := StrToInt64Def(APlayerUUID, -1);
      QryPlayer.Open;
    end;

    if QryPlayer.EOF then
    begin
      // Auto-registro transparente
      QryPlayer.Close;
      QryPlayer.SQL.Text := 'INSERT INTO TELAS (UUID, NOME, IP_LOCAL, IP_PUBLICO, STATUS, ULTIMO_HEARTBEAT) ' +
                            'VALUES (:UUID, :NOME, ''127.0.0.1'', ''127.0.0.1'', ''ONLINE'', CURRENT_TIMESTAMP) ' +
                            'RETURNING ID, UUID, NOME, STATUS, VOLUME_AUDIO';
      QryPlayer.ParamByName('UUID').AsString := APlayerUUID;
      QryPlayer.ParamByName('NOME').AsString := 'Web Player ' + Copy(APlayerUUID, 1, 8);
      QryPlayer.Open;
      ATrans.CommitRetaining;
    end;

    PlayerID := QryPlayer.FieldByName('ID').AsLargeInt;
    RootObj.Add('status', 'ok');
    RootObj.Add('server_time', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
    RootObj.Add('player_id', PlayerID);
    RootObj.Add('player_uuid', QryPlayer.FieldByName('UUID').AsString);
    RootObj.Add('player_name', QryPlayer.FieldByName('NOME').AsString);
    RootObj.Add('volume', QryPlayer.FieldByName('VOLUME_AUDIO').AsInteger);

    // 2. Agendamentos Específicos por Tela
    QrySchedules.SQL.Text :=
      'SELECT A.ID AS SCHED_ID, A.NOME_EVENTO, A.DATA_INICIO, A.DATA_FIM, ' +
      '       A.HORA_INICIO, A.HORA_FIM, A.DIAS_SEMANA, A.PRIORIDADE, ' +
      '       P.ID AS PLAYLIST_ID, P.NOME AS PLAYLIST_NOME ' +
      'FROM AGENDAMENTOS A ' +
      'INNER JOIN PLAYLISTS P ON P.ID = A.PLAYLIST_ID ' +
      'LEFT JOIN TELAS T_SCHED ON T_SCHED.ID = A.TELA_ID ' +
      'WHERE ( ' +
      '       A.TELA_ID = :TELA_ID ' +
      '    OR LOWER(TRIM(T_SCHED.NOME)) = LOWER(TRIM(:PNAME)) ' +
      '    OR LOWER(TRIM(A.NOME_EVENTO)) = LOWER(TRIM(:PNAME)) ' +
      '    OR (A.TELA_ID IS NULL AND NOT EXISTS ( ' +
      '       SELECT 1 FROM AGENDAMENTOS A2 ' +
      '       LEFT JOIN TELAS T2 ON T2.ID = A2.TELA_ID ' +
      '       WHERE (A2.TELA_ID = :TELA_ID OR LOWER(TRIM(T2.NOME)) = LOWER(TRIM(:PNAME)) OR LOWER(TRIM(A2.NOME_EVENTO)) = LOWER(TRIM(:PNAME))) ' +
      '         AND A2.ATIVO = 1 AND A2.DATA_FIM >= CURRENT_DATE)) ' +
      ') ' +
      '  AND A.ATIVO = 1 ' +
      '  AND P.ATIVA = 1 ' +
      '  AND A.DATA_FIM >= CURRENT_DATE ' +
      'ORDER BY A.PRIORIDADE DESC, A.ID ASC';
    QrySchedules.ParamByName('TELA_ID').AsLargeInt := PlayerID;
    QrySchedules.ParamByName('PNAME').AsString := QryPlayer.FieldByName('NOME').AsString;
    QrySchedules.Open;
    QryPlayer.Close;

    // 3. Playlist Padrão de Fallback
    QryFallback.SQL.Text :=
      'SELECT ID, NOME, DESCRICAO, IS_PADRAO ' +
      'FROM PLAYLISTS ' +
      'WHERE IS_PADRAO = 1 AND ATIVA = 1 ' +
      'ROWS 1';
    QryFallback.Open;

    if not QryFallback.EOF then
    begin
      FallbackPlID := QryFallback.FieldByName('ID').AsLargeInt;
      FallbackPlObj := TJSONObject.Create;
      FallbackPlObj.Add('id', FallbackPlID);
      FallbackPlObj.Add('name', QryFallback.FieldByName('NOME').AsString);
      FallbackPlObj.Add('is_default', 1);
      FallbackPlObj.Add('items', FetchPlaylistItemsAsJson(FallbackPlID, AConn, ATrans, RequiredMediasArr));
      RootObj.Add('fallback_playlist', FallbackPlObj);
    end
    else
    begin
      FallbackPlObj := TJSONObject.Create;
      FallbackPlObj.Add('id', 0);
      FallbackPlObj.Add('name', 'Nenhuma');
      FallbackPlObj.Add('is_default', 1);
      FallbackPlObj.Add('items', TJSONArray.Create);
      RootObj.Add('fallback_playlist', FallbackPlObj);
    end;
    QryFallback.Close;

    while not QrySchedules.EOF do
    begin
      SchedPlID := QrySchedules.FieldByName('PLAYLIST_ID').AsLargeInt;

      SchedObj := TJSONObject.Create;
      SchedObj.Add('id', QrySchedules.FieldByName('SCHED_ID').AsLargeInt);
      SchedObj.Add('event_name', QrySchedules.FieldByName('NOME_EVENTO').AsString);
      SchedObj.Add('priority', QrySchedules.FieldByName('PRIORIDADE').AsInteger);

      if not QrySchedules.FieldByName('DATA_INICIO').IsNull then
        SchedObj.Add('start_date', FormatDateTime('yyyy-mm-dd', QrySchedules.FieldByName('DATA_INICIO').AsDateTime))
      else
        SchedObj.Add('start_date', FormatDateTime('yyyy-mm-dd', Date));

      if not QrySchedules.FieldByName('DATA_FIM').IsNull then
        SchedObj.Add('end_date', FormatDateTime('yyyy-mm-dd', QrySchedules.FieldByName('DATA_FIM').AsDateTime))
      else
        SchedObj.Add('end_date', FormatDateTime('yyyy-mm-dd', Date + 365));

      if not QrySchedules.FieldByName('HORA_INICIO').IsNull then
        SchedObj.Add('start_time', FormatDateTime('hh:nn:ss', QrySchedules.FieldByName('HORA_INICIO').AsDateTime))
      else
        SchedObj.Add('start_time', '00:00:00');

      if not QrySchedules.FieldByName('HORA_FIM').IsNull then
        SchedObj.Add('end_time', FormatDateTime('hh:nn:ss', QrySchedules.FieldByName('HORA_FIM').AsDateTime))
      else
        SchedObj.Add('end_time', '23:59:59');

      SchedObj.Add('days_of_week', QrySchedules.FieldByName('DIAS_SEMANA').AsString);

      // Detalhes da Playlist
      SchedPlObj := TJSONObject.Create;
      SchedPlObj.Add('id', SchedPlID);
      SchedPlObj.Add('name', QrySchedules.FieldByName('PLAYLIST_NOME').AsString);
      SchedPlObj.Add('is_default', 0);
      SchedPlObj.Add('items', FetchPlaylistItemsAsJson(SchedPlID, AConn, ATrans, RequiredMediasArr));
      SchedObj.Add('playlist', SchedPlObj);

      SchedArr.Add(SchedObj);
      QrySchedules.Next;
    end;
    QrySchedules.Close;

    RootObj.Add('schedules', SchedArr);
    RootObj.Add('required_medias', RequiredMediasArr);

    Result := RootObj.AsJSON;
  finally
    QryPlayer.Free;
    QryFallback.Free;
    QrySchedules.Free;
    RootObj.Free;
  end;
end;

class function TSignageDbService.RegisterPlayer(const AUUID, ANome, AIPLocal, AIPPublico, AMac, AOS, AVersao: string; ALargura, AAltura: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text :=
      'UPDATE OR INSERT INTO TELAS (' +
      '  UUID, NOME, IP_LOCAL, IP_PUBLICO, MAC_ADDRESS, SISTEMA_OPERACIONAL, ' +
      '  VERSAO_PLAYER, LARGURA_PX, ALTURA_PX, STATUS, ULTIMO_HEARTBEAT ' +
      ') VALUES (' +
      '  :UUID, :NOME, :IP_LOCAL, :IP_PUBLICO, :MAC_ADDRESS, :SISTEMA_OPERACIONAL, ' +
      '  :VERSAO_PLAYER, :LARGURA_PX, :ALTURA_PX, ''ONLINE'', CURRENT_TIMESTAMP ' +
      ') MATCHING (UUID)';

    Qry.ParamByName('UUID').AsString := AUUID;
    Qry.ParamByName('NOME').AsString := ANome;
    Qry.ParamByName('IP_LOCAL').AsString := AIPLocal;
    Qry.ParamByName('IP_PUBLICO').AsString := AIPPublico;
    Qry.ParamByName('MAC_ADDRESS').AsString := AMac;
    Qry.ParamByName('SISTEMA_OPERACIONAL').AsString := AOS;
    Qry.ParamByName('VERSAO_PLAYER').AsString := AVersao;
    Qry.ParamByName('LARGURA_PX').AsInteger := ALargura;
    Qry.ParamByName('ALTURA_PX').AsInteger := AAltura;

    Qry.ExecSQL;
    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.UpdatePlayerHeartbeat(const AUUID, AStatus, AVersao, ACurrentMedia: string; AFreeSpaceMB: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text :=
      'UPDATE TELAS SET ' +
      '  STATUS = :STATUS, ' +
      '  VERSAO_PLAYER = :VERSAO, ' +
      '  ESPACO_DISCO_LIVRE_MB = :FREE_MB, ' +
      '  ULTIMO_HEARTBEAT = CURRENT_TIMESTAMP ' +
      'WHERE UUID = :UUID';

    Qry.ParamByName('STATUS').AsString := AStatus;
    Qry.ParamByName('VERSAO').AsString := AVersao;
    Qry.ParamByName('FREE_MB').AsLargeInt := AFreeSpaceMB;
    Qry.ParamByName('UUID').AsString := AUUID;

    Qry.ExecSQL;
    ATrans.CommitRetaining;
    Result := True;
  finally
    Qry.Free;
  end;
end;

class function TSignageDbService.InsertBatchProofOfPlay(const APlayerUUID, AJsonBatch: string; AConn: TIBConnection; ATrans: TSQLTransaction): Integer;
var
  Parser: TJSONParser;
  RootArr: TJSONArray;
  ItemObj: TJSONObject;
  QryPlayer, QryInsert: TSQLQuery;
  PlayerID: Int64;
  i, InsertedCount: Integer;
  StartStr, EndStr: string;
begin
  Result := 0;
  InsertedCount := 0;

  QryPlayer := TSQLQuery.Create(nil);
  QryInsert := TSQLQuery.Create(nil);
  Parser := TJSONParser.Create(AJsonBatch, True);

  try
    QryPlayer.Database := AConn;
    QryPlayer.Transaction := ATrans;
    QryInsert.Database := AConn;
    QryInsert.Transaction := ATrans;

    QryPlayer.SQL.Text := 'SELECT ID FROM TELAS WHERE UUID = :UUID';
    QryPlayer.ParamByName('UUID').AsString := APlayerUUID;
    QryPlayer.Open;

    if QryPlayer.EOF then Exit;
    PlayerID := QryPlayer.FieldByName('ID').AsLargeInt;
    QryPlayer.Close;

    RootArr := TJSONArray(Parser.Parse);
    if RootArr <> nil then
    begin
      try
        QryInsert.SQL.Text :=
          'INSERT INTO LOGS_EXIBICAO (' +
          '  TELA_ID, MIDIA_ID, PLAYLIST_ID, DATA_HORA_INICIO, DATA_HORA_FIM, ' +
          '  SEGUNDOS_EXIBIDOS, STATUS_EXIBICAO, MENSAGEM_ERRO' +
          ') VALUES (' +
          '  :TELA_ID, :MIDIA_ID, :PLAYLIST_ID, :DATA_HORA_INICIO, :DATA_HORA_FIM, ' +
          '  :SEGUNDOS_EXIBIDOS, :STATUS_EXIBICAO, :MENSAGEM_ERRO' +
          ')';

        for i := 0 to RootArr.Count - 1 do
        begin
          ItemObj := RootArr.Objects[i];
          StartStr := ItemObj.Get('start_time', '2026-01-01T00:00:00');
          EndStr := ItemObj.Get('end_time', '2026-01-01T00:00:00');

          QryInsert.ParamByName('TELA_ID').AsLargeInt := PlayerID;
          QryInsert.ParamByName('MIDIA_ID').AsLargeInt := ItemObj.Get('media_id', Int64(0));
          QryInsert.ParamByName('PLAYLIST_ID').AsLargeInt := ItemObj.Get('playlist_id', Int64(0));
          QryInsert.ParamByName('DATA_HORA_INICIO').AsDateTime := ScanDateTime('yyyy-mm-dd"T"hh:nn:ss', StartStr);
          QryInsert.ParamByName('DATA_HORA_FIM').AsDateTime := ScanDateTime('yyyy-mm-dd"T"hh:nn:ss', EndStr);
          QryInsert.ParamByName('SEGUNDOS_EXIBIDOS').AsInteger := ItemObj.Get('seconds_played', 0);
          QryInsert.ParamByName('STATUS_EXIBICAO').AsString := ItemObj.Get('status', 'COMPLETED');
          QryInsert.ParamByName('MENSAGEM_ERRO').AsString := ItemObj.Get('error_message', '');

          QryInsert.ExecSQL;
          Inc(InsertedCount);
        end;

        ATrans.CommitRetaining;
        Result := InsertedCount;
      finally
        RootArr.Free;
      end;
    end;
  finally
    Parser.Free;
    QryPlayer.Free;
    QryInsert.Free;
  end;
end;

end.
