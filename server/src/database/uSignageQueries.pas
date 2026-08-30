unit uSignageQueries;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, sqldb, IBConnection, db, fpjson, jsonparser;

type
  { TSignageDatabaseService - Consultas Otimizadas para Firebird 5.0 }
  TSignageDatabaseService = class
  private
    class function FetchPlaylistItemsAsJson(APlaylistID: Int64; AConn: TIBConnection; ATrans: TSQLTransaction; ARequiredMedias: TJSONArray): TJSONArray;
  public
    // Gera o JSON completo de sincronização para a tela solicitada
    class function BuildPlayerSyncJson(const APlayerUUID: string; AConn: TIBConnection; ATrans: TSQLTransaction): string;
    
    // Auto-registro e atualização cadastral do Player (UPDATE OR INSERT Firebird)
    class function RegisterPlayer(const AUUID, ANome, AIPLocal, AIPPublico, AMac, AOS, AVersao: string; 
      ALargura, AAltura: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;

    // Atualiza heartbeat e telemetria da tela
    class function UpdatePlayerHeartbeat(const AUUID, AStatus, AVersao, ACurrentMedia: string; 
      AFreeSpaceMB: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;

    // Ingestão em lote (Batch Transaction) de registros Proof-of-Play
    class function InsertBatchProofOfPlay(const APlayerUUID, AJsonBatch: string; 
      AConn: TIBConnection; ATrans: TSQLTransaction): Integer;
  end;

implementation

{ TSignageDatabaseService }

class function TSignageDatabaseService.FetchPlaylistItemsAsJson(APlaylistID: Int64; 
  AConn: TIBConnection; ATrans: TSQLTransaction; ARequiredMedias: TJSONArray): TJSONArray;
var
  Qry: TSQLQuery;
  ItemObj, MediaObj: TJSONObject;
  i: Integer;
  AlreadyInRequired: Boolean;
  CurrentMD5: string;
begin
  Result := TJSONArray.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;
    Qry.SQL.Text :=
      'SELECT PI.ID AS ITEM_ID, PI.ORDEM, PI.DURACAO_EXIBICAO_SEG, PI.TRANSICAO, ' +
      '       M.ID AS MIDIA_ID, M.NOME_ARQUIVO, M.HASH_MD5, M.TAMANHO_BYTES, ' +
      '       M.TIPO_MIDIA, M.URL_DOWNLOAD ' +
      'FROM PLAYLIST_ITENS PI ' +
      'INNER JOIN MIDIAS M ON M.ID = PI.MIDIA_ID ' +
      'WHERE PI.PLAYLIST_ID = :PLAYLIST_ID ' +
      'ORDER BY PI.ORDEM ASC';
    Qry.ParamByName('PLAYLIST_ID').AsLargeInt := APlaylistID;
    Qry.Open;

    while not Qry.EOF do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('item_id', Qry.FieldByName('ITEM_ID').AsLargeInt);
      ItemObj.Add('media_id', Qry.FieldByName('MIDIA_ID').AsLargeInt);
      ItemObj.Add('order', Qry.FieldByName('ORDEM').AsInteger);
      ItemObj.Add('duration_sec', Qry.FieldByName('DURACAO_EXIBICAO_SEG').AsInteger);
      ItemObj.Add('transition', Qry.FieldByName('TRANSICAO').AsString);
      ItemObj.Add('filename', Qry.FieldByName('NOME_ARQUIVO').AsString);
      ItemObj.Add('hash_md5', Qry.FieldByName('HASH_MD5').AsString);
      ItemObj.Add('type', Qry.FieldByName('TIPO_MIDIA').AsString);
      ItemObj.Add('size_bytes', Qry.FieldByName('TAMANHO_BYTES').AsLargeInt);
      ItemObj.Add('download_url', Qry.FieldByName('URL_DOWNLOAD').AsString);
      Result.Add(ItemObj);

      // Adicionar à lista consolidada de downloads requeridos se não duplicado
      if ARequiredMedias <> nil then
      begin
        CurrentMD5 := Qry.FieldByName('HASH_MD5').AsString;
        AlreadyInRequired := False;
        for i := 0 to ARequiredMedias.Count - 1 do
        begin
          if ARequiredMedias.Objects[i].Get('hash_md5', '') = CurrentMD5 then
          begin
            AlreadyInRequired := True;
            Break;
          end;
        end;

        if not AlreadyInRequired then
        begin
          MediaObj := TJSONObject.Create;
          MediaObj.Add('media_id', Qry.FieldByName('MIDIA_ID').AsLargeInt);
          MediaObj.Add('filename', Qry.FieldByName('NOME_ARQUIVO').AsString);
          MediaObj.Add('hash_md5', CurrentMD5);
          MediaObj.Add('size_bytes', Qry.FieldByName('TAMANHO_BYTES').AsLargeInt);
          MediaObj.Add('type', Qry.FieldByName('TIPO_MIDIA').AsString);
          MediaObj.Add('download_url', Qry.FieldByName('URL_DOWNLOAD').AsString);
          ARequiredMedias.Add(MediaObj);
        end;
      end;

      Qry.Next;
    end;
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

class function TSignageDatabaseService.BuildPlayerSyncJson(const APlayerUUID: string; 
  AConn: TIBConnection; ATrans: TSQLTransaction): string;
var
  RootObj, FallbackPlObj, SchedObj, SchedPlObj: TJSONObject;
  SchedArr, RequiredMediasArr: TJSONArray;
  QryPlayer, QryFallback, QrySchedules: TSQLQuery;
  PlayerID, FallbackPlID, SchedPlID: Int64;
begin
  Result := '{"error": "Internal Error"}';

  RootObj := TJSONObject.Create;
  RequiredMediasArr := TJSONArray.Create;
  SchedArr := TJSONArray.Create;

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

    // 1. Identificar a Tela
    QryPlayer.SQL.Text := 'SELECT ID, UUID, NOME, STATUS, VOLUME_AUDIO FROM TELAS WHERE UUID = :UUID';
    QryPlayer.ParamByName('UUID').AsString := APlayerUUID;
    QryPlayer.Open;

    if QryPlayer.EOF then
    begin
      RootObj.Add('status', 'error');
      RootObj.Add('message', 'Player UUID não cadastrado');
      Result := RootObj.AsJSON;
      Exit;
    end;

    PlayerID := QryPlayer.FieldByName('ID').AsLargeInt;
    RootObj.Add('status', 'ok');
    RootObj.Add('server_time', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
    RootObj.Add('player_uuid', APlayerUUID);
    RootObj.Add('player_name', QryPlayer.FieldByName('NOME').AsString);
    RootObj.Add('volume', QryPlayer.FieldByName('VOLUME_AUDIO').AsInteger);
    QryPlayer.Close;

    // 2. Localizar Playlist Padrão de Fallback
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

    // 3. Localizar Agendamentos Ativos para esta Tela (ou Globais onde TELA_ID é nulo)
    QrySchedules.SQL.Text :=
      'SELECT A.ID AS SCHED_ID, A.NOME_EVENTO, A.DATA_INICIO, A.DATA_FIM, ' +
      '       A.HORA_INICIO, A.HORA_FIM, A.DIAS_SEMANA, A.PRIORIDADE, ' +
      '       P.ID AS PLAYLIST_ID, P.NOME AS PLAYLIST_NOME ' +
      'FROM AGENDAMENTOS A ' +
      'INNER JOIN PLAYLISTS P ON P.ID = A.PLAYLIST_ID ' +
      'WHERE (A.TELA_ID = :TELA_ID OR A.TELA_ID IS NULL) ' +
      '  AND A.ATIVO = 1 ' +
      '  AND P.ATIVA = 1 ' +
      '  AND A.DATA_FIM >= CURRENT_DATE ' +
      'ORDER BY A.PRIORIDADE DESC, A.ID ASC';
    QrySchedules.ParamByName('TELA_ID').AsLargeInt := PlayerID;
    QrySchedules.Open;

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

      // Detalhes da Playlist do Agendamento
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

class function TSignageDatabaseService.RegisterPlayer(const AUUID, ANome, AIPLocal, AIPPublico, 
  AMac, AOS, AVersao: string; ALargura, AAltura: Integer; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;

    // Utilização de UPDATE OR INSERT nativo do Firebird com MATCHING
    Qry.SQL.Text :=
      'UPDATE OR INSERT INTO TELAS (' +
      '  UUID, NOME, IP_LOCAL, IP_PUBLICO, MAC_ADDRESS, SISTEMA_OPERACIONAL, ' +
      '  VERSAO_PLAYER, LARGURA_PX, ALTURA_PX, STATUS, ULTIMO_HEARTBEAT ' +
      ') VALUES (' +
      '  :UUID, :NOME, :IP_LOCAL, :IP_PUBLICO, :MAC_ADDRESS, :SISTEMA_OPERACIONAL, ' +
      '  :VERSAO_PLAYER, :LARGURA_PX, :ALTURA_PX, ''ONLINE'', CURRENT_TIMESTAMP ' +
      ') MATCHING (UUID)';

    Qry.ParamByName('UUID').AsString := Copy(Trim(AUUID), 1, 36);
    Qry.ParamByName('NOME').AsString := Copy(Trim(ANome), 1, 100);
    Qry.ParamByName('IP_LOCAL').AsString := Copy(Trim(AIPLocal), 1, 45);
    Qry.ParamByName('IP_PUBLICO').AsString := Copy(Trim(AIPPublico), 1, 45);
    Qry.ParamByName('MAC_ADDRESS').AsString := Copy(Trim(AMac), 1, 30);
    Qry.ParamByName('SISTEMA_OPERACIONAL').AsString := Copy(Trim(AOS), 1, 50);
    Qry.ParamByName('VERSAO_PLAYER').AsString := Copy(Trim(AVersao), 1, 20);
    Qry.ParamByName('LARGURA_PX').AsInteger := ALargura;
    Qry.ParamByName('ALTURA_PX').AsInteger := AAltura;

    Qry.ExecSQL;
    ATrans.CommitRetaining;
    Result := True;
  except
    on E: Exception do
    begin
      ATrans.RollbackRetaining;
      Result := False;
    end;
  end;
  Qry.Free;
end;

class function TSignageDatabaseService.UpdatePlayerHeartbeat(const AUUID, AStatus, AVersao, 
  ACurrentMedia: string; AFreeSpaceMB: Int64; AConn: TIBConnection; ATrans: TSQLTransaction): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.Database := AConn;
    Qry.Transaction := ATrans;

    Qry.SQL.Text :=
      'UPDATE TELAS ' +
      'SET STATUS = :STATUS, ' +
      '    VERSAO_PLAYER = :VERSAO_PLAYER, ' +
      '    STORAGE_LIVRE_MB = :STORAGE_LIVRE_MB, ' +
      '    ULTIMO_HEARTBEAT = CURRENT_TIMESTAMP ' +
      'WHERE UUID = :UUID';

    Qry.ParamByName('STATUS').AsString := Copy(Trim(AStatus), 1, 20);
    Qry.ParamByName('VERSAO_PLAYER').AsString := Copy(Trim(AVersao), 1, 20);
    Qry.ParamByName('STORAGE_LIVRE_MB').AsLargeInt := AFreeSpaceMB;
    Qry.ParamByName('UUID').AsString := Copy(Trim(AUUID), 1, 36);

    Qry.ExecSQL;
    ATrans.CommitRetaining;
    Result := True;
  except
    on E: Exception do
    begin
      ATrans.RollbackRetaining;
      Result := False;
    end;
  end;
  Qry.Free;
end;

class function TSignageDatabaseService.InsertBatchProofOfPlay(const APlayerUUID, AJsonBatch: string; 
  AConn: TIBConnection; ATrans: TSQLTransaction): Integer;
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
  if AJsonBatch.Trim = '' then Exit;

  InsertedCount := 0;
  QryPlayer := TSQLQuery.Create(nil);
  QryInsert := TSQLQuery.Create(nil);
  Parser := TJSONParser.Create(AJsonBatch, True);
  try
    QryPlayer.Database := AConn;
    QryPlayer.Transaction := ATrans;
    QryInsert.Database := AConn;
    QryInsert.Transaction := ATrans;

    // 1. Obter ID interno da Tela
    QryPlayer.SQL.Text := 'SELECT ID FROM TELAS WHERE UUID = :UUID';
    QryPlayer.ParamByName('UUID').AsString := APlayerUUID;
    QryPlayer.Open;
    if QryPlayer.EOF then Exit;
    PlayerID := QryPlayer.FieldByName('ID').AsLargeInt;
    QryPlayer.Close;

    // 2. Preparar comando INSERT parametrizado
    QryInsert.SQL.Text :=
      'INSERT INTO LOGS_EXIBICAO (' +
      '  TELA_ID, MIDIA_ID, PLAYLIST_ID, DATA_HORA_INICIO, DATA_HORA_FIM, ' +
      '  SEGUNDOS_EXIBIDOS, STATUS_EXIBICAO, MENSAGEM_ERRO ' +
      ') VALUES (' +
      '  :TELA_ID, :MIDIA_ID, :PLAYLIST_ID, :DATA_HORA_INICIO, :DATA_HORA_FIM, ' +
      '  :SEGUNDOS_EXIBIDOS, :STATUS_EXIBICAO, :MENSAGEM_ERRO ' +
      ')';

    RootArr := TJSONArray(Parser.Parse);
    if RootArr <> nil then
    begin
      try
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

        // Comitar lote em transação única
        ATrans.CommitRetaining;
        Result := InsertedCount;
      finally
        RootArr.Free;
      end;
    end;
  except
    on E: Exception do
    begin
      ATrans.RollbackRetaining;
      Result := 0;
    end;
  end;
  Parser.Free;
  QryPlayer.Free;
  QryInsert.Free;
end;

end.
