unit uCacheManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, md5, fphttpclient, opensslsockets;

type
  { Evento de progresso de download }
  TOnDownloadProgress = procedure(Sender: TObject; const AFileName: string; ABytesRead, ATotalBytes: Int64) of object;
  TOnDownloadCompleted = procedure(Sender: TObject; const AFileName: string; ASuccess: Boolean; const AError: string) of object;

  { TCacheManager - Gerenciamento de Cache Local Offline e Integridade MD5 }
  TCacheManager = class
  private
    FCachePath: string;
    FOnProgress: TOnDownloadProgress;
    FOnCompleted: TOnDownloadCompleted;
  public
    constructor Create(const ACustomCacheDir: string = '');
    destructor Destroy; override;

    // Calcula o MD5 de um arquivo local
    function CalculateFileMD5(const AFilePath: string): string;
    
    // Verifica se um arquivo existe no cache e se o MD5 coincide
    function IsMediaCached(const AMD5Hash, AFileName: string): Boolean;
    
    // Retorna o caminho absoluto do arquivo no cache
    function GetCachedFilePath(const AMD5Hash, AFileName: string): string;
    
    // Download síncrono de mídia com validação rigorosa de MD5
    function DownloadMedia(const AUrl, AMD5Expected, AFileName: string): Boolean;
    
    // Limpeza de mídias obsoletas não presentes na lista de hashes ativos
    procedure CleanObsoleteMedia(AActiveHashes: TStrings);
    
    // Retorna o espaço livre no disco em MegaBytes
    function GetFreeDiskSpaceMB: Int64;

    property CachePath: string read FCachePath;
    property OnProgress: TOnDownloadProgress read FOnProgress write FOnProgress;
    property OnCompleted: TOnDownloadCompleted read FOnCompleted write FOnCompleted;
  end;

implementation

{ TCacheManager }

constructor TCacheManager.Create(const ACustomCacheDir: string);
begin
  inherited Create;
  if ACustomCacheDir <> '' then
    FCachePath := IncludeTrailingPathDelimiter(ACustomCacheDir)
  else
  begin
    {$IFDEF WINDOWS}
    FCachePath := 'C:\DigitalSignage\Cache\media\';
    {$ELSE}
    FCachePath := '/var/cache/digitalsignage/media/';
    if not DirectoryExists('/var/cache') then
      FCachePath := IncludeTrailingPathDelimiter(GetUserDir) + '.digitalsignage/cache/media/';
    {$ENDIF}
  end;

  if not ForceDirectories(FCachePath) then
    // Fallback para diretório local da aplicação
    FCachePath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'cache' + PathDelim + 'media' + PathDelim;
  
  ForceDirectories(FCachePath);
end;

destructor TCacheManager.Destroy;
begin
  inherited Destroy;
end;

function TCacheManager.CalculateFileMD5(const AFilePath: string): string;
begin
  Result := '';
  if not FileExists(AFilePath) then Exit;
  try
    Result := MD5Print(MD5File(AFilePath));
  except
    Result := '';
  end;
end;

function TCacheManager.GetCachedFilePath(const AMD5Hash, AFileName: string): string;
var
  Ext: string;
begin
  Ext := ExtractFileExt(AFileName);
  // Padrão de nomenclatura: <HASH_MD5>.<extensao>
  Result := FCachePath + LowerCase(AMD5Hash) + Ext;
  if not FileExists(Result) then
  begin
    // Tenta pelo nome original caso exista
    if FileExists(FCachePath + AFileName) then
      Result := FCachePath + AFileName;
  end;
end;

function TCacheManager.IsMediaCached(const AMD5Hash, AFileName: string): Boolean;
var
  TargetFile: string;
  CalculatedMD5: string;
begin
  Result := False;
  TargetFile := GetCachedFilePath(AMD5Hash, AFileName);

  if not FileExists(TargetFile) then Exit;

  // Validação estrita de integridade via MD5
  CalculatedMD5 := CalculateFileMD5(TargetFile);
  Result := SameText(CalculatedMD5, AMD5Hash);
end;

function TCacheManager.DownloadMedia(const AUrl, AMD5Expected, AFileName: string): Boolean;
var
  Client: TFPHTTPClient;
  TempFile, FinalFile: string;
  CalculatedMD5: string;
  FileStream: TFileStream;
begin
  Result := False;
  if (AUrl = '') or (AMD5Expected = '') then Exit;

  // Se já estiver em cache válido, não baixa novamente
  if IsMediaCached(AMD5Expected, AFileName) then
  begin
    if Assigned(FOnCompleted) then
      FOnCompleted(Self, AFileName, True, '');
    Exit(True);
  end;

  FinalFile := GetCachedFilePath(AMD5Expected, AFileName);
  TempFile := FinalFile + '.part';

  Client := TFPHTTPClient.Create(nil);
  try
    Client.AllowRedirect := True;
    Client.IOTimeout := 30000; // 30 segundos

    FileStream := TFileStream.Create(TempFile, fmCreate);
    try
      try
        Client.Get(AUrl, FileStream);
      except
        on E: Exception do
        begin
          if Assigned(FOnCompleted) then
            FOnCompleted(Self, AFileName, False, E.Message);
          Exit(False);
        end;
      end;
    finally
      FileStream.Free;
    end;

    // Validar hash MD5 após o download
    CalculatedMD5 := CalculateFileMD5(TempFile);
    if SameText(CalculatedMD5, AMD5Expected) then
    begin
      if FileExists(FinalFile) then
        DeleteFile(FinalFile);
      RenameFile(TempFile, FinalFile);
      Result := True;
      if Assigned(FOnCompleted) then
        FOnCompleted(Self, AFileName, True, '');
    end
    else
    begin
      // Falha na integridade - descarta o arquivo corrompido
      DeleteFile(TempFile);
      if Assigned(FOnCompleted) then
        FOnCompleted(Self, AFileName, False, 'MD5 Checksum mismatch');
    end;
  finally
    Client.Free;
  end;
end;

procedure TCacheManager.CleanObsoleteMedia(AActiveHashes: TStrings);
var
  SearchRec: TSearchRec;
  FilePath, FileBaseName: string;
  i: Integer;
  IsReferenced: Boolean;
begin
  if (AActiveHashes = nil) or (AActiveHashes.Count = 0) then Exit;

  if FindFirst(FCachePath + '*.*', faAnyFile and not faDirectory, SearchRec) = 0 then
  begin
    try
      repeat
        FilePath := FCachePath + SearchRec.Name;
        FileBaseName := ChangeFileExt(SearchRec.Name, '');

        IsReferenced := False;
        for i := 0 to AActiveHashes.Count - 1 do
        begin
          if SameText(FileBaseName, AActiveHashes[i]) or SameText(SearchRec.Name, AActiveHashes[i]) then
          begin
            IsReferenced := True;
            Break;
          end;
        end;

        if not IsReferenced and not SameText(ExtractFileExt(SearchRec.Name), '.part') then
          DeleteFile(FilePath);

      until FindNext(SearchRec) <> 0;
    finally
      FindClose(SearchRec);
    end;
  end;
end;

function TCacheManager.GetFreeDiskSpaceMB: Int64;
begin
  Result := DiskFree(0) div (1024 * 1024);
end;

end.
