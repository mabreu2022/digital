unit uLibVlcWrapper;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DynLibs, Controls
  {$IFDEF WINDOWS}
  , Windows
  {$ENDIF}
  {$IFDEF UNIX}
  , BaseUnix
  {$ENDIF};

type
  { Ponteiros opacos da libvlc }
  Plibvlc_instance_t     = Pointer;
  Plibvlc_media_t        = Pointer;
  Plibvlc_media_player_t = Pointer;
  Plibvlc_event_manager_t= Pointer;

  { Estados do Player libvlc }
  Tlibvlc_state_t = (
    libvlc_NothingSpecial = 0,
    libvlc_Opening        = 1,
    libvlc_Buffering      = 2,
    libvlc_Playing        = 3,
    libvlc_Paused         = 4,
    libvlc_Stopped        = 5,
    libvlc_Ended          = 6,
    libvlc_Error          = 7
  );

  { Eventos da libvlc }
  Tlibvlc_event_type_t = Integer;

  Plibvlc_event_t = ^Tlibvlc_event_t;
  Tlibvlc_event_t = record
    event_type: Tlibvlc_event_type_t;
    p_obj: Pointer;
  end;

  Tlibvlc_callback_t = procedure(p_event: Plibvlc_event_t; p_data: Pointer); cdecl;

  { Assinaturas de funções da libvlc }
  Tlibvlc_new = function(argc: Integer; argv: PPAnsiChar): Plibvlc_instance_t; cdecl;
  Tlibvlc_release = procedure(p_instance: Plibvlc_instance_t); cdecl;
  Tlibvlc_get_version = function(): PAnsiChar; cdecl;

  Tlibvlc_media_new_path = function(p_instance: Plibvlc_instance_t; path: PAnsiChar): Plibvlc_media_t; cdecl;
  Tlibvlc_media_new_location = function(p_instance: Plibvlc_instance_t; psz_mrl: PAnsiChar): Plibvlc_media_t; cdecl;
  Tlibvlc_media_release = procedure(p_media: Plibvlc_media_t); cdecl;

  Tlibvlc_media_player_new_from_media = function(p_media: Plibvlc_media_t): Plibvlc_media_player_t; cdecl;
  Tlibvlc_media_player_release = procedure(p_mi: Plibvlc_media_player_t); cdecl;

  Tlibvlc_media_player_play = function(p_mi: Plibvlc_media_player_t): Integer; cdecl;
  Tlibvlc_media_player_stop = procedure(p_mi: Plibvlc_media_player_t); cdecl;
  Tlibvlc_media_player_pause = procedure(p_mi: Plibvlc_media_player_t); cdecl;
  Tlibvlc_media_player_is_playing = function(p_mi: Plibvlc_media_player_t): Integer; cdecl;
  Tlibvlc_media_player_get_state = function(p_mi: Plibvlc_media_player_t): Tlibvlc_state_t; cdecl;
  Tlibvlc_media_player_get_length = function(p_mi: Plibvlc_media_player_t): Int64; cdecl;
  Tlibvlc_media_player_get_time = function(p_mi: Plibvlc_media_player_t): Int64; cdecl;
  Tlibvlc_media_player_set_time = procedure(p_mi: Plibvlc_media_player_t; i_time: Int64); cdecl;

  Tlibvlc_media_player_set_hwnd = procedure(p_mi: Plibvlc_media_player_t; drawable: Pointer); cdecl;
  Tlibvlc_media_player_set_xwindow = procedure(p_mi: Plibvlc_media_player_t; drawable: Cardinal); cdecl;

  Tlibvlc_audio_set_volume = function(p_mi: Plibvlc_media_player_t; i_volume: Integer): Integer; cdecl;
  Tlibvlc_audio_get_volume = function(p_mi: Plibvlc_media_player_t): Integer; cdecl;

  Tlibvlc_media_player_event_manager = function(p_mi: Plibvlc_media_player_t): Plibvlc_event_manager_t; cdecl;
  Tlibvlc_event_attach = function(p_event_manager: Plibvlc_event_manager_t; i_event_type: Tlibvlc_event_type_t; f_callback: Tlibvlc_callback_t; user_data: Pointer): Integer; cdecl;
  Tlibvlc_event_detach = procedure(p_event_manager: Plibvlc_event_manager_t; i_event_type: Tlibvlc_event_type_t; f_callback: Tlibvlc_callback_t; user_data: Pointer); cdecl;

  { Constantes de eventos VLC }
  const
    libvlc_MediaPlayerMediaChanged      = $100;
    libvlc_MediaPlayerNothingSpecial    = $101;
    libvlc_MediaPlayerOpening           = $102;
    libvlc_MediaPlayerBuffering         = $103;
    libvlc_MediaPlayerPlaying           = $104;
    libvlc_MediaPlayerPaused            = $105;
    libvlc_MediaPlayerStopped           = $106;
    libvlc_MediaPlayerForward           = $107;
    libvlc_MediaPlayerBackward          = $108;
    libvlc_MediaPlayerEndReached        = $109;
    libvlc_MediaPlayerEncounteredError  = $10a;
    libvlc_MediaPlayerTimeChanged       = $10b;
    libvlc_MediaPlayerPositionChanged   = $10c;

