unit uDbManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, IBConnection, sqldb, db;

type
  { Configurações de conexão do Firebird 5.0 }
  TFirebirdConfig = record
    Host: string;
    Port: Integer;
    DatabaseName: string;
    User: string;
    Password: string;
    Charset: string;
    Dialect: Integer;
    ClientLibrary: string;
    ListenPort: Integer;
    MediaBaseURL: string;
  end;

  { TFirebirdConnectionManager - Gerenciador de conexões Firebird 5.0 }
  TFirebirdConnectionManager = class
  private
    FConfig: TFirebirdConfig;
    FConfigFile: string;
    procedure LoadConfiguration;
  public
    constructor Create(const AConfigFile: string = '');
    destructor Destroy; override;

    // Cria uma conexão isolada com transação configurada para Read Committed
    function CreateConnection(out ATransaction: TSQLTransaction): TIBConnection;
    
    // Testa a conectividade com o banco Firebird 5.0
    function TestConnection(out AErrorMessage: string): Boolean;

    property Config: TFirebirdConfig read FConfig;
  end;

var
  GDbManager: TFirebirdConnectionManager = nil;

implementation

{ TFirebirdConnectionManager }

constructor TFirebirdConnectionManager.Create(const AConfigFile: string);
begin
  inherited Create;
  if AConfigFile <> '' then
    FConfigFile := AConfigFile
  else
  begin
    if FileExists(ExtractFilePath(ParamStr(0)) + 'config' + PathDelim + 'database.ini') then
      FConfigFile := ExtractFilePath(ParamStr(0)) + 'config' + PathDelim + 'database.ini'
    else if FileExists(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'config' + PathDelim + 'database.ini') then
      FConfigFile := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'config' + PathDelim + 'database.ini'
    else
      FConfigFile := 'config' + PathDelim + 'database.ini';
  end;

  LoadConfiguration;
end;

destructor TFirebirdConnectionManager.Destroy;
begin
  inherited Destroy;
end;

procedure TFirebirdConnectionManager.LoadConfiguration;
var
  Ini: TIniFile;
begin
  // Valores padrão
  FConfig.Host := '127.0.0.1';
  FConfig.Port := 3050;
  FConfig.DatabaseName := '/opt/firebird/dados/digitalsign.fdb';
  FConfig.User := 'SYSDBA';
  FConfig.Password := 'masterkey';
  FConfig.Charset := 'UTF8';
  FConfig.Dialect := 3;
  {$IFDEF WINDOWS}
  FConfig.ClientLibrary := 'fbclient.dll';
  {$ELSE}
  FConfig.ClientLibrary := 'libfbclient.so';
  {$ENDIF}
  FConfig.ListenPort := 8080;
  FConfig.MediaBaseURL := 'http://127.0.0.1:8080/media';

  if FileExists(FConfigFile) then
  begin
    Ini := TIniFile.Create(FConfigFile);
    try
      FConfig.Host := Ini.ReadString('Database', 'Host', FConfig.Host);
      FConfig.Port := Ini.ReadInteger('Database', 'Port', FConfig.Port);
      FConfig.DatabaseName := Ini.ReadString('Database', 'DatabaseName', FConfig.DatabaseName);
      FConfig.User := Ini.ReadString('Database', 'User', FConfig.User);
      FConfig.Password := Ini.ReadString('Database', 'Password', FConfig.Password);
      FConfig.Charset := Ini.ReadString('Database', 'Charset', FConfig.Charset);
      FConfig.Dialect := Ini.ReadInteger('Database', 'Dialect', FConfig.Dialect);
      FConfig.ClientLibrary := Ini.ReadString('Database', 'ClientLibrary', FConfig.ClientLibrary);
      FConfig.ListenPort := Ini.ReadInteger('Server', 'ListenPort', FConfig.ListenPort);
      FConfig.MediaBaseURL := Ini.ReadString('Server', 'MediaBaseURL', FConfig.MediaBaseURL);
    finally
      Ini.Free;
    end;
  end;
end;

function TFirebirdConnectionManager.CreateConnection(out ATransaction: TSQLTransaction): TIBConnection;
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
begin
  Conn := TIBConnection.Create(nil);
  Trans := TSQLTransaction.Create(nil);

  Conn.HostName := FConfig.Host;
  Conn.DatabaseName := FConfig.DatabaseName;
  Conn.UserName := FConfig.User;
  Conn.Password := FConfig.Password;
  Conn.CharSet := FConfig.Charset;
  Conn.Dialect := FConfig.Dialect;

  // Configuração ideal de transação para Firebird 5.0 (Read Committed / Rec Version / No Wait)
  Trans.Database := Conn;
  Trans.Action := caCommitRetaining;
  Trans.Params.Clear;
  Trans.Params.Add('read_committed');
  Trans.Params.Add('rec_version');
  Trans.Params.Add('nowait');

  Conn.Transaction := Trans;

  ATransaction := Trans;
  Result := Conn;
end;

function TFirebirdConnectionManager.TestConnection(out AErrorMessage: string): Boolean;
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  Result := False;
  AErrorMessage := '';

  Conn := CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    try
      Qry.Database := Conn;
      Qry.Transaction := Trans;
      Conn.Connected := True;
      Qry.SQL.Text := 'SELECT RDB$GET_CONTEXT(''SYSTEM'', ''ENGINE_VERSION'') AS VER FROM RDB$DATABASE';
      Qry.Open;
      if not Qry.EOF then
      begin
        Result := True;
        AErrorMessage := 'Conectado com sucesso ao Firebird: ' + Qry.FieldByName('VER').AsString;
      end;
      Qry.Close;
      Trans.Commit;
      Conn.Connected := False;
    except
      on E: Exception do
      begin
        Result := False;
        AErrorMessage := E.Message;
        if Trans.Active then Trans.Rollback;
      end;
    end;
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

end.
