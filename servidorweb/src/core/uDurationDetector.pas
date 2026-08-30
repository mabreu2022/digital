unit uDurationDetector;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

function DetectVideoDuration(const AFilePath: string): Integer;

implementation

function DetectMp4Duration(const AFilePath: string): Integer;
var
  FS: TFileStream;
  AtomSize, AtomType: Cardinal;
  AtomTypeStr: string;
  Buf: array[0..3] of Byte;
  TimeScale, Duration: Cardinal;
  Version: Byte;
  FileLen, PosIdx: Int64;
begin
  Result := 0;
  if not FileExists(AFilePath) then Exit;

  try
    FS := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
    try
      FileLen := FS.Size;
      while FS.Position < FileLen - 8 do
      begin
        PosIdx := FS.Position;
        if FS.Read(Buf, 4) < 4 then Break;
        AtomSize := (Cardinal(Buf[0]) shl 24) or (Cardinal(Buf[1]) shl 16) or (Cardinal(Buf[2]) shl 8) or Cardinal(Buf[3]);

        if FS.Read(Buf, 4) < 4 then Break;
        SetLength(AtomTypeStr, 4);
        Move(Buf, AtomTypeStr[1], 4);

        if AtomSize = 0 then
          AtomSize := FileLen - PosIdx
        else if AtomSize = 1 then
        begin
          FS.Seek(PosIdx + 16, soFromBeginning);
          Continue;
        end;

        if AtomTypeStr = 'moov' then
        begin
          // Entrar no container moov
          Continue;
        end
        else if AtomTypeStr = 'mvhd' then
        begin
          // mvhd encontrado!
          Version := FS.ReadByte;
          FS.Seek(3, soFromCurrent); // flags

          if Version = 1 then
          begin
            FS.Seek(16, soFromCurrent); // creation & mod time (64-bit)
            if FS.Read(Buf, 4) < 4 then Break;
            TimeScale := (Cardinal(Buf[0]) shl 24) or (Cardinal(Buf[1]) shl 16) or (Cardinal(Buf[2]) shl 8) or Cardinal(Buf[3]);
            FS.Seek(4, soFromCurrent); // Pula alta de duration 64-bit
            if FS.Read(Buf, 4) < 4 then Break;
            Duration := (Cardinal(Buf[0]) shl 24) or (Cardinal(Buf[1]) shl 16) or (Cardinal(Buf[2]) shl 8) or Cardinal(Buf[3]);
          end
          else
          begin
            FS.Seek(8, soFromCurrent); // creation & mod time (32-bit)
            if FS.Read(Buf, 4) < 4 then Break;
            TimeScale := (Cardinal(Buf[0]) shl 24) or (Cardinal(Buf[1]) shl 16) or (Cardinal(Buf[2]) shl 8) or Cardinal(Buf[3]);
            if FS.Read(Buf, 4) < 4 then Break;
            Duration := (Cardinal(Buf[0]) shl 24) or (Cardinal(Buf[1]) shl 16) or (Cardinal(Buf[2]) shl 8) or Cardinal(Buf[3]);
          end;

          if (TimeScale > 0) and (Duration > 0) then
          begin
            Result := Round(Duration / TimeScale);
            if Result < 1 then Result := 1;
            Exit;
          end;
        end
        else
        begin
          // Pular outro átomo
          if (AtomSize > 8) and (PosIdx + AtomSize <= FileLen) then
            FS.Seek(PosIdx + AtomSize, soFromBeginning)
          else
            Break;
        end;
      end;
    finally
      FS.Free;
    end;
  except
    Result := 0;
  end;
end;

function DetectVideoDuration(const AFilePath: string): Integer;
var
  Ext: string;
begin
  Result := 0;
  if not FileExists(AFilePath) then Exit;

  Ext := LowerCase(ExtractFileExt(AFilePath));
  if (Ext = '.mp4') or (Ext = '.m4v') or (Ext = '.mov') then
  begin
    Result := DetectMp4Duration(AFilePath);
  end;

  if Result <= 0 then
    Result := 10; // Fallback seguro
end;

end.