type
  { Eventos Pascal }
  TOnMediaEndEvent = procedure(Sender: TObject) of object;
  TOnMediaErrorEvent = procedure(Sender: TObject; const AErrorMsg: string) of object;

  { TLibVlcEngine - Gerenciador singleton da biblioteca libvlc }
  TLibVlcEngine = class
  private
    FLibHandle: TLibHandle;
    FInstance: Plibvlc_instance_t;
    FIsLoaded: Boolean;
    FVersion: string;
    procedure LoadFunctions;
  public
    libvlc_new: Tlibvlc_new;
    libvlc_release: Tlibvlc_release;
    libvlc_get_version: Tlibvlc_get_version;
    libvlc_media_new_path: Tlibvlc_media_new_path;
    libvlc_media_new_location: Tlibvlc_media_new_location;
    libvlc_media_release: Tlibvlc_media_release;
    libvlc_media_player_new_from_media: Tlibvlc_media_player_new_from_media;
    libvlc_media_player_release: Tlibvlc_media_player_release;
    libvlc_media_player_play: Tlibvlc_media_player_play;
    libvlc_media_player_stop: Tlibvlc_media_player_stop;
    libvlc_media_player_pause: Tlibvlc_media_player_pause;
    libvlc_media_player_is_playing: Tlibvlc_media_player_is_playing;
    libvlc_media_player_get_state: Tlibvlc_media_player_get_state;
    libvlc_media_player_get_length: Tlibvlc_media_player_get_length;
    libvlc_media_player_get_time: Tlibvlc_media_player_get_time;
    libvlc_media_player_set_time: Tlibvlc_media_player_set_time;
    libvlc_media_player_set_hwnd: Tlibvlc_media_player_set_hwnd;
    libvlc_media_player_set_xwindow: Tlibvlc_media_player_set_xwindow;
    libvlc_audio_set_volume: Tlibvlc_audio_set_volume;
    libvlc_audio_get_volume: Tlibvlc_audio_get_volume;
    libvlc_media_player_event_manager: Tlibvlc_media_player_event_manager;
    libvlc_event_attach: Tlibvlc_event_attach;
    libvlc_event_detach: Tlibvlc_event_detach;

    constructor Create;
    destructor Destroy; override;
    function Initialize(const AExtraArgs: array of string): Boolean;
    procedure Finalize;
    property IsLoaded: Boolean read FIsLoaded;
    property Instance: Plibvlc_instance_t read FInstance;
    property Version: string read FVersion;
  end;

  { TLibVlcPlayer - Reprodutor de mídia vinculado a um WinControl LCL }
  TLibVlcPlayer = class
  private
    FEngine: TLibVlcEngine;
    FMediaPlayer: Plibvlc_media_player_t;
    FCurrentMedia: Plibvlc_media_t;
    FDisplayControl: TWinControl;
    FCurrentFile: string;
    FOnMediaEnd: TOnMediaEndEvent;
    FOnMediaError: TOnMediaErrorEvent;
    procedure BindDisplayHandle;
    procedure SetupEvents;
    procedure DoMediaEnd;
    procedure DoMediaError;
  public
    constructor Create(AEngine: TLibVlcEngine; ADisplayControl: TWinControl);
    destructor Destroy; override;
    
    function PlayFile(const AFilePath: string): Boolean;
    function PlayURL(const AURL: string): Boolean;
    procedure Stop;
    procedure Pause;
    procedure Resume;
    
    function GetState: Tlibvlc_state_t;
    function IsPlaying: Boolean;
    function GetDurationMs: Int64;
    function GetCurrentTimeMs: Int64;
    procedure SetVolume(AVolumePercent: Integer); // 0 a 100
    
    property CurrentFile: string read FCurrentFile;
    property DisplayControl: TWinControl read FDisplayControl write FDisplayControl;
    property OnMediaEnd: TOnMediaEndEvent read FOnMediaEnd write FOnMediaEnd;
    property OnMediaError: TOnMediaErrorEvent read FOnMediaError write FOnMediaError;
  end;

