unit uProofOfPlay;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpjson, jsonparser, syncobjs;

type
  { Registro individual de Proof of Play }
  TProofOfPlayRecord = record
    MediaID: Int64;
    PlaylistID: Int64;
    StartDateTime: TDateTime;
    EndDateTime: TDateTime;
    DurationSeconds: Integer;
    Status: string; // 'COMPLETED', 'INTERRUPTED', 'ERROR'
    ErrorMessage: string;
  end;

  { TProofOfPlayManager - Buffer thread-safe de telemetria offline }
  TProofOfPlayManager = class
  private
    FStorageFile: string;
    FLock: TCriticalSection;
    FBuffer: array of TProofOfPlayRecord;
    procedure LoadFromDisk;
    procedure SaveToDisk;
  public
    constructor Create(const AStoragePath: string);
    destructor Destroy; override;

    // Registra uma exibição de mídia concluída ou interrompida
    procedure LogPlayback(AMediaID, APlaylistID: Int64; AStartedAt, AEndedAt: TDateTime; 
      ADurationSec: Integer; const AStatus: string = 'COMPLETED'; const AError: string = '');

    // Exporta o lote atual para formato JSON pronto para envio REST
    function ExportBatchJson(AMaxRecords: Integer = 50): string;

    // Confirma o envio bem-sucedido e remove os registros processados do buffer
    procedure ConfirmSentBatch(ACount: Integer);

    // Quantidade de registros pendentes na fila
    function PendingCount: Integer;
  end;

implementation

{ TProofOfPlayManager }

constructor TProofOfPlayManager.Create(const AStoragePath: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FStorageFile := IncludeTrailingPathDelimiter(AStoragePath) + 'pop_buffer.json';
  SetLength(FBuffer, 0);
  LoadFromDisk;
end;

destructor TProofOfPlayManager.Destroy;
begin
  SaveToDisk;
  FLock.Free;
  inherited Destroy;
end;

procedure TProofOfPlayManager.LogPlayback(AMediaID, APlaylistID: Int64; 
  AStartedAt, AEndedAt: TDateTime; ADurationSec: Integer; 
  const AStatus: string; const AError: string);
var
  Idx: Integer;
begin
  FLock.Enter;
  try
    Idx := Length(FBuffer);
    SetLength(FBuffer, Idx + 1);

    FBuffer[Idx].MediaID := AMediaID;
    FBuffer[Idx].PlaylistID := APlaylistID;
    FBuffer[Idx].StartDateTime := AStartedAt;
    FBuffer[Idx].EndDateTime := AEndedAt;
    FBuffer[Idx].DurationSeconds := ADurationSec;
    FBuffer[Idx].Status := AStatus;
    FBuffer[Idx].ErrorMessage := AError;

    SaveToDisk;
  finally
    FLock.Leave;
  end;
end;

function TProofOfPlayManager.ExportBatchJson(AMaxRecords: Integer): string;
var
  RootArr: TJSONArray;
  ItemObj: TJSONObject;
  i, Limit: Integer;
begin
  Result := '[]';
  FLock.Enter;
  try
    if Length(FBuffer) = 0 then Exit;

    Limit := Length(FBuffer);
    if (AMaxRecords > 0) and (Limit > AMaxRecords) then
      Limit := AMaxRecords;

    RootArr := TJSONArray.Create;
    try
      for i := 0 to Limit - 1 do
      begin
        ItemObj := TJSONObject.Create;
        ItemObj.Add('media_id', FBuffer[i].MediaID);
        ItemObj.Add('playlist_id', FBuffer[i].PlaylistID);
        ItemObj.Add('start_time', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', FBuffer[i].StartDateTime));
        ItemObj.Add('end_time', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', FBuffer[i].EndDateTime));
        ItemObj.Add('seconds_played', FBuffer[i].DurationSeconds);
        ItemObj.Add('status', FBuffer[i].Status);
        ItemObj.Add('error_message', FBuffer[i].ErrorMessage);

        RootArr.Add(ItemObj);
      end;

      Result := RootArr.AsJSON;
    finally
      RootArr.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TProofOfPlayManager.ConfirmSentBatch(ACount: Integer);
var
  Total, Remaining, i: Integer;
begin
  FLock.Enter;
  try
    Total := Length(FBuffer);
    if ACount >= Total then
    begin
      SetLength(FBuffer, 0);
    end
    else
    begin
      Remaining := Total - ACount;
      for i := 0 to Remaining - 1 do
        FBuffer[i] := FBuffer[i + ACount];
      SetLength(FBuffer, Remaining);
    end;
    SaveToDisk;
  finally
    FLock.Leave;
  end;
end;

function TProofOfPlayManager.PendingCount: Integer;
begin
  FLock.Enter;
  try
    Result := Length(FBuffer);
  finally
    FLock.Leave;
  end;
end;

procedure TProofOfPlayManager.LoadFromDisk;
var
  SL: TStringList;
  Parser: TJSONParser;
  RootArr: TJSONArray;
  ItemObj: TJSONObject;
  i: Integer;
begin
  if not FileExists(FStorageFile) then Exit;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(FStorageFile);
    if SL.Text.Trim = '' then Exit;

    Parser := TJSONParser.Create(SL.Text);
    try
      RootArr := TJSONArray(Parser.Parse);
      if RootArr = nil then Exit;
      try
        SetLength(FBuffer, RootArr.Count);
        for i := 0 to RootArr.Count - 1 do
        begin
          ItemObj := RootArr.Objects[i];
          FBuffer[i].MediaID := ItemObj.Get('media_id', Int64(0));
          FBuffer[i].PlaylistID := ItemObj.Get('playlist_id', Int64(0));
          FBuffer[i].StartDateTime := ScanDateTime('yyyy-mm-dd"T"hh:nn:ss', ItemObj.Get('start_time', '2026-01-01T00:00:00'));
          FBuffer[i].EndDateTime := ScanDateTime('yyyy-mm-dd"T"hh:nn:ss', ItemObj.Get('end_time', '2026-01-01T00:00:00'));
          FBuffer[i].DurationSeconds := ItemObj.Get('seconds_played', 0);
          FBuffer[i].Status := ItemObj.Get('status', 'COMPLETED');
          FBuffer[i].ErrorMessage := ItemObj.Get('error_message', '');
        end;
      finally
        RootArr.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TProofOfPlayManager.SaveToDisk;
var
  SL: TStringList;
  JsonText: string;
begin
  JsonText := ExportBatchJson(0);
  SL := TStringList.Create;
  try
    SL.Text := JsonText;
    SL.SaveToFile(FStorageFile);
  finally
    SL.Free;
  end;
end;

end.
