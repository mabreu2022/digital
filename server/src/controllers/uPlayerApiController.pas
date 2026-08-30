unit uPlayerApiController;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpapp, httpdefs, fpjson, jsonparser, sqldb, IBConnection,
  uDbConnection, uSignageQueries;

type
  TOnApiLogEvent = procedure(const ALogMsg: string) of object;

  { TPlayerApiController - Gerenciador dos Endpoints REST do Player }
  TPlayerApiController = class
  private
    FDbManager: TFirebirdConnectionManager;
    FOnLog: TOnApiLogEvent;
    
    procedure Log(const AMsg: string);
    procedure SendJsonResponse(AResponse: TResponse; const AJson: string; AStatusCode: Integer = 200);
    procedure SendErrorResponse(AResponse: TResponse; const AMessage: string; AStatusCode: Integer = 400);
    function ExtractUUIDFromURI(const APath, APrefix, ASuffix: string): string;
  public
    constructor Create(ADbManager: TFirebirdConnectionManager);
    
    // Roteador de requisições HTTP da API de Players
    procedure RouteRequest(ARequest: TRequest; AResponse: TResponse);
    
    // Handlers específicos
    procedure HandleRegister(ARequest: TRequest; AResponse: TResponse);
    procedure HandleSync(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleHeartbeat(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleProofOfPlay(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleMediaDownload(const AFilename: string; ARequest: TRequest; AResponse: TResponse);
    procedure HandleWebPlayer(const ASubPath: string; ARequest: TRequest; AResponse: TResponse);

    property OnLog: TOnApiLogEvent read FOnLog write FOnLog;
  end;

implementation

{ TPlayerApiController }

constructor TPlayerApiController.Create(ADbManager: TFirebirdConnectionManager);
begin
  inherited Create;
  FDbManager := ADbManager;
end;

procedure TPlayerApiController.Log(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(FormatDateTime('hh:nn:ss', Now) + ' ' + AMsg);
end;

procedure TPlayerApiController.SendJsonResponse(AResponse: TResponse; const AJson: string; AStatusCode: Integer);
begin
  AResponse.Code := AStatusCode;
  AResponse.ContentType := 'application/json; charset=utf-8';
  AResponse.SetCustomHeader('Access-Control-Allow-Origin', '*');
  AResponse.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  AResponse.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  AResponse.Content := AJson;
  AResponse.SendContent;
end;

procedure TPlayerApiController.SendErrorResponse(AResponse: TResponse; const AMessage: string; AStatusCode: Integer);
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

function TPlayerApiController.ExtractUUIDFromURI(const APath, APrefix, ASuffix: string): string;
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

procedure TPlayerApiController.RouteRequest(ARequest: TRequest; AResponse: TResponse);
var
  Path, UUID, ClientIP: string;
begin
  Path := ARequest.PathInfo;
  if Pos('?', Path) > 0 then
    Path := Copy(Path, 1, Pos('?', Path) - 1);
  Path := Trim(Path);
  ClientIP := ARequest.RemoteAddr;

  // Suporte a CORS Pre-flight
  if ARequest.Method = 'OPTIONS' then
  begin
    SendJsonResponse(AResponse, '{"status":"ok"}', 200);
    Exit;
  end;

  // 1. POST /api/v1/players/register
  if (ARequest.Method = 'POST') and (Path = '/api/v1/players/register') then
  begin
    Log(Format('[REGISTER] %s requisitou auto-registro', [ClientIP]));
    HandleRegister(ARequest, AResponse);
    Exit;
  end;

  // 2. GET /api/v1/players/{uuid}/sync
  if (ARequest.Method = 'GET') and (Pos('/api/v1/players/', Path) = 1) and (Pos('/sync', Path) > 0) then
  begin
    UUID := ExtractUUIDFromURI(Path, '/api/v1/players/', '/sync');
    Log(Format('[SYNC] Tela (%s - %s) sincronizando grade', [ClientIP, Copy(UUID, 1, 8)]));
    HandleSync(UUID, ARequest, AResponse);
    Exit;
  end;

  // 3. POST /api/v1/players/{uuid}/heartbeat
  if (ARequest.Method = 'POST') and (Pos('/api/v1/players/', Path) = 1) and (Pos('/heartbeat', Path) > 0) then
  begin
    UUID := ExtractUUIDFromURI(Path, '/api/v1/players/', '/heartbeat');
    Log(Format('[HEARTBEAT] Tela (%s) ping de telemetria recebido', [ClientIP]));
    HandleHeartbeat(UUID, ARequest, AResponse);
    Exit;
  end;

  // 4. POST /api/v1/players/{uuid}/proof-of-play
  if (ARequest.Method = 'POST') and (Pos('/api/v1/players/', Path) = 1) and (Pos('/proof-of-play', Path) > 0) then
  begin
    UUID := ExtractUUIDFromURI(Path, '/api/v1/players/', '/proof-of-play');
    Log(Format('[PROOF-OF-PLAY] Tela (%s) enviou lote de exibicao', [ClientIP]));
    HandleProofOfPlay(UUID, ARequest, AResponse);
    Exit;
  end;

  // 5. GET /media/{filename}
  if (ARequest.Method = 'GET') and (Pos('/media/', Path) = 1) then
  begin
    Log(Format('[DOWNLOAD] %s baixando: %s', [ClientIP, Copy(Path, 8, Length(Path))]));
    HandleMediaDownload(Copy(Path, 8, Length(Path)), ARequest, AResponse);
    Exit;
  end;

  // 6. GET /web/{subpath} (Arquivos estáticos do Web Player)
  if (ARequest.Method = 'GET') and (Pos('/web/', Path) = 1) then
  begin
    HandleWebPlayer(Copy(Path, 6, Length(Path)), ARequest, AResponse);
    Exit;
  end;

  // 7. GET /player, /player/, /web, /, /player.html, /index.html (Web Signage Player SPA)
  if (ARequest.Method = 'GET') and ((Path = '') or (Path = '/') or (Path = '/player') or 
     (Path = '/player/') or (Path = '/web') or (Path = '/web/') or (Path = '/player.html') or (Path = '/index.html')) then
  begin
    Log(Format('[WEB-PLAYER] %s acessou o Web Signage Player', [ClientIP]));
    HandleWebPlayer('index.html', ARequest, AResponse);
    Exit;
  end;

  // 404 Endpoint Não Encontrado
  Log(Format('[404] %s tentou rota inexistente: %s', [ClientIP, Path]));
  SendErrorResponse(AResponse, 'Endpoint não encontrado: ' + Path, 404);
end;

procedure TPlayerApiController.HandleRegister(ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Parser: TJSONParser;
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

  Parser := TJSONParser.Create(ARequest.Content, True);
  try
    BodyObj := TJSONObject(Parser.Parse);
    if BodyObj = nil then
    begin
      SendErrorResponse(AResponse, 'JSON inválido');
      Exit;
    end;

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

      if UUID = '' then
      begin
        SendErrorResponse(AResponse, 'UUID é obrigatório');
        Exit;
      end;

      Conn := FDbManager.CreateConnection(Trans);
      try
        Conn.Connected := True;
        Success := TSignageDatabaseService.RegisterPlayer(
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

    finally
      BodyObj.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TPlayerApiController.HandleSync(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
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
    SyncJson := TSignageDatabaseService.BuildPlayerSyncJson(APlayerUUID, Conn, Trans);
    Conn.Connected := False;
  finally
    Trans.Free;
    Conn.Free;
  end;

  SendJsonResponse(AResponse, SyncJson, 200);
end;

procedure TPlayerApiController.HandleHeartbeat(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Parser: TJSONParser;
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
    Parser := TJSONParser.Create(ARequest.Content, True);
    try
      BodyObj := TJSONObject(Parser.Parse);
      if BodyObj <> nil then
      begin
        try
          Status := BodyObj.Get('status', 'ONLINE');
          Versao := BodyObj.Get('version', '1.0.0');
          CurrentMedia := BodyObj.Get('current_media', '');
          FreeSpaceMB := BodyObj.Get('free_space_mb', Int64(0));
        finally
          BodyObj.Free;
        end;
      end;
    finally
      Parser.Free;
    end;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  try
    Conn.Connected := True;
    Success := TSignageDatabaseService.UpdatePlayerHeartbeat(
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
      RespObj.Add('commands', TJSONArray.Create); // Comandos pendentes como RESTART, REBOOT, etc.
      SendJsonResponse(AResponse, RespObj.AsJSON, 200);
    finally
      RespObj.Free;
    end;
  end
  else
    SendErrorResponse(AResponse, 'Falha ao processar heartbeat', 500);
end;

procedure TPlayerApiController.HandleProofOfPlay(const APlayerUUID: string; ARequest: TRequest; AResponse: TResponse);
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
    InsertedQty := TSignageDatabaseService.InsertBatchProofOfPlay(APlayerUUID, ARequest.Content, Conn, Trans);
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

procedure TPlayerApiController.HandleMediaDownload(const AFilename: string; ARequest: TRequest; AResponse: TResponse);
var
  MediaDirs: array[0..2] of string;
  FoundPath, Ext, CleanName: string;
  i: Integer;
  FileStream: TFileStream;
begin
  CleanName := AFilename;
  // Segurança contra Directory Traversal
  if (Pos('..', CleanName) > 0) or (Pos('/', CleanName) > 0) or (Pos('\', CleanName) > 0) or (CleanName = '') then
  begin
    SendErrorResponse(AResponse, 'Nome de arquivo inválido', 400);
    Exit;
  end;

  MediaDirs[0] := ExtractFilePath(ParamStr(0)) + 'media' + PathDelim;
  MediaDirs[1] := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'media' + PathDelim;
  MediaDirs[2] := GetCurrentDir + PathDelim + 'media' + PathDelim;

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
    if not DirectoryExists(MediaDirs[0]) then
      ForceDirectories(MediaDirs[0]);
    SendErrorResponse(AResponse, 'Arquivo de mídia não encontrado: ' + CleanName, 404);
    Exit;
  end;

  Ext := LowerCase(ExtractFileExt(FoundPath));
  if (Ext = '.mp4') or (Ext = '.mkv') or (Ext = '.avi') or (Ext = '.mov') then
    AResponse.ContentType := 'video/mp4'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then
    AResponse.ContentType := 'image/jpeg'
  else if (Ext = '.png') then
    AResponse.ContentType := 'image/png'
  else if (Ext = '.webp') then
    AResponse.ContentType := 'image/webp'
  else if (Ext = '.html') or (Ext = '.htm') then
    AResponse.ContentType := 'text/html; charset=utf-8'
  else
    AResponse.ContentType := 'application/octet-stream';

  AResponse.SetCustomHeader('Access-Control-Allow-Origin', '*');
  AResponse.Code := 200;

  FileStream := TFileStream.Create(FoundPath, fmOpenRead or fmShareDenyNone);
  try
    AResponse.ContentStream := FileStream;
    AResponse.SendContent;
  finally
    FileStream.Free;
  end;
end;

procedure TPlayerApiController.HandleWebPlayer(const ASubPath: string; ARequest: TRequest; AResponse: TResponse);
var
  WebDirs: array[0..2] of string;
  FoundPath, Ext, CleanSubPath: string;
  i: Integer;
  FileStream: TFileStream;
begin
  CleanSubPath := Trim(ASubPath);
  if (CleanSubPath = '') or (CleanSubPath = '/') then
    CleanSubPath := 'index.html';

  if (Pos('..', CleanSubPath) > 0) or (Pos('\', CleanSubPath) > 0) then
  begin
    SendErrorResponse(AResponse, 'Acesso inválido', 400);
    Exit;
  end;

  WebDirs[0] := ExtractFilePath(ParamStr(0)) + 'web' + PathDelim;
  WebDirs[1] := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'web' + PathDelim;
  WebDirs[2] := GetCurrentDir + PathDelim + 'web' + PathDelim;

  FoundPath := '';
  for i := 0 to High(WebDirs) do
  begin
    if DirectoryExists(WebDirs[i]) and FileExists(WebDirs[i] + CleanSubPath) then
    begin
      FoundPath := WebDirs[i] + CleanSubPath;
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
    try
      AResponse.ContentStream := FileStream;
      AResponse.SendContent;
    finally
      FileStream.Free;
    end;
    Exit;
  end;

  // Fallback quando executado sem a pasta web externa
  if (CleanSubPath = 'index.html') then
  begin
    AResponse.Code := 200;
    AResponse.ContentType := 'text/html; charset=utf-8';
    AResponse.SetCustomHeader('Access-Control-Allow-Origin', '*');
    AResponse.Content := '<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8">' +
                         '<title>Digital Signage Web Player</title>' +
                         '<style>body{background:#0b0f19;color:#fff;font-family:sans-serif;' +
                         'display:flex;align-items:center;justify-content:center;height:100vh;margin:0;}' +
                         '.c{text-align:center;padding:40px;background:rgba(255,255,255,0.05);' +
                         'border-radius:16px;border:1px solid rgba(255,255,255,0.1);max-width:500px;}' +
                         'h2{margin:0 0 10px;color:#38bdf8;} p{color:#94a3b8;font-size:14px;}</style></head>' +
                         '<body><div class="c"><h2>📺 Digital Signage Web Player</h2>' +
                         '<p>O Web Player está pronto! Crie a pasta <code>server/web/</code> para carregar o visual completo.</p>' +
                         '</div></body></html>';
    AResponse.SendContent;
    Exit;
  end;

  SendErrorResponse(AResponse, 'Arquivo web não encontrado: ' + CleanSubPath, 404);
end;

end.