implementation

{ Callback CDecl chamado pela libvlc em outra thread }
procedure VlcEventCallback(p_event: Plibvlc_event_t; p_data: Pointer); cdecl;
var
  Player: TLibVlcPlayer;
begin
  if (p_event = nil) or (p_data = nil) then Exit;
  Player := TLibVlcPlayer(p_data);

  case p_event^.event_type of
    libvlc_MediaPlayerEndReached:
    begin
      TThread.Queue(nil, @Player.DoMediaEnd);
    end;
    libvlc_MediaPlayerEncounteredError:
    begin
      TThread.Queue(nil, @Player.DoMediaError);
    end;
  end;
end;

{ TLibVlcEngine }

constructor TLibVlcEngine.Create;
begin
  inherited Create;
  FLibHandle := NilHandle;
  FInstance := nil;
  FIsLoaded := False;
end;

destructor TLibVlcEngine.Destroy;
begin
  Finalize;
  inherited Destroy;
end;

procedure TLibVlcEngine.LoadFunctions;
begin
  Pointer(libvlc_new) := GetProcedureAddress(FLibHandle, 'libvlc_new');
  Pointer(libvlc_release) := GetProcedureAddress(FLibHandle, 'libvlc_release');
  Pointer(libvlc_get_version) := GetProcedureAddress(FLibHandle, 'libvlc_get_version');

  Pointer(libvlc_media_new_path) := GetProcedureAddress(FLibHandle, 'libvlc_media_new_path');
  Pointer(libvlc_media_new_location) := GetProcedureAddress(FLibHandle, 'libvlc_media_new_location');
  Pointer(libvlc_media_release) := GetProcedureAddress(FLibHandle, 'libvlc_media_release');

  Pointer(libvlc_media_player_new_from_media) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_new_from_media');
  Pointer(libvlc_media_player_release) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_release');

  Pointer(libvlc_media_player_play) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_play');
  Pointer(libvlc_media_player_stop) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_stop');
  Pointer(libvlc_media_player_pause) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_pause');
  Pointer(libvlc_media_player_is_playing) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_is_playing');
  Pointer(libvlc_media_player_get_state) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_get_state');
  Pointer(libvlc_media_player_get_length) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_get_length');
  Pointer(libvlc_media_player_get_time) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_get_time');
  Pointer(libvlc_media_player_set_time) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_set_time');

  Pointer(libvlc_media_player_set_hwnd) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_set_hwnd');
  Pointer(libvlc_media_player_set_xwindow) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_set_xwindow');

  Pointer(libvlc_audio_set_volume) := GetProcedureAddress(FLibHandle, 'libvlc_audio_set_volume');
  Pointer(libvlc_audio_get_volume) := GetProcedureAddress(FLibHandle, 'libvlc_audio_get_volume');

  Pointer(libvlc_media_player_event_manager) := GetProcedureAddress(FLibHandle, 'libvlc_media_player_event_manager');
  Pointer(libvlc_event_attach) := GetProcedureAddress(FLibHandle, 'libvlc_event_attach');
  Pointer(libvlc_event_detach) := GetProcedureAddress(FLibHandle, 'libvlc_event_detach');
