unit uSyncWorker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpclient, opensslsockets, fpjson, jsonparser,
  uCacheManager, uProofOfPlay, uScheduler;

type
  { Evento chamado na Thread Principal para notificar nova grade pronta }
  TOnScheduleUpdatedEvent = procedure(Sender: TObject; const ANewScheduleJson: string) of object;
  TOnSyncStatusEvent = procedure(Sender: TObject; const AStatus: string) of object;

  { TSyncWorkerThread - Worker em background para Heartbeat, Sync e Uploads }
  TSyncWorkerThread = class(TThread)
  private
    FPlayerUUID: string;
    FServerBaseURL: string;
    FHeartbeatIntervalSec: Integer;
    FSyncIntervalSec: Integer;
    FCacheManager: TCacheManager;
    FProofOfPlay: TProofOfPlayManager;
    FLastSyncScheduleJson: string;
    FCurrentPlayingMedia: string;
    
    FOnScheduleUpdated: TOnScheduleUpdatedEvent;
    FOnStatusChange: TOnSyncStatusEvent;
    
    FTempStatusMsg: string;
    FTempScheduleJson: string;
    
    procedure DoNotifyStatus;
    procedure DoNotifyScheduleUpdated;
    
    function PerformHeartbeat: Boolean;
    function PerformSync: Boolean;
    function PerformProofOfPlayUpload: Boolean;
    function PostJson(const AUrl, AJsonBody: string; out AResponse: string): Boolean;
    function GetJson(const AUrl: string; out AResponse: string): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AUUID, AServerURL: string; 
      ACacheMgr: TCacheManager; APoPMgr: TProofOfPlayManager);
    destructor Destroy; override;
    
    procedure SetCurrentPlayingMedia(const AMediaName: string);
    
    property HeartbeatIntervalSec: Integer read FHeartbeatIntervalSec write FHeartbeatIntervalSec;
    property SyncIntervalSec: Integer read FSyncIntervalSec write FSyncIntervalSec;
    property OnScheduleUpdated: TOnScheduleUpdatedEvent read FOnScheduleUpdated write FOnScheduleUpdated;
    property OnStatusChange: TOnSyncStatusEvent read FOnStatusChange write FOnStatusChange;
  end;

implementation

{ TSyncWorkerThread }

constructor TSyncWorkerThread.Create(const AUUID, AServerURL: string;
  ACacheMgr: TCacheManager; APoPMgr: TProofOfPlayManager);
begin
  inherited Create(True); // Create suspended
  FreeOnTerminate := False;
  FPlayerUUID := AUUID;
  FServerBaseURL := ExcludeTrailingPathDelimiter(AServerURL);
  FCacheManager := ACacheMgr;
  FProofOfPlay := APoPMgr;
  FHeartbeatIntervalSec := 15; // 15 segundos entre heartbeats
  FSyncIntervalSec := 60;      // 60 segundos entre sincronizações de grade
  FCurrentPlayingMedia := '';
end;

destructor TSyncWorkerThread.Destroy;
begin
  Terminate;
  inherited Destroy;
end;

procedure TSyncWorkerThread.SetCurrentPlayingMedia(const AMediaName: string);
begin
  FCurrentPlayingMedia := AMediaName;
end;

procedure TSyncWorkerThread.DoNotifyStatus;
begin
  if Assigned(FOnStatusChange) then
    FOnStatusChange(Self, FTempStatusMsg);
end;

procedure TSyncWorkerThread.DoNotifyScheduleUpdated;
begin
  if Assigned(FOnScheduleUpdated) then
    FOnScheduleUpdated(Self, FTempScheduleJson);
end;

function TSyncWorkerThread.PostJson(const AUrl, AJsonBody: string; out AResponse: string): Boolean;
var
  Client: TFPHTTPClient;
  RequestBody: TStringStream;
begin
  Result := False;
  AResponse := '';

  Client := TFPHTTPClient.Create(nil);
  RequestBody := TStringStream.Create(AJsonBody);
  try
    try
      Client.AddHeader('Content-Type', 'application/json');
      Client.AddHeader('Accept', 'application/json');
      Client.IOTimeout := 10000; // 10s timeout
      Client.RequestBody := RequestBody;
      AResponse := Client.Post(AUrl);
      Result := (Client.ResponseStatusCode >= 200) and (Client.ResponseStatusCode < 300);
    except
      on E: Exception do
        AResponse := E.Message;
    end;
  finally
    RequestBody.Free;
    Client.Free;
  end;
end;

function TSyncWorkerThread.GetJson(const AUrl: string; out AResponse: string): Boolean;
var
  Client: TFPHTTPClient;
begin
  Result := False;
  AResponse := '';

  Client := TFPHTTPClient.Create(nil);
  try
    try
      Client.AddHeader('Accept', 'application/json');
      Client.IOTimeout := 15000;
      AResponse := Client.Get(AUrl);
      Result := (Client.ResponseStatusCode >= 200) and (Client.ResponseStatusCode < 300);
    except
      on E: Exception do
        AResponse := E.Message;
    end;
  finally
    Client.Free;
  end;
end;

