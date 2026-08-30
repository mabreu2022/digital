unit uPlayerConfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles;

type
  { TPlayerConfig - Gerenciador de configurações locais do Player }
  TPlayerConfig = class
  private
    FConfigFile: string;
    FPlayerUUID: string;
    FPlayerName: string;
    FServerURL: string;
    FCacheDirectory: string;
    FVolume: Integer;
    FHeartbeatIntervalSec: Integer;
    FSyncIntervalSec: Integer;
    FAdminPassword: string;
    FShowOSD: Boolean;
    
    function GenerateUUID: string;
  public
    constructor Create(const AConfigFilePath: string = '');
    
    procedure Load;
    procedure Save;
    
    property PlayerUUID: string read FPlayerUUID write FPlayerUUID;
    property PlayerName: string read FPlayerName write FPlayerName;
    property ServerURL: string read FServerURL write FServerURL;
    property CacheDirectory: string read FCacheDirectory write FCacheDirectory;
    property Volume: Integer read FVolume write FVolume;
    property HeartbeatIntervalSec: Integer read FHeartbeatIntervalSec write FHeartbeatIntervalSec;
    property SyncIntervalSec: Integer read FSyncIntervalSec write FSyncIntervalSec;
    property AdminPassword: string read FAdminPassword write FAdminPassword;
    property ShowOSD: Boolean read FShowOSD write FShowOSD;
  end;

implementation

{ TPlayerConfig }

constructor TPlayerConfig.Create(const AConfigFilePath: string);
begin
  inherited Create;
  if AConfigFilePath <> '' then
    FConfigFile := AConfigFilePath
  else
    FConfigFile := ExtractFilePath(ParamStr(0)) + 'player_config.ini';

  // Valores padrão
  FPlayerUUID := '';
  FPlayerName := 'Player Display 01';
  FServerURL := 'http://127.0.0.1:8080';
  FCacheDirectory := ExtractFilePath(ParamStr(0)) + 'cache' + PathDelim + 'media' + PathDelim;
  FVolume := 100;
  FHeartbeatIntervalSec := 15;
  FSyncIntervalSec := 60;
  FAdminPassword := 'admin123';
  FShowOSD := False;

  Load;
end;

function TPlayerConfig.GenerateUUID: string;
var
  Guid: TGUID;
begin
  CreateGUID(Guid);
  Result := LowerCase(GUIDToString(Guid));
  // Remover chaves { }
  if (Length(Result) > 2) and (Result[1] = '{') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

procedure TPlayerConfig.Load;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(FConfigFile);
  try
    FPlayerUUID := Ini.ReadString('General', 'PlayerUUID', '');
    if FPlayerUUID = '' then
    begin
      FPlayerUUID := GenerateUUID;
      Ini.WriteString('General', 'PlayerUUID', FPlayerUUID);
    end;

    FPlayerName := Ini.ReadString('General', 'PlayerName', FPlayerName);
    FServerURL := Ini.ReadString('Server', 'URL', FServerURL);
    FCacheDirectory := Ini.ReadString('Storage', 'CacheDir', FCacheDirectory);
    FVolume := Ini.ReadInteger('Audio', 'Volume', FVolume);
    FHeartbeatIntervalSec := Ini.ReadInteger('Sync', 'HeartbeatIntervalSec', FHeartbeatIntervalSec);
    FSyncIntervalSec := Ini.ReadInteger('Sync', 'SyncIntervalSec', FSyncIntervalSec);
    FAdminPassword := Ini.ReadString('Security', 'AdminPassword', FAdminPassword);
    FShowOSD := Ini.ReadBool('Display', 'ShowOSD', FShowOSD);
  finally
    Ini.Free;
  end;
end;

procedure TPlayerConfig.Save;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(FConfigFile);
  try
    Ini.WriteString('General', 'PlayerUUID', FPlayerUUID);
    Ini.WriteString('General', 'PlayerName', FPlayerName);
    Ini.WriteString('Server', 'URL', FServerURL);
    Ini.WriteString('Storage', 'CacheDir', FCacheDirectory);
    Ini.WriteInteger('Audio', 'Volume', FVolume);
    Ini.WriteInteger('Sync', 'HeartbeatIntervalSec', FHeartbeatIntervalSec);
    Ini.WriteInteger('Sync', 'SyncIntervalSec', FSyncIntervalSec);
    Ini.WriteString('Security', 'AdminPassword', FAdminPassword);
    Ini.WriteBool('Display', 'ShowOSD', FShowOSD);
  finally
    Ini.Free;
  end;
end;

end.