end;

function TLibVlcEngine.Initialize(const AExtraArgs: array of string): Boolean;
var
  LibNames: array of string;
  i: Integer;
  ArgsList: TStringList;
  VlcArgs: array of PAnsiChar;
  AnsiStrings: array of AnsiString;
begin
  Result := False;
  if FIsLoaded then Exit(True);

  // Lista de bibliotecas candidatas por SO
  {$IFDEF WINDOWS}
  SetLength(LibNames, 3);
  LibNames[0] := 'libvlc.dll';
  LibNames[1] := 'C:\Program Files\VideoLAN\VLC\libvlc.dll';
  LibNames[2] := 'C:\Program Files (x86)\VideoLAN\VLC\libvlc.dll';
  {$ENDIF}
  {$IFDEF UNIX}
  SetLength(LibNames, 6);
  LibNames[0] := 'libvlc.so.5';
  LibNames[1] := 'libvlc.so';
  LibNames[2] := '/usr/lib/x86_64-linux-gnu/libvlc.so.5';
  LibNames[3] := '/usr/lib/x86_64-linux-gnu/libvlc.so';
  LibNames[4] := '/usr/lib/libvlc.so.5';
  LibNames[5] := '/usr/lib/libvlc.so';
  {$ENDIF}

  for i := 0 to High(LibNames) do
  begin
    FLibHandle := LoadLibrary(LibNames[i]);
    if FLibHandle <> NilHandle then
      Break;
  end;

  if FLibHandle = NilHandle then
    Exit(False);

  LoadFunctions;

  // Montar argumentos otimizados para Digital Signage (Hardware Acceleration)
  ArgsList := TStringList.Create;
  try
    ArgsList.Add('--no-video-title-show');  // Não exibir título do vídeo
    ArgsList.Add('--avcodec-hw=any');       // Habilitar aceleração por hardware
    ArgsList.Add('--quiet');                // Reduzir ruído de logs
    ArgsList.Add('--network-caching=2000'); // Cache de rede para streams

    for i := 0 to High(AExtraArgs) do
      ArgsList.Add(AExtraArgs[i]);

    SetLength(VlcArgs, ArgsList.Count);
    SetLength(AnsiStrings, ArgsList.Count);
    for i := 0 to ArgsList.Count - 1 do
    begin
      AnsiStrings[i] := AnsiString(ArgsList[i]);
      VlcArgs[i] := PAnsiChar(AnsiStrings[i]);
    end;

    if Assigned(libvlc_new) then
      FInstance := libvlc_new(ArgsList.Count, @VlcArgs[0]);

    if FInstance <> nil then
    begin
      FIsLoaded := True;
      if Assigned(libvlc_get_version) then
        FVersion := string(libvlc_get_version());
      Result := True;
    end;
  finally
    ArgsList.Free;
  end;
end;

procedure TLibVlcEngine.Finalize;
begin
  if FInstance <> nil then
  begin
    if Assigned(libvlc_release) then
      libvlc_release(FInstance);
    FInstance := nil;
  end;

  if FLibHandle <> NilHandle then
  begin
    UnloadLibrary(FLibHandle);
    FLibHandle := NilHandle;
  end;

  FIsLoaded := False;