function TSyncWorkerThread.PerformHeartbeat: Boolean;
var
  URL, Payload, ResponseStr: string;
  HeartbeatObj: TJSONObject;
begin
  URL := FServerBaseURL + '/api/v1/players/' + FPlayerUUID + '/heartbeat';
  HeartbeatObj := TJSONObject.Create;
  try
    HeartbeatObj.Add('status', 'ONLINE');
    HeartbeatObj.Add('version', '1.0.0');
    HeartbeatObj.Add('free_space_mb', FCacheManager.GetFreeDiskSpaceMB);
    HeartbeatObj.Add('current_media', FCurrentPlayingMedia);
    Payload := HeartbeatObj.AsJSON;
  finally
    HeartbeatObj.Free;
  end;

  Result := PostJson(URL, Payload, ResponseStr);
end;

function TSyncWorkerThread.PerformProofOfPlayUpload: Boolean;
var
  URL, BatchJson, ResponseStr: string;
  PendingQty: Integer;
begin
  Result := True;
  PendingQty := FProofOfPlay.PendingCount;
  if PendingQty = 0 then Exit;

  BatchJson := FProofOfPlay.ExportBatchJson(50);
  URL := FServerBaseURL + '/api/v1/players/' + FPlayerUUID + '/proof-of-play';

  if PostJson(URL, BatchJson, ResponseStr) then
  begin
    // Se o backend confirmou o lote, remove os registros já enviados
    FProofOfPlay.ConfirmSentBatch(50);
    Result := True;
  end
  else
    Result := False;
end;

function TSyncWorkerThread.PerformSync: Boolean;
var
  URL, ResponseJson: string;
  Parser: TJSONParser;
  RootObj: TJSONObject;
  RequiredArr: TJSONArray;
  ItemObj: TJSONObject;
  i: Integer;
  MD5Hash, FileName, DownloadURL: string;
  ActiveHashes: TStringList;
  AllDownloadedOk: Boolean;
begin
  Result := False;
  URL := FServerBaseURL + '/api/v1/players/' + FPlayerUUID + '/sync';

  if not GetJson(URL, ResponseJson) then Exit;

  // Se a grade for idêntica à que já temos, não precisa reprocessar
  if ResponseJson = FLastSyncScheduleJson then
  begin
    Result := True;
    Exit;
  end;

  Parser := TJSONParser.Create(ResponseJson);
  ActiveHashes := TStringList.Create;
  try
    try
      RootObj := TJSONObject(Parser.Parse);
      if RootObj = nil then Exit;
      try
        // Lista de mídias requeridas
        RequiredArr := RootObj.Get('required_medias', TJSONArray(nil));
        AllDownloadedOk := True;

        if RequiredArr <> nil then
        begin
          for i := 0 to RequiredArr.Count - 1 do
          begin
            ItemObj := RequiredArr.Objects[i];
            MD5Hash := ItemObj.Get('hash_md5', '');
            FileName := ItemObj.Get('filename', '');
            DownloadURL := ItemObj.Get('download_url', '');

            ActiveHashes.Add(MD5Hash);

            FTempStatusMsg := Format('Baixando mídia (%d/%d): %s', [i + 1, RequiredArr.Count, FileName]);
            Synchronize(@DoNotifyStatus);

            // Realiza o download se não estiver em cache
            if not FCacheManager.IsMediaCached(MD5Hash, FileName) then
            begin
              if not FCacheManager.DownloadMedia(DownloadURL, MD5Hash, FileName) then
              begin
                AllDownloadedOk := False;
              end;
            end;
          end;
        end;

        // Limpeza de mídias obsoletas que saíram da grade
        FCacheManager.CleanObsoleteMedia(ActiveHashes);

        // Se baixou tudo com sucesso, atualiza a grade em execução
        if AllDownloadedOk then
        begin
          FLastSyncScheduleJson := ResponseJson;
          FTempScheduleJson := ResponseJson;
          Synchronize(@DoNotifyScheduleUpdated);
          Result := True;
        end;

      finally
        RootObj.Free;
      end;
    except
      on E: Exception do
        Result := False;
    end;
  finally
    ActiveHashes.Free;
    Parser.Free;
  end;
end;

procedure TSyncWorkerThread.Execute;
var
  HeartbeatTicks, SyncTicks: Integer;
begin
  HeartbeatTicks := 0;
  SyncTicks := 0;

  while not Terminated do
  begin
    // 1. Telemetria Heartbeat
    if HeartbeatTicks >= FHeartbeatIntervalSec then
    begin
      PerformHeartbeat;
      HeartbeatTicks := 0;
    end;

    // 2. Upload em lote de Proof-of-Play
    PerformProofOfPlayUpload;

    // 3. Sincronização de Grade e Mídias
    if SyncTicks >= FSyncIntervalSec then
    begin
      FTempStatusMsg := 'Verificando atualizações de grade...';
      Synchronize(@DoNotifyStatus);
      PerformSync;
      SyncTicks := 0;
    end;

    // Dorme 1 segundo por iteração
    Sleep(1000);
    Inc(HeartbeatTicks);
    Inc(SyncTicks);
  end;
end;

end.
