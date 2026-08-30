unit uApiRouter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fphttpapp, fpjson, jsonparser, md5,
  uDbManager, uDbQueries, uDurationDetector;

type
  TOnLogEvent = procedure(const AMsg: string) of object;

  { TWebApiController - Roteador Central HTTP do Servidor Web CMS }
  TWebApiController = class
  private
    FDbManager: TFirebirdConnectionManager;
    FOnLog: TOnLogEvent;
    
    procedure Log(const AMsg: string);
    procedure SendJsonResponse(AResponse: TResponse; const AJson: string; AStatusCode: Integer = 200);
    procedure SendErrorResponse(AResponse: TResponse; const AMessage: string; AStatusCode: Integer = 400);
    function ExtractUUIDFromURI(const APath, APrefix, ASuffix: string): string;

    // Handlers CMS
    procedure HandleDashboardStats(ARequest: TRequest; AResponse: TResponse);
    procedure HandleDashboardLogs(ARequest: TRequest; AResponse: TResponse);
    procedure HandleListScreens(ARequest: TRequest; AResponse: TResponse);
    procedure HandleDeleteScreen(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleListMedias(ARequest: TRequest; AResponse: TResponse);
    procedure HandleUploadMedia(ARequest: TRequest; AResponse: TResponse);
    procedure HandleAddYouTubeMedia(ARequest: TRequest; AResponse: TResponse);
    procedure HandleDeleteMedia(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleListPlaylists(ARequest: TRequest; AResponse: TResponse);
    procedure HandleGetPlaylistDetails(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleCreatePlaylist(ARequest: TRequest; AResponse: TResponse);
    procedure HandleDeletePlaylist(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleSetDefaultPlaylist(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleAddPlaylistItem(const APlaylistIDStr: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleRemovePlaylistItem(const AItemIDStr: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleMovePlaylistItem(const AItemIDStr: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleListSchedules(ARequest: TRequest; AResponse: TResponse);
    procedure HandleCreateSchedule(ARequest: TRequest; AResponse: TResponse);
    procedure HandleDeleteSchedule(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleTestDb(ARequest: TRequest; AResponse: TResponse);

    // Handlers Player
    procedure HandlePlayerRegister(ARequest: TRequest; AResponse: TResponse);
    procedure HandlePlayerSync(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandlePlayerHeartbeat(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandlePlayerProofOfPlay(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleMediaDownload(const AFilename: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleStaticFiles(const ASubPath: string; ARequest: TRequest; AResponse: TResponse);

  public
    constructor Create(ADbManager: TFirebirdConnectionManager);
    procedure RouteRequest(ARequest: TRequest; AResponse: TResponse);
    property OnLog: TOnLogEvent read FOnLog write FOnLog;
  end;

implementation

{ TWebApiController }

constructor TWebApiController.Create(ADbManager: TFirebirdConnectionManager);
begin
  inherited Create;
  FDbManager := ADbManager;
end;

procedure TWebApiController.Log(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(FormatDateTime('hh:nn:ss', Now) + ' ' + AMsg);
end;

procedure TWebApiController.SendJsonResponse(AResponse: TResponse; const AJson: string; AStatusCode: Integer);
begin
  AResponse.Code := AStatusCode;
  AResponse.ContentType := 'application/json; charset=utf-8';
  AResponse.SetCustomHeader('Access-Control-Allow-Origin', '*');
  AResponse.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  AResponse.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  AResponse.Content := AJson;
  AResponse.SendContent;
end;

procedure TWebApiController.SendErrorResponse(AResponse: TResponse; const AMessage: string; AStatusCode: Integer);
var
  ErrObj: TJSONObject;
begin
  ErrObj := TJSONObject.Create;
  try
    ErrObj.Add('status', 'error');
    ErrObj.Add('message', AMessage);
    SendJsonResponse(AResponse, ErrObj.AsJSON, AStatusCode);
  finally
    ErrObj.Free;
  end;
end;

function TWebApiController.ExtractUUIDFromURI(const APath, APrefix, ASuffix: string): string;
var
  S: string;
  PosP, PosS: Integer;
begin
  Result := '';
  S := APath;
  PosP := Pos(APrefix, S);
  if PosP > 0 then
  begin
    Delete(S, 1, PosP + Length(APrefix) - 1);
    if ASuffix <> '' then
    begin
      PosS := Pos(ASuffix, S);
      if PosS > 0 then
        Result := Copy(S, 1, PosS - 1)
      else
        Result := S;
    end
    else
      Result := S;
  end;
  Result := Trim(Result);
end;

procedure TWebApiController.RouteRequest(ARequest: TRequest; AResponse: TResponse);
var
  Path, ClientIP, SubID: string;
begin
  Path := ARequest.PathInfo;
  if Pos('?', Path) > 0 then
    Path := Copy(Path, 1, Pos('?', Path) - 1);
  Path := Trim(Path);
  ClientIP := ARequest.RemoteAddr;

  // CORS Pre-flight
  if ARequest.Method = 'OPTIONS' then
  begin
    SendJsonResponse(AResponse, '{"status":"ok"}', 200);
    Exit;
  end;

  try
    // ==========================================
    // 1. API DO DASHBOARD
    // ==========================================
    if (ARequest.Method = 'GET') and (Path = '/api/v1/dashboard/stats') then
    begin
      HandleDashboardStats(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'GET') and (Path = '/api/v1/dashboard/logs') then
    begin
      HandleDashboardLogs(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'GET') and (Path = '/api/v1/server/test-db') then
    begin
      HandleTestDb(ARequest, AResponse);
      Exit;
    end;

    // ==========================================
    // 2. API DE TELAS (CMS)
    // ==========================================
    if (ARequest.Method = 'GET') and ((Path = '/api/v1/screens') or (Path = '/api/v1/players')) then
    begin
      HandleListScreens(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'DELETE') and (Pos('/api/v1/screens/', Path) = 1) then
    begin
      SubID := Copy(Path, 16, Length(Path));
      HandleDeleteScreen(SubID, ARequest, AResponse);
      Exit;
    end;

    // ==========================================
    // 3. API DE MÍDIAS (CMS)
    // ==========================================
    if (ARequest.Method = 'GET') and (Path = '/api/v1/medias') then
    begin
      HandleListMedias(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'POST') and (Path = '/api/v1/medias/upload') then
    begin
      HandleUploadMedia(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'POST') and (Path = '/api/v1/medias/youtube') then
    begin
      HandleAddYouTubeMedia(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'DELETE') and (Pos('/api/v1/medias/', Path) = 1) then
    begin
      SubID := Copy(Path, 15, Length(Path));
      HandleDeleteMedia(SubID, ARequest, AResponse);
      Exit;
    end;

    // ==========================================
    // 4. API DE PLAYLISTS (CMS)
    // ==========================================
    if (ARequest.Method = 'GET') and (Path = '/api/v1/playlists') then
    begin
      HandleListPlaylists(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'POST') and (Path = '/api/v1/playlists') then
    begin
      HandleCreatePlaylist(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'GET') and (Pos('/api/v1/playlists/', Path) = 1) and (Pos('/items', Path) = 0) and (Pos('/default', Path) = 0) then
    begin
      SubID := Copy(Path, 18, Length(Path));
      HandleGetPlaylistDetails(SubID, ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'DELETE') and (Pos('/api/v1/playlists/', Path) = 1) and (Pos('/items', Path) = 0) then
    begin
      SubID := Copy(Path, 18, Length(Path));
      HandleDeletePlaylist(SubID, ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'POST') and (Pos('/api/v1/playlists/', Path) = 1) and (Pos('/default', Path) > 0) then
    begin
      SubID := ExtractUUIDFromURI(Path, '/api/v1/playlists/', '/default');
      HandleSetDefaultPlaylist(SubID, ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'POST') and (Pos('/api/v1/playlists/', Path) = 1) and (Pos('/items', Path) > 0) then
    begin
      SubID := ExtractUUIDFromURI(Path, '/api/v1/playlists/', '/items');
      HandleAddPlaylistItem(SubID, ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'DELETE') and (Pos('/api/v1/playlist-items/', Path) = 1) then
    begin
      SubID := Copy(Path, 23, Length(Path));
      HandleRemovePlaylistItem(SubID, ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'POST') and (Pos('/api/v1/playlist-items/', Path) = 1) and (Pos('/move', Path) > 0) then
    begin
      SubID := ExtractUUIDFromURI(Path, '/api/v1/playlist-items/', '/move');
      HandleMovePlaylistItem(SubID, ARequest, AResponse);
      Exit;
    end;

    // ==========================================
    // 5. API DE AGENDAMENTOS (CMS)
    // ==========================================
    if (ARequest.Method = 'GET') and (Path = '/api/v1/schedules') then
    begin
      HandleListSchedules(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'POST') and (Path = '/api/v1/schedules') then
    begin
      HandleCreateSchedule(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'DELETE') and (Pos('/api/v1/schedules/', Path) = 1) then
    begin
      SubID := Copy(Path, 18, Length(Path));
      HandleDeleteSchedule(SubID, ARequest, AResponse);
      Exit;
    end;

    // ==========================================
    // 6. API DE PLAYERS & PROTOCOLO DIGITAL SIGNAGE
    // ==========================================
    if (ARequest.Method = 'POST') and (Path = '/api/v1/players/register') then
    begin
      Log(Format('[REGISTER] %s requisitou auto-registro', [ClientIP]));
      HandlePlayerRegister(ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'GET') and (Pos('/api/v1/players/', Path) = 1) and (Pos('/sync', Path) > 0) then
    begin
      SubID := ExtractUUIDFromURI(Path, '/api/v1/players/', '/sync');
      Log(Format('[SYNC] Tela (%s - %s) sincronizando grade', [ClientIP, Copy(SubID, 1, 8)]));
      HandlePlayerSync(SubID, ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'POST') and (Pos('/api/v1/players/', Path) = 1) and (Pos('/heartbeat', Path) > 0) then
    begin
      SubID := ExtractUUIDFromURI(Path, '/api/v1/players/', '/heartbeat');
      HandlePlayerHeartbeat(SubID, ARequest, AResponse);
      Exit;
    end;

    if (ARequest.Method = 'POST') and (Pos('/api/v1/players/', Path) = 1) and (Pos('/proof-of-play', Path) > 0) then
    begin
      SubID := ExtractUUIDFromURI(Path, '/api/v1/players/', '/proof-of-play');
      HandlePlayerProofOfPlay(SubID, ARequest, AResponse);
      Exit;
    end;

    // ==========================================
    // 7. DOWNLOAD DE MÍDIAS
    // ==========================================
    if (ARequest.Method = 'GET') and (Pos('/media/', Path) = 1) then
    begin
      HandleMediaDownload(Copy(Path, 8, Length(Path)), ARequest, AResponse);
      Exit;
    end;

    // ==========================================
    // 8. ARQUIVOS ESTÁTICOS DO PAINEL CMS & WEB PLAYER
    // ==========================================
    if (ARequest.Method = 'GET') then
    begin
      HandleStaticFiles(Path, ARequest, AResponse);
      Exit;
    end;

    SendErrorResponse(AResponse, 'Endpoint não encontrado: ' + Path, 404);

  except
    on E: Exception do
    begin
      Log('[ERRO] ' + E.Message);
      SendErrorResponse(AResponse, 'Erro interno do servidor: ' + E.Message, 500);
    end;
  end;
end;

{ Métodos de Tratamento (Handlers) }

procedure TWebApiController.HandleDashboardStats(ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Json: string;
begin
  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Json := TSignageDbService.GetDashboardStatsAsJson(Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;
  SendJsonResponse(AResponse, Json, 200);
end;

procedure TWebApiController.HandleDashboardLogs(ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Json: string;
begin
  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Json := TSignageDbService.ListRecentLogsAsJson(50, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;
  SendJsonResponse(AResponse, Json, 200);
end;

procedure TWebApiController.HandleTestDb(ARequest: TRequest; AResponse: TResponse);
var
  Msg: string;
  Ok: Boolean;
  Obj: TJSONObject;
begin
  Ok := FDbManager.TestConnection(Msg);
  Obj := TJSONObject.Create;
  try
    if Ok then
    begin
      Obj.Add('status', 'ok');
      Obj.Add('message', Msg);
      SendJsonResponse(AResponse, Obj.AsJSON, 200);
    end
    else
    begin
      Obj.Add('status', 'error');
      Obj.Add('message', Msg);
      SendJsonResponse(AResponse, Obj.AsJSON, 500);
    end;
  finally
    Obj.Free;
  end;
end;

procedure TWebApiController.HandleListScreens(ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Json: string;
begin
  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Json := TSignageDbService.ListScreensAsJson(Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;
  SendJsonResponse(AResponse, Json, 200);
end;

procedure TWebApiController.HandleDeleteScreen(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  ID: Int64;
  Ok: Boolean;
begin
  ID := StrToInt64Def(AIDStr, 0);
  if ID <= 0 then
  begin
    SendErrorResponse(AResponse, 'ID de tela inválido');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Ok := TSignageDbService.DeleteScreen(ID, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  if Ok then
    SendJsonResponse(AResponse, '{"status":"ok","message":"Tela excluída com sucesso"}', 200)
  else
    SendErrorResponse(AResponse, 'Falha ao excluir tela', 500);
end;

procedure TWebApiController.HandleListMedias(ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Json: string;
begin
  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Json := TSignageDbService.ListMediasAsJson(Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;
  SendJsonResponse(AResponse, Json, 200);
end;

procedure TWebApiController.HandleUploadMedia(ARequest: TRequest; AResponse: TResponse);
var
  UploadedFile: TUploadedFile;
  DestDir, DestFile, Ext, NomeOriginal, TipoMidia, MimeType, HashMd5: string;
  Tamanho: Int64;
  Duracao, Largura, Altura: Integer;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  NewID: Int64;
  RespObj: TJSONObject;
begin
  if ARequest.Files.Count = 0 then
  begin
    SendErrorResponse(AResponse, 'Nenhum arquivo enviado');
    Exit;
  end;

  UploadedFile := ARequest.Files[0];
  NomeOriginal := ExtractFileName(UploadedFile.FileName);
  Ext := LowerCase(ExtractFileExt(NomeOriginal));

  DestDir := ExtractFilePath(ParamStr(0)) + 'media' + PathDelim;
  if not DirectoryExists(DestDir) then
    ForceDirectories(DestDir);

  DestFile := DestDir + NomeOriginal;
  UploadedFile.SaveToFile(DestFile);

  // Copia também para ../media se existir para desenvolvimento
  if DirectoryExists(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'media') then
    CopyFile(DestFile, ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'media' + PathDelim + NomeOriginal, [cffOverwriteFile]);

  Tamanho := UploadedFile.Size;
  HashMd5 := LowerCase(MD5Print(MD5File(DestFile)));

  if (Ext = '.mp4') or (Ext = '.mkv') or (Ext = '.avi') or (Ext = '.mov') or (Ext = '.webm') then
  begin
    TipoMidia := 'VIDEO';
    MimeType := 'video/mp4';
    Duracao := DetectVideoDuration(DestFile);
    if Duracao <= 0 then Duracao := 10;
    Largura := 1920;
    Altura := 1080;
  end
  else if (Ext = '.jpg') or (Ext = '.jpeg') then
  begin
    TipoMidia := 'IMAGE';
    MimeType := 'image/jpeg';
    Duracao := 8;
    Largura := 1920;
    Altura := 1080;
  end
  else if Ext = '.png' then
  begin
    TipoMidia := 'IMAGE';
    MimeType := 'image/png';
    Duracao := 8;
    Largura := 1920;
    Altura := 1080;
  end
  else
  begin
    TipoMidia := 'IMAGE';
    MimeType := 'application/octet-stream';
    Duracao := 8;
    Largura := 1920;
    Altura := 1080;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    NewID := TSignageDbService.InsertMedia(
      NomeOriginal, NomeOriginal, HashMd5, TipoMidia, MimeType, '/media/' + NomeOriginal,
      Tamanho, Duracao, Largura, Altura, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  if NewID > 0 then
  begin
    RespObj := TJSONObject.Create;
    try
      RespObj.Add('status', 'ok');
      RespObj.Add('id', NewID);
      RespObj.Add('filename', NomeOriginal);
      RespObj.Add('duration_sec', Duracao);
      SendJsonResponse(AResponse, RespObj.AsJSON, 200);
    finally
      RespObj.Free;
    end;
  end
  else
    SendErrorResponse(AResponse, 'Falha ao salvar mídia no banco', 500);
end;

procedure TWebApiController.HandleAddYouTubeMedia(ARequest: TRequest; AResponse: TResponse);
var
  Parser: TJSONParser;
  Data: TJSONData;
  BodyObj, RespObj: TJSONObject;
  Url, VideoId, Titulo, HashMd5, CleanFile: string;
  PosV, PosBe: Integer;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  NewID: Int64;
begin
  if ARequest.Content = '' then
  begin
    SendErrorResponse(AResponse, 'Corpo da requisição vazio');
    Exit;
  end;

  Data := nil;
  Parser := TJSONParser.Create(ARequest.Content, True);
  try
    try
      Data := Parser.Parse;
    except
      Data := nil;
    end;
  finally
    Parser.Free;
  end;

  if (Data = nil) or (not (Data is TJSONObject)) then
  begin
    if Assigned(Data) then Data.Free;
    SendErrorResponse(AResponse, 'JSON inválido');
    Exit;
  end;

  BodyObj := TJSONObject(Data);
  try
    Url := Trim(BodyObj.Get('url', ''));
    Titulo := Trim(BodyObj.Get('title', ''));

    if Url = '' then
    begin
      SendErrorResponse(AResponse, 'URL do YouTube é obrigatória');
      Exit;
    end;

    VideoId := '';
    PosV := Pos('v=', Url);
    if PosV > 0 then
    begin
      VideoId := Copy(Url, PosV + 2, 11);
    end
    else
    begin
      PosBe := Pos('youtu.be/', Url);
      if PosBe > 0 then
        VideoId := Copy(Url, PosBe + 9, 11)
      else if Length(Url) = 11 then
        VideoId := Url;
    end;

    if VideoId = '' then
    begin
      SendErrorResponse(AResponse, 'ID de vídeo do YouTube não identificado na URL');
      Exit;
    end;

    if Titulo = '' then
      Titulo := 'YouTube - ' + VideoId;

    CleanFile := 'youtube_' + VideoId;
    HashMd5 := LowerCase(MD5Print(MD5String(CleanFile)));

    Conn := FDbManager.CreateConnection(Trans);
    try
      Conn.Connected := True;
      NewID := TSignageDbService.InsertMedia(
        Titulo, CleanFile, HashMd5, 'STREAM', 'video/youtube', 'https://www.youtube.com/watch?v=' + VideoId,
        0, 0, 1920, 1080, Conn, Trans);
      Conn.Connected := False;
    finally
      Trans.Free;
      Conn.Free;
    end;

    if NewID > 0 then
    begin
      RespObj := TJSONObject.Create;
      try
        RespObj.Add('status', 'ok');
        RespObj.Add('id', NewID);
        RespObj.Add('video_id', VideoId);
        SendJsonResponse(AResponse, RespObj.AsJSON, 200);
      finally
        RespObj.Free;
      end;
    end
    else
      SendErrorResponse(AResponse, 'Falha ao salvar link do YouTube', 500);

  finally
    BodyObj.Free;
  end;
end;

procedure TWebApiController.HandleDeleteMedia(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  ID: Int64;
  Ok: Boolean;
begin
  ID := StrToInt64Def(AIDStr, 0);
  if ID <= 0 then
  begin
    SendErrorResponse(AResponse, 'ID de mídia inválido');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Ok := TSignageDbService.DeleteMedia(ID, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  if Ok then
    SendJsonResponse(AResponse, '{"status":"ok","message":"Mídia excluída com sucesso"}', 200)
  else
    SendErrorResponse(AResponse, 'Falha ao excluir mídia', 500);
end;

procedure TWebApiController.HandleListPlaylists(ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Json: string;
begin
  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Json := TSignageDbService.ListPlaylistsAsJson(Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;
  SendJsonResponse(AResponse, Json, 200);
end;

procedure TWebApiController.HandleGetPlaylistDetails(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  ID: Int64;
  Json: string;
begin
  ID := StrToInt64Def(AIDStr, 0);
  if ID <= 0 then
  begin
    SendErrorResponse(AResponse, 'ID de playlist inválido');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Json := TSignageDbService.GetPlaylistDetailsAsJson(ID, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;
  SendJsonResponse(AResponse, Json, 200);
end;

procedure TWebApiController.HandleCreatePlaylist(ARequest: TRequest; AResponse: TResponse);
var
  Parser: TJSONParser;
  Data: TJSONData;
  BodyObj, RespObj: TJSONObject;
  Nome, Descricao: string;
  IsDefault: Integer;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  NewID: Int64;
begin
  if ARequest.Content = '' then
  begin
    SendErrorResponse(AResponse, 'Corpo da requisição vazio');
    Exit;
  end;

  Data := nil;
  Parser := TJSONParser.Create(ARequest.Content, True);
  try
    try Data := Parser.Parse; except Data := nil; end;
  finally
    Parser.Free;
  end;

  if (Data = nil) or (not (Data is TJSONObject)) then
  begin
    if Assigned(Data) then Data.Free;
    SendErrorResponse(AResponse, 'JSON inválido');
    Exit;
  end;

  BodyObj := TJSONObject(Data);
  try
    Nome := Trim(BodyObj.Get('name', 'Nova Playlist'));
    Descricao := Trim(BodyObj.Get('description', ''));
    IsDefault := BodyObj.Get('is_default', 0);

    Conn := FDbManager.CreateConnection(Trans);
    try
      Conn.Connected := True;
      NewID := TSignageDbService.CreatePlaylist(Nome, Descricao, IsDefault, Conn, Trans);
      Conn.Connected := False;
    finally
      Trans.Free;
      Conn.Free;
    end;

    if NewID > 0 then
    begin
      RespObj := TJSONObject.Create;
      try
        RespObj.Add('status', 'ok');
        RespObj.Add('id', NewID);
        SendJsonResponse(AResponse, RespObj.AsJSON, 200);
      finally
        RespObj.Free;
      end;
    end
    else
      SendErrorResponse(AResponse, 'Falha ao criar playlist', 500);

  finally
    BodyObj.Free;
  end;
end;

procedure TWebApiController.HandleDeletePlaylist(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  ID: Int64;
  Ok: Boolean;
begin
  ID := StrToInt64Def(AIDStr, 0);
  if ID <= 0 then
  begin
    SendErrorResponse(AResponse, 'ID de playlist inválido');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Ok := TSignageDbService.DeletePlaylist(ID, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  if Ok then
    SendJsonResponse(AResponse, '{"status":"ok","message":"Playlist excluída com sucesso"}', 200)
  else
    SendErrorResponse(AResponse, 'Falha ao excluir playlist', 500);
end;

procedure TWebApiController.HandleSetDefaultPlaylist(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  ID: Int64;
  Ok: Boolean;
begin
  ID := StrToInt64Def(AIDStr, 0);
  if ID <= 0 then
  begin
    SendErrorResponse(AResponse, 'ID de playlist inválido');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Ok := TSignageDbService.SetDefaultPlaylist(ID, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  if Ok then
    SendJsonResponse(AResponse, '{"status":"ok","message":"Playlist definida como padrão"}', 200)
  else
    SendErrorResponse(AResponse, 'Falha ao definir playlist padrão', 500);
end;

procedure TWebApiController.HandleAddPlaylistItem(const APlaylistIDStr: string; ARequest: TRequest; AResponse: TResponse);
var
  Parser: TJSONParser;
  Data: TJSONData;
  BodyObj: TJSONObject;
  PlID, MediaID: Int64;
  Duracao: Integer;
  Transicao: string;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Ok: Boolean;
begin
  PlID := StrToInt64Def(APlaylistIDStr, 0);
  if PlID <= 0 then
  begin
    SendErrorResponse(AResponse, 'ID de playlist inválido');
    Exit;
  end;

  Data := nil;
  Parser := TJSONParser.Create(ARequest.Content, True);
  try
    try Data := Parser.Parse; except Data := nil; end;
  finally
    Parser.Free;
  end;

  if (Data = nil) or (not (Data is TJSONObject)) then
  begin
    if Assigned(Data) then Data.Free;
    SendErrorResponse(AResponse, 'JSON inválido');
    Exit;
  end;

  BodyObj := TJSONObject(Data);
  try
    MediaID := BodyObj.Get('media_id', Int64(0));
    Duracao := BodyObj.Get('duration_sec', 10);
    Transicao := BodyObj.Get('transition', 'CUT');

    if MediaID <= 0 then
    begin
      SendErrorResponse(AResponse, 'ID de mídia inválido');
      Exit;
    end;

    Conn := FDbManager.CreateConnection(Trans);
    try
      Conn.Connected := True;
      Ok := TSignageDbService.AddPlaylistItem(PlID, MediaID, Duracao, Transicao, Conn, Trans);
      Conn.Connected := False;
    finally
      Trans.Free;
      Conn.Free;
    end;

    if Ok then
      SendJsonResponse(AResponse, '{"status":"ok","message":"Item adicionado à playlist"}', 200)
    else
      SendErrorResponse(AResponse, 'Falha ao adicionar item à playlist', 500);

  finally
    BodyObj.Free;
  end;
end;

procedure TWebApiController.HandleRemovePlaylistItem(const AItemIDStr: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  ID: Int64;
  Ok: Boolean;
begin
  ID := StrToInt64Def(AItemIDStr, 0);
  if ID <= 0 then
  begin
    SendErrorResponse(AResponse, 'ID de item inválido');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Ok := TSignageDbService.RemovePlaylistItem(ID, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  if Ok then
    SendJsonResponse(AResponse, '{"status":"ok","message":"Item removido com sucesso"}', 200)
  else
    SendErrorResponse(AResponse, 'Falha ao remover item', 500);
end;

procedure TWebApiController.HandleMovePlaylistItem(const AItemIDStr: string; ARequest: TRequest; AResponse: TResponse);
var
  Parser: TJSONParser;
  Data: TJSONData;
  BodyObj: TJSONObject;
  ItemID: Int64;
  Direction: string;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Ok: Boolean;
begin
  ItemID := StrToInt64Def(AItemIDStr, 0);
  if ItemID <= 0 then
  begin
    SendErrorResponse(AResponse, 'ID de item inválido');
    Exit;
  end;

  Data := nil;
  Parser := TJSONParser.Create(ARequest.Content, True);
  try
    try Data := Parser.Parse; except Data := nil; end;
  finally
    Parser.Free;
  end;

  if (Data = nil) or (not (Data is TJSONObject)) then
  begin
    if Assigned(Data) then Data.Free;
    SendErrorResponse(AResponse, 'JSON inválido');
    Exit;
  end;

  BodyObj := TJSONObject(Data);
  try
    Direction := BodyObj.Get('direction', 'up');

    Conn := FDbManager.CreateConnection(Trans);
    try
      Conn.Connected := True;
      Ok := TSignageDbService.MovePlaylistItem(ItemID, Direction, Conn, Trans);
      Conn.Connected := False;
    finally
      Trans.Free;
      Conn.Free;
    end;

    if Ok then
      SendJsonResponse(AResponse, '{"status":"ok","message":"Item reordenado com sucesso"}', 200)
    else
      SendErrorResponse(AResponse, 'Falha ao reordenar item', 500);

  finally
    BodyObj.Free;
  end;
end;

procedure TWebApiController.HandleListSchedules(ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Json: string;
begin
  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Json := TSignageDbService.ListSchedulesAsJson(Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;
  SendJsonResponse(AResponse, Json, 200);
end;

procedure TWebApiController.HandleCreateSchedule(ARequest: TRequest; AResponse: TResponse);
var
  Parser: TJSONParser;
  Data: TJSONData;
  BodyObj, RespObj: TJSONObject;
  Evento, DataIni, DataFim, HoraIni, HoraFim, Dias: string;
  PlaylistID, TelaID: Int64;
  Prioridade: Integer;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  NewID: Int64;
begin
  if ARequest.Content = '' then
  begin
    SendErrorResponse(AResponse, 'Corpo da requisição vazio');
    Exit;
  end;

  Data := nil;
  Parser := TJSONParser.Create(ARequest.Content, True);
  try
    try Data := Parser.Parse; except Data := nil; end;
  finally
    Parser.Free;
  end;

  if (Data = nil) or (not (Data is TJSONObject)) then
  begin
    if Assigned(Data) then Data.Free;
    SendErrorResponse(AResponse, 'JSON inválido');
    Exit;
  end;

  BodyObj := TJSONObject(Data);
  try
    Evento := Trim(BodyObj.Get('event_name', 'Campanha'));
    PlaylistID := BodyObj.Get('playlist_id', Int64(0));
    TelaID := BodyObj.Get('screen_id', Int64(0));
    DataIni := BodyObj.Get('start_date', FormatDateTime('yyyy-mm-dd', Date));
    DataFim := BodyObj.Get('end_date', FormatDateTime('yyyy-mm-dd', Date + 365));
    HoraIni := BodyObj.Get('start_time', '00:00:00');
    HoraFim := BodyObj.Get('end_time', '23:59:59');
    Dias := BodyObj.Get('days_of_week', '1,2,3,4,5,6,7');
    Prioridade := BodyObj.Get('priority', 10);

    if PlaylistID <= 0 then
    begin
      SendErrorResponse(AResponse, 'Playlist obrigatória para o agendamento');
      Exit;
    end;

    Conn := FDbManager.CreateConnection(Trans);
    try
      Conn.Connected := True;
      NewID := TSignageDbService.CreateSchedule(
        Evento, PlaylistID, TelaID, DataIni, DataFim, HoraIni, HoraFim, Dias, Prioridade, Conn, Trans);
      Conn.Connected := False;
    finally
      Trans.Free;
      Conn.Free;
    end;

    if NewID > 0 then
    begin
      RespObj := TJSONObject.Create;
      try
        RespObj.Add('status', 'ok');
        RespObj.Add('id', NewID);
        SendJsonResponse(AResponse, RespObj.AsJSON, 200);
      finally
        RespObj.Free;
      end;
    end
    else
      SendErrorResponse(AResponse, 'Falha ao salvar agendamento', 500);

  finally
    BodyObj.Free;
  end;
end;

procedure TWebApiController.HandleDeleteSchedule(const AIDStr: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  ID: Int64;
  Ok: Boolean;
begin
  ID := StrToInt64Def(AIDStr, 0);
  if ID <= 0 then
  begin
    SendErrorResponse(AResponse, 'ID de agendamento inválido');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Ok := TSignageDbService.DeleteSchedule(ID, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  if Ok then
    SendJsonResponse(AResponse, '{"status":"ok","message":"Agendamento excluído com sucesso"}', 200)
  else
    SendErrorResponse(AResponse, 'Falha ao excluir agendamento', 500);
end;

procedure TWebApiController.HandlePlayerRegister(ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Parser: TJSONParser;
  Data: TJSONData;
  BodyObj, RespObj: TJSONObject;
  UUID, Nome, IPLocal, IPPub, Mac, OSName, Versao: string;
  WidthPx, HeightPx: Integer;
  Success: Boolean;
begin
  if ARequest.Content = '' then
  begin
    SendErrorResponse(AResponse, 'Corpo da requisição vazio');
    Exit;
  end;

  try
    Data := nil;
    Parser := TJSONParser.Create(ARequest.Content, True);
    try
      try Data := Parser.Parse; except Data := nil; end;
    finally
      Parser.Free;
    end;

    if (Data = nil) or (not (Data is TJSONObject)) then
    begin
      if Assigned(Data) then Data.Free;
      SendErrorResponse(AResponse, 'JSON inválido');
      Exit;
    end;

    BodyObj := TJSONObject(Data);
    try
      UUID := BodyObj.Get('uuid', '');
      Nome := BodyObj.Get('name', 'Player Sem Nome');
      IPLocal := BodyObj.Get('local_ip', ARequest.RemoteAddr);
      IPPub := ARequest.RemoteAddr;
      Mac := BodyObj.Get('mac_address', '');
      OSName := BodyObj.Get('os', 'Unknown');
      Versao := BodyObj.Get('version', '1.0.0');
      WidthPx := BodyObj.Get('width', 1920);
      HeightPx := BodyObj.Get('height', 1080);
    finally
      BodyObj.Free;
    end;

    if UUID = '' then
    begin
      SendErrorResponse(AResponse, 'UUID é obrigatório');
      Exit;
    end;

    Conn := FDbManager.CreateConnection(Trans);
    try
      Conn.Connected := True;
      Success := TSignageDbService.RegisterPlayer(
        UUID, Nome, IPLocal, IPPub, Mac, OSName, Versao, WidthPx, HeightPx, Conn, Trans);
      Conn.Connected := False;
    finally
      Trans.Free;
      Conn.Free;
    end;

    if Success then
    begin
      RespObj := TJSONObject.Create;
      try
        RespObj.Add('status', 'ok');
        RespObj.Add('message', 'Player registrado/atualizado com sucesso');
        RespObj.Add('uuid', UUID);
        SendJsonResponse(AResponse, RespObj.AsJSON, 200);
      finally
        RespObj.Free;
      end;
    end
    else
      SendErrorResponse(AResponse, 'Falha ao registrar player no Firebird', 500);

  except
    on E: Exception do
      SendErrorResponse(AResponse, 'Erro interno ao registrar: ' + E.Message, 500);
  end;
end;

procedure TWebApiController.HandlePlayerSync(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  SyncJson: string;
begin
  if APlayerUUID = '' then
  begin
    SendErrorResponse(AResponse, 'UUID do player não informado');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    SyncJson := TSignageDbService.BuildPlayerSyncJson(APlayerUUID, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  SendJsonResponse(AResponse, SyncJson, 200);
end;

procedure TWebApiController.HandlePlayerHeartbeat(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Parser: TJSONParser;
  Data: TJSONData;
  BodyObj, RespObj: TJSONObject;
  Status, Versao, CurrentMedia: string;
  FreeSpaceMB: Int64;
  Success: Boolean;
begin
  Status := 'ONLINE';
  Versao := '1.0.0';
  CurrentMedia := '';
  FreeSpaceMB := 0;

  if ARequest.Content <> '' then
  begin
    Data := nil;
    Parser := TJSONParser.Create(ARequest.Content, True);
    try
      try Data := Parser.Parse; except Data := nil; end;
    finally
      Parser.Free;
    end;

    if (Data <> nil) and (Data is TJSONObject) then
    begin
      BodyObj := TJSONObject(Data);
      try
        Status := BodyObj.Get('status', 'ONLINE');
        Versao := BodyObj.Get('version', '1.0.0');
        CurrentMedia := BodyObj.Get('current_media', '');
        FreeSpaceMB := BodyObj.Get('free_space_mb', Int64(0));
      finally
        BodyObj.Free;
      end;
    end
    else if Assigned(Data) then
      Data.Free;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Success := TSignageDbService.UpdatePlayerHeartbeat(
      APlayerUUID, Status, Versao, CurrentMedia, FreeSpaceMB, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  if Success then
  begin
    RespObj := TJSONObject.Create;
    try
      RespObj.Add('status', 'ok');
      RespObj.Add('commands', TJSONArray.Create);
      SendJsonResponse(AResponse, RespObj.AsJSON, 200);
    finally
      RespObj.Free;
    end;
  end
  else
    SendErrorResponse(AResponse, 'Falha ao processar heartbeat', 500);
end;

procedure TWebApiController.HandlePlayerProofOfPlay(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  InsertedQty: Integer;
  RespObj: TJSONObject;
begin
  if ARequest.Content = '' then
  begin
    SendErrorResponse(AResponse, 'Payload vazio');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    InsertedQty := TSignageDbService.InsertBatchProofOfPlay(APlayerUUID, ARequest.Content, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  RespObj := TJSONObject.Create;
  try
    RespObj.Add('status', 'ok');
    RespObj.Add('records_inserted', InsertedQty);
    SendJsonResponse(AResponse, RespObj.AsJSON, 200);
  finally
    RespObj.Free;
  end;
end;

procedure TWebApiController.HandleMediaDownload(const AFilename: string; ARequest: TRequest; AResponse: TResponse);
var
  MediaDirs: array[0..3] of string;
  FoundPath, Ext, CleanName: string;
  i: Integer;
  FileStream: TFileStream;
begin
  CleanName := AFilename;
  if (Pos('..', CleanName) > 0) or (Pos('/', CleanName) > 0) or (Pos('\', CleanName) > 0) or (CleanName = '') then
  begin
    SendErrorResponse(AResponse, 'Nome de arquivo inválido', 400);
    Exit;
  end;

  MediaDirs[0] := ExtractFilePath(ParamStr(0)) + 'media' + PathDelim;
  MediaDirs[1] := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'media' + PathDelim;
  MediaDirs[2] := GetCurrentDir + PathDelim + 'media' + PathDelim;
  MediaDirs[3] := '/home/mauricio/Fontes Lazarus/Digital sign/server/media/';

  FoundPath := '';
  for i := 0 to High(MediaDirs) do
  begin
    if DirectoryExists(MediaDirs[i]) and FileExists(MediaDirs[i] + CleanName) then
    begin
      FoundPath := MediaDirs[i] + CleanName;
      Break;
    end;
  end;

  if (FoundPath = '') or not FileExists(FoundPath) then
  begin
    SendErrorResponse(AResponse, 'Arquivo de mídia não encontrado: ' + CleanName, 404);
    Exit;
  end;

  Ext := LowerCase(ExtractFileExt(FoundPath));
  if (Ext = '.mp4') or (Ext = '.mkv') or (Ext = '.avi') or (Ext = '.mov') or (Ext = '.webm') then
    AResponse.ContentType := 'video/mp4'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then
    AResponse.ContentType := 'image/jpeg'
  else if (Ext = '.png') then
    AResponse.ContentType := 'image/png'
  else if (Ext = '.webp') then
    AResponse.ContentType := 'image/webp'
  else
    AResponse.ContentType := 'application/octet-stream';

  AResponse.SetCustomHeader('Access-Control-Allow-Origin', '*');
  AResponse.Code := 200;

  FileStream := TFileStream.Create(FoundPath, fmOpenRead or fmShareDenyNone);
  AResponse.ContentStream := FileStream;
  AResponse.SendContent;
end;

procedure TWebApiController.HandleStaticFiles(const ASubPath: string; ARequest: TRequest; AResponse: TResponse);
var
  PublicDirs: array[0..3] of string;
  FoundPath, Ext, CleanSubPath: string;
  i: Integer;
  FileStream: TFileStream;
begin
  CleanSubPath := Trim(ASubPath);
  if (CleanSubPath = '') or (CleanSubPath = '/') or (CleanSubPath = '/admin') then
    CleanSubPath := 'index.html';

  if (CleanSubPath = '/player') or (CleanSubPath = '/player/') then
    CleanSubPath := 'player/index.html';

  if (Pos('/player/', CleanSubPath) = 1) then
    CleanSubPath := 'player/' + Copy(CleanSubPath, 9, Length(CleanSubPath));

  if (Pos('..', CleanSubPath) > 0) or (Pos('\', CleanSubPath) > 0) then
  begin
    SendErrorResponse(AResponse, 'Acesso inválido', 400);
    Exit;
  end;

  PublicDirs[0] := ExtractFilePath(ParamStr(0)) + 'public' + PathDelim;
  PublicDirs[1] := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'public' + PathDelim;
  PublicDirs[2] := GetCurrentDir + PathDelim + 'public' + PathDelim;
  PublicDirs[3] := GetCurrentDir + PathDelim + 'servidorweb' + PathDelim + 'public' + PathDelim;

  FoundPath := '';
  for i := 0 to High(PublicDirs) do
  begin
    if DirectoryExists(PublicDirs[i]) and FileExists(PublicDirs[i] + CleanSubPath) then
    begin
      FoundPath := PublicDirs[i] + CleanSubPath;
      Break;
    end;
  end;

  if (FoundPath <> '') and FileExists(FoundPath) then
  begin
    Ext := LowerCase(ExtractFileExt(FoundPath));
    if (Ext = '.html') or (Ext = '.htm') then
      AResponse.ContentType := 'text/html; charset=utf-8'
    else if Ext = '.css' then
      AResponse.ContentType := 'text/css; charset=utf-8'
    else if Ext = '.js' then
      AResponse.ContentType := 'application/javascript; charset=utf-8'
    else if Ext = '.json' then
      AResponse.ContentType := 'application/json; charset=utf-8'
    else if Ext = '.svg' then
      AResponse.ContentType := 'image/svg+xml'
    else if (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg') then
      AResponse.ContentType := 'image/' + Copy(Ext, 2, Length(Ext))
    else
      AResponse.ContentType := 'application/octet-stream';

    AResponse.SetCustomHeader('Access-Control-Allow-Origin', '*');
    AResponse.Code := 200;

    FileStream := TFileStream.Create(FoundPath, fmOpenRead or fmShareDenyNone);
    AResponse.ContentStream := FileStream;
    AResponse.SendContent;
    Exit;
  end;

  SendErrorResponse(AResponse, 'Arquivo não encontrado: ' + CleanSubPath, 404);
end;

end.