end;

{ TLibVlcPlayer }

constructor TLibVlcPlayer.Create(AEngine: TLibVlcEngine; ADisplayControl: TWinControl);
begin
  inherited Create;
  FEngine := AEngine;
  FDisplayControl := ADisplayControl;
  FMediaPlayer := nil;
  FCurrentMedia := nil;
  FCurrentFile := '';
end;

destructor TLibVlcPlayer.Destroy;
begin
  Stop;
  inherited Destroy;
end;

procedure TLibVlcPlayer.BindDisplayHandle;
begin
  if (FMediaPlayer = nil) or (FDisplayControl = nil) then Exit;

  {$IFDEF WINDOWS}
  if Assigned(FEngine.libvlc_media_player_set_hwnd) then
    FEngine.libvlc_media_player_set_hwnd(FMediaPlayer, Pointer(FDisplayControl.Handle));
  {$ENDIF}

  {$IFDEF UNIX}
  if Assigned(FEngine.libvlc_media_player_set_xwindow) then
    FEngine.libvlc_media_player_set_xwindow(FMediaPlayer, Cardinal(FDisplayControl.Handle));
  {$ENDIF}
end;

procedure TLibVlcPlayer.SetupEvents;
var
  EvtMgr: Plibvlc_event_manager_t;
begin
  if (FMediaPlayer = nil) or not Assigned(FEngine.libvlc_media_player_event_manager) then Exit;

  EvtMgr := FEngine.libvlc_media_player_event_manager(FMediaPlayer);
  if EvtMgr <> nil then
  begin
    FEngine.libvlc_event_attach(EvtMgr, libvlc_MediaPlayerEndReached, @VlcEventCallback, Pointer(Self));
    FEngine.libvlc_event_attach(EvtMgr, libvlc_MediaPlayerEncounteredError, @VlcEventCallback, Pointer(Self));
  end;
end;

function TLibVlcPlayer.PlayFile(const AFilePath: string): Boolean;
var
  AnsiPath: AnsiString;
begin
  Result := False;
  if not FEngine.IsLoaded or (FEngine.Instance = nil) then Exit;
  if not FileExists(AFilePath) then Exit;

  Stop;

  AnsiPath := AnsiString(AFilePath);
  FCurrentMedia := FEngine.libvlc_media_new_path(FEngine.Instance, PAnsiChar(AnsiPath));
  if FCurrentMedia = nil then Exit;

  FMediaPlayer := FEngine.libvlc_media_player_new_from_media(FCurrentMedia);
  // Liberar a referência da mídia após criar o player
  FEngine.libvlc_media_release(FCurrentMedia);
  FCurrentMedia := nil;

  if FMediaPlayer = nil then Exit;

  BindDisplayHandle;
  SetupEvents;

  FEngine.libvlc_media_player_play(FMediaPlayer);
  FCurrentFile := AFilePath;
  Result := True;
end;

function TLibVlcPlayer.PlayURL(const AURL: string): Boolean;
var
  AnsiURL: AnsiString;
begin
  Result := False;
  if not FEngine.IsLoaded or (FEngine.Instance = nil) then Exit;

  Stop;

  AnsiURL := AnsiString(AURL);
  FCurrentMedia := FEngine.libvlc_media_new_location(FEngine.Instance, PAnsiChar(AnsiURL));
  if FCurrentMedia = nil then Exit;

  FMediaPlayer := FEngine.libvlc_media_player_new_from_media(FCurrentMedia);
  FEngine.libvlc_media_release(FCurrentMedia);
  FCurrentMedia := nil;

  if FMediaPlayer = nil then Exit;

  BindDisplayHandle;
  SetupEvents;

  FEngine.libvlc_media_player_play(FMediaPlayer);
  FCurrentFile := AURL;
  Result := True;
end;

procedure TLibVlcPlayer.DoMediaEnd;
begin
  if Assigned(FOnMediaEnd) then
    FOnMediaEnd(Self);
