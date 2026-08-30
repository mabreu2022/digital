unit uMediaDurationDetector;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process;

{ Detecta a duração real de um arquivo de mídia em segundos }
function DetectVideoDurationSeconds(const AFilePath: string): Integer;

implementation

{ Lê um inteiro de 32 bits em Big-Endian a partir de um TStream }
function ReadBigEndianUInt32(AStream: TStream): Cardinal;
var
  Buf: array[0..3] of Byte;
begin
  if AStream.Read(Buf, 4) < 4 then
    Exit(0);
  Result := (Cardinal(Buf[0]) shl 24) or (Cardinal(Buf[1]) shl 16) or (Cardinal(Buf[2]) shl 8) or Cardinal(Buf[3]);
end;

{ Lê um inteiro de 64 bits em Big-Endian a partir de um TStream }
function ReadBigEndianUInt64(AStream: TStream): QWord;
var
  Buf: array[0..7] of Byte;
  i: Integer;
begin
  if AStream.Read(Buf, 8) < 8 then
    Exit(0);
  Result := 0;
  for i := 0 to 7 do
    Result := (Result shl 8) or QWord(Buf[i]);
end;

{ Tenta extrair a duração diretamente dos átomos 'moov' -> 'mvhd' de arquivos MP4/MOV/M4V }
function ExtractMp4Duration(const AFilePath: string): Integer;
var
  FS: TFileStream;
  AtomSize: Cardinal;
  AtomType: array[0..3] of AnsiChar;
  FileSize, EndMoovPos, MoovStartPos: Int64;
  Version: Byte;
  Timescale: Cardinal;
  Duration32: Cardinal;
  Duration64: QWord;
  FoundMoov, FoundMvhd: Boolean;
begin
  Result := 0;
  if not FileExists(AFilePath) then Exit;

  try
    FS := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
    try
      FileSize := FS.Size;
      FoundMoov := False;

      // 1. Procurar átomo 'moov'
      while FS.Position + 8 <= FileSize do
      begin
        AtomSize := ReadBigEndianUInt32(FS);
        if FS.Read(AtomType, 4) < 4 then Break;

        if AtomSize = 0 then
          AtomSize := FileSize - (FS.Position - 8);

        if AtomType = 'moov' then
        begin
          MoovStartPos := FS.Position - 8;
          EndMoovPos := MoovStartPos + AtomSize;
          if EndMoovPos > FileSize then EndMoovPos := FileSize;
          FoundMoov := True;
          Break;
        end;

        if AtomSize < 8 then Break;
        FS.Seek(AtomSize - 8, soFromCurrent);
      end;

      if not FoundMoov then Exit;

      // 2. Dentro de 'moov', procurar átomo 'mvhd'
      FoundMvhd := False;
      while (FS.Position + 8 <= EndMoovPos) do
      begin
        AtomSize := ReadBigEndianUInt32(FS);
        if FS.Read(AtomType, 4) < 4 then Break;

        if AtomType = 'mvhd' then
        begin
          FoundMvhd := True;
          // Ler versão (1 byte)
          if FS.Read(Version, 1) < 1 then Break;
          // Pular flags (3 bytes)
          FS.Seek(3, soFromCurrent);

          if Version = 0 then
          begin
            // Pular creation_time (4 bytes) e modification_time (4 bytes)
            FS.Seek(8, soFromCurrent);
            Timescale := ReadBigEndianUInt32(FS);
            Duration32 := ReadBigEndianUInt32(FS);
            if Timescale > 0 then
              Result := Round(Duration32 / Timescale);
          end
          else if Version = 1 then
          begin
            // Pular creation_time (8 bytes) e modification_time (8 bytes)
            FS.Seek(16, soFromCurrent);
            Timescale := ReadBigEndianUInt32(FS);
            Duration64 := ReadBigEndianUInt64(FS);
            if Timescale > 0 then
              Result := Round(Duration64 / Timescale);
          end;
          Break;
        end;

        if AtomSize < 8 then Break;
        FS.Seek(AtomSize - 8, soFromCurrent);
      end;

    finally
      FS.Free;
    end;
  except
    Result := 0;
  end;
end;

{ Tenta detectar duração via ferramenta externa ffprobe (se instalada no sistema) }
function ProbeWithFFProbe(const AFilePath: string): Integer;
var
  AProcess: TProcess;
  OutputLines: TStringList;
  DurFloat: Double;
  ValStr: string;
  FS: TFormatSettings;
begin
  Result := 0;
  AProcess := TProcess.Create(nil);
  OutputLines := TStringList.Create;
  try
    AProcess.Executable := 'ffprobe';
    AProcess.Parameters.Add('-v');
    AProcess.Parameters.Add('error');
    AProcess.Parameters.Add('-show_entries');
    AProcess.Parameters.Add('format=duration');
    AProcess.Parameters.Add('-of');
    AProcess.Parameters.Add('default=noprint_wrappers=1:nokey=1');
    AProcess.Parameters.Add(AFilePath);
    AProcess.Options := [poUsePipes, poStderrToOutPut, poWaitOnExit];

    try
      AProcess.Execute;
      OutputLines.LoadFromStream(AProcess.Output);
      if OutputLines.Count > 0 then
      begin
        ValStr := Trim(OutputLines[0]);
        FS := DefaultFormatSettings;
        FS.DecimalSeparator := '.';
        if TryStrToFloat(ValStr, DurFloat, FS) then
          Result := Round(DurFloat);
      end;
    except
      Result := 0;
    end;
  finally
    OutputLines.Free;
    AProcess.Free;
  end;
end;

function DetectVideoDurationSeconds(const AFilePath: string): Integer;
var
  Ext: string;
begin
  Result := 0;
  if not FileExists(AFilePath) then Exit(0);

  Ext := LowerCase(ExtractFileExt(AFilePath));

  // 1. Tentar parser nativo ultra-rápido para MP4, MOV, M4V
  if (Ext = '.mp4') or (Ext = '.mov') or (Ext = '.m4v') or (Ext = '.3gp') then
  begin
    Result := ExtractMp4Duration(AFilePath);
    if Result > 0 then Exit;
  end;

  // 2. Tentar via ffprobe se disponível no sistema
  Result := ProbeWithFFProbe(AFilePath);
  if Result > 0 then Exit;

  // 3. Fallback: retorna 0 (sinaliza aos players reprodução contínua até o fim do vídeo)
  Result := 0;
end;

end.