end;

procedure TLibVlcPlayer.DoMediaError;
begin
  if Assigned(FOnMediaError) then
    FOnMediaError(Self, 'Erro de reprodução LibVLC');
end;

procedure TLibVlcPlayer.Stop;
var
  EvtMgr: Plibvlc_event_manager_t;
begin
  if FMediaPlayer <> nil then
  begin
    if Assigned(FEngine.libvlc_media_player_event_manager) and Assigned(FEngine.libvlc_event_detach) then
    begin
      EvtMgr := FEngine.libvlc_media_player_event_manager(FMediaPlayer);
      if EvtMgr <> nil then
      begin
        FEngine.libvlc_event_detach(EvtMgr, libvlc_MediaPlayerEndReached, @VlcEventCallback, Pointer(Self));
        FEngine.libvlc_event_detach(EvtMgr, libvlc_MediaPlayerEncounteredError, @VlcEventCallback, Pointer(Self));
      end;
    end;

    if Assigned(FEngine.libvlc_media_player_stop) then
      FEngine.libvlc_media_player_stop(FMediaPlayer);

    {$IFDEF UNIX}
    if Assigned(FEngine.libvlc_media_player_set_xwindow) then
      FEngine.libvlc_media_player_set_xwindow(FMediaPlayer, 0);
    {$ENDIF}
    {$IFDEF WINDOWS}
    if Assigned(FEngine.libvlc_media_player_set_hwnd) then
      FEngine.libvlc_media_player_set_hwnd(FMediaPlayer, nil);
    {$ENDIF}

    if Assigned(FEngine.libvlc_media_player_release) then
      FEngine.libvlc_media_player_release(FMediaPlayer);

    FMediaPlayer := nil;
  end;
  FCurrentFile := '';
end;

procedure TLibVlcPlayer.Pause;
begin
  if (FMediaPlayer <> nil) and Assigned(FEngine.libvlc_media_player_pause) then
    FEngine.libvlc_media_player_pause(FMediaPlayer);
end;

procedure TLibVlcPlayer.Resume;
begin
  if (FMediaPlayer <> nil) and Assigned(FEngine.libvlc_media_player_play) then
    FEngine.libvlc_media_player_play(FMediaPlayer);
end;

function TLibVlcPlayer.GetState: Tlibvlc_state_t;
begin
  if (FMediaPlayer <> nil) and Assigned(FEngine.libvlc_media_player_get_state) then
    Result := FEngine.libvlc_media_player_get_state(FMediaPlayer)
  else
    Result := libvlc_Stopped;
end;

function TLibVlcPlayer.IsPlaying: Boolean;
begin
  if (FMediaPlayer <> nil) and Assigned(FEngine.libvlc_media_player_is_playing) then
    Result := (FEngine.libvlc_media_player_is_playing(FMediaPlayer) = 1)
  else
    Result := False;
end;

function TLibVlcPlayer.GetDurationMs: Int64;
begin
  if (FMediaPlayer <> nil) and Assigned(FEngine.libvlc_media_player_get_length) then
    Result := FEngine.libvlc_media_player_get_length(FMediaPlayer)
  else
    Result := 0;
end;

function TLibVlcPlayer.GetCurrentTimeMs: Int64;
begin
  if (FMediaPlayer <> nil) and Assigned(FEngine.libvlc_media_player_get_time) then
    Result := FEngine.libvlc_media_player_get_time(FMediaPlayer)
  else
    Result := 0;
end;

procedure TLibVlcPlayer.SetVolume(AVolumePercent: Integer);
begin
  if AVolumePercent < 0 then AVolumePercent := 0;
  if AVolumePercent > 100 then AVolumePercent := 100;

  if (FMediaPlayer <> nil) and Assigned(FEngine.libvlc_audio_set_volume) then
    FEngine.libvlc_audio_set_volume(FMediaPlayer, AVolumePercent);
end;

end.
