unit uFrmPlayer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  LCLType, DateUtils,
  uKioskUtils, uLibVlcWrapper, uScheduler, uCacheManager, uProofOfPlay,
  uSyncWorker, uPlayerConfig;

type
  { TFrmPlayer - Formulário Principal do Player Digital Signage (Kiosk) }
  TFrmPlayer = class(TForm)
    pnlVideoCanvas: TPanel;
    imgStaticMedia: TImage;
    pnlOSD: TPanel;
    lblOSDTitle: TLabel;
    lblOSDStatus: TLabel;
    lblOSDClock: TLabel;
    tmrPlaybackTick: TTimer;
    tmrKioskWatchdog: TTimer;
    
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure tmrPlaybackTickTimer(Sender: TObject);
    procedure tmrKioskWatchdogTimer(Sender: TObject);
  private
    FConfig: TPlayerConfig;
    FVlcEngine: TLibVlcEngine;
    FVlcPlayer: TLibVlcPlayer;
    FScheduler: TSignageScheduler;
    FCacheManager: TCacheManager;
    FProofOfPlay: TProofOfPlayManager;
    FSyncWorker: TSyncWorkerThread;
    
    FCurrentItemRemainingSec: Integer;
    FCurrentMediaStartedAt: TDateTime;
    FCurrentMediaID: Int64;
    FCurrentPlaylistID: Int64;
    FCurrentMediaDurationSec: Integer;
    FIsVideoPlaying: Boolean;
    FCurrentStatusText: string;

    procedure InitializeSubsystems;
    procedure PlayNextScheduleItem;
    procedure ExecuteMedia(const AMedia: TScheduleMediaItem);
    procedure ShowStaticImage(const AFilePath: string);
    procedure HandleVlcMediaEnd(Sender: TObject);
    procedure HandleVlcMediaError(Sender: TObject; const AErrorMsg: string);
    
    procedure HandleScheduleUpdated(Sender: TObject; const ANewScheduleJson: string);
    procedure HandleSyncStatusChange(Sender: TObject; const AStatus: string);
    procedure UpdateOSDDisplay;
    procedure PromptAdminExit;
  public
  end;

var
  FrmPlayer: TFrmPlayer;

implementation

{$R *.lfm}

{ TFrmPlayer }

procedure TFrmPlayer.FormCreate(Sender: TObject);
begin
  // 1. Configurações de Janela Kiosk
  TKioskManager.ApplyKioskMode(Self);

  // 2. Inicializar componentes de layout
  Color := clBlack;
  pnlVideoCanvas.Align := alClient;
  pnlVideoCanvas.Color := clBlack;
  pnlVideoCanvas.BevelOuter := bvNone;

  imgStaticMedia.Align := alClient;
  imgStaticMedia.Center := True;
  imgStaticMedia.Proportional := True;
  imgStaticMedia.Stretch := True;
  imgStaticMedia.Visible := False;

  pnlOSD.Align := alBottom;
  pnlOSD.Height := 40;
  pnlOSD.Color := $00222222;
  pnlOSD.BevelOuter := bvNone;
  pnlOSD.Visible := False;

  // 3. Inicializar Subsistemas do Player
  InitializeSubsystems;
end;

procedure TFrmPlayer.FormDestroy(Sender: TObject);
begin
  // Finalizar Worker de sincronização
  if Assigned(FSyncWorker) then
  begin
    FSyncWorker.Terminate;
    FSyncWorker.WaitFor;
    FreeAndNil(FSyncWorker);
  end;

  // Registrar interrupção da mídia atual se ainda em execução
  if FCurrentMediaID > 0 then
  begin
    FProofOfPlay.LogPlayback(FCurrentMediaID, FCurrentPlaylistID, 
      FCurrentMediaStartedAt, Now, 
      SecondsBetween(Now, FCurrentMediaStartedAt), 'INTERRUPTED');
  end;

  // Finalizar VLC
  if Assigned(FVlcPlayer) then
    FreeAndNil(FVlcPlayer);

  if Assigned(FVlcEngine) then
    FreeAndNil(FVlcEngine);

  // Finalizar demais subsistemas
  FreeAndNil(FScheduler);
  FreeAndNil(FCacheManager);
  FreeAndNil(FProofOfPlay);
  FreeAndNil(FConfig);

  // Restaurar screensaver e cursor ao fechar
  TKioskManager.RestoreScreenSaver;
  TKioskManager.ShowMouseCursor;
end;

procedure TFrmPlayer.InitializeSubsystems;
var
  StorageDir: string;
  ScheduleFile: string;
begin
  // 1. Carregar configurações locais
  FConfig := TPlayerConfig.Create;
  StorageDir := FConfig.CacheDirectory;

  // 2. Gerenciador de Cache e Integridade
  FCacheManager := TCacheManager.Create(StorageDir);

  // 3. Gerenciador de Proof of Play (Offline Buffer)
  FProofOfPlay := TProofOfPlayManager.Create(StorageDir);

  // 4. Scheduler Local
  FScheduler := TSignageScheduler.Create(StorageDir);

  // 5. Motor LibVLC
  FVlcEngine := TLibVlcEngine.Create;
  if FVlcEngine.Initialize(['--avcodec-hw=any', '--quiet', '--no-video-title-show']) then
  begin
    FVlcPlayer := TLibVlcPlayer.Create(FVlcEngine, pnlVideoCanvas);
    FVlcPlayer.OnMediaEnd := @HandleVlcMediaEnd;
    FVlcPlayer.OnMediaError := @HandleVlcMediaError;
    FVlcPlayer.SetVolume(FConfig.Volume);
  end
  else
  begin
    // Se a libvlc não estiver instalada, opera em modo fallback de imagens
    FCurrentStatusText := 'Aviso: libvlc não encontrada. Modo somente imagem.';
  end;

  // 6. Carregar Grade Prévia Salva em Disco (Offline First)
  ScheduleFile := StorageDir + 'current_schedule.json';
  if FileExists(ScheduleFile) then
    FScheduler.LoadFromFile(ScheduleFile);

  // 7. Iniciar Thread de Sincronização em Segundo Plano
  FSyncWorker := TSyncWorkerThread.Create(FConfig.PlayerUUID, FConfig.ServerURL, FCacheManager, FProofOfPlay);
  FSyncWorker.HeartbeatIntervalSec := FConfig.HeartbeatIntervalSec;
  FSyncWorker.SyncIntervalSec := FConfig.SyncIntervalSec;
  FSyncWorker.OnScheduleUpdated := @HandleScheduleUpdated;
  FSyncWorker.OnStatusChange := @HandleSyncStatusChange;
  FSyncWorker.Start;

  pnlOSD.Visible := FConfig.ShowOSD;

  // Iniciar reprodução da grade
  PlayNextScheduleItem;

  tmrPlaybackTick.Interval := 1000;
  tmrPlaybackTick.Enabled := True;

  tmrKioskWatchdog.Interval := 5000;
  tmrKioskWatchdog.Enabled := True;
end;

procedure TFrmPlayer.PlayNextScheduleItem;
var
  Res: TScheduleResolution;
begin
  // Registrar conclusão da mídia anterior
  if FCurrentMediaID > 0 then
  begin
    FProofOfPlay.LogPlayback(FCurrentMediaID, FCurrentPlaylistID, 
      FCurrentMediaStartedAt, Now, 
      SecondsBetween(Now, FCurrentMediaStartedAt), 'COMPLETED');
    FCurrentMediaID := 0;
  end;

  // Resolver o próximo item da grade para o timestamp exato
  Res := FScheduler.MoveToNextItem(Now);

  if not Res.HasValidMedia then
  begin
    // Não há itens válidos configurados
    if Assigned(FVlcPlayer) then FVlcPlayer.Stop;
    imgStaticMedia.Visible := False;
    FCurrentStatusText := 'Aguardando sincronização de playlist...';
    Exit;
  end;

  FCurrentMediaID := Res.MediaItem.MediaID;
  FCurrentPlaylistID := Res.ActivePlaylistID;
  FCurrentMediaStartedAt := Now;
  FCurrentMediaDurationSec := Res.MediaItem.DurationSec;
  FCurrentItemRemainingSec := Res.MediaItem.DurationSec;

  // Notificar telemetria do item em execução
  if Assigned(FSyncWorker) then
    FSyncWorker.SetCurrentPlayingMedia(Res.MediaItem.FileName);

  ExecuteMedia(Res.MediaItem);
end;

procedure TFrmPlayer.ExecuteMedia(const AMedia: TScheduleMediaItem);
var
  FilePath: string;
begin
  FilePath := AMedia.LocalFilePath;

  // 1. Caso a mídia não esteja em disco, tenta carregar pelo nome
  if not FileExists(FilePath) then
    FilePath := FCacheManager.GetCachedFilePath(AMedia.MD5Hash, AMedia.FileName);

  if not FileExists(FilePath) then
  begin
    FCurrentStatusText := 'Mídia ausente em cache: ' + AMedia.FileName;
    // Avança para o próximo item
    FCurrentItemRemainingSec := 1;
    Exit;
  end;

  if AMedia.MediaType = 'VIDEO' then
  begin
    imgStaticMedia.Visible := False;
    pnlVideoCanvas.Visible := True;

    if Assigned(FVlcPlayer) then
    begin
      FIsVideoPlaying := FVlcPlayer.PlayFile(FilePath);
      if not FIsVideoPlaying then
      begin
        FCurrentStatusText := 'Erro ao decodificar vídeo: ' + AMedia.FileName;
        FCurrentItemRemainingSec := 1;
      end;
    end;
  end
  else // IMAGEM ou outros formatos estáticos
  begin
    if Assigned(FVlcPlayer) then
      FVlcPlayer.Stop;
    pnlVideoCanvas.Visible := False;
    ShowStaticImage(FilePath);
  end;
end;

procedure TFrmPlayer.ShowStaticImage(const AFilePath: string);
begin
  try
    imgStaticMedia.Picture.LoadFromFile(AFilePath);
    imgStaticMedia.Visible := True;
  except
    on E: Exception do
    begin
      imgStaticMedia.Visible := False;
      FCurrentStatusText := 'Erro ao carregar imagem: ' + E.Message;
    end;
  end;
end;

procedure TFrmPlayer.HandleVlcMediaEnd(Sender: TObject);
begin
  // libvlc notificou fim do vídeo: avançar imediatamente
  PlayNextScheduleItem;
end;

procedure TFrmPlayer.HandleVlcMediaError(Sender: TObject; const AErrorMsg: string);
begin
  FCurrentStatusText := 'VLC Error: ' + AErrorMsg;
  // Fallback rápido para o próximo item
  PlayNextScheduleItem;
end;

procedure TFrmPlayer.HandleScheduleUpdated(Sender: TObject; const ANewScheduleJson: string);
var
  ScheduleFile: string;
  SL: TStringList;
begin
  // Salvar nova grade em disco para persistência offline
  ScheduleFile := FConfig.CacheDirectory + 'current_schedule.json';
  SL := TStringList.Create;
  try
    SL.Text := ANewScheduleJson;
    SL.SaveToFile(ScheduleFile);
  finally
    SL.Free;
  end;

  // Recarregar no scheduler
  FScheduler.LoadFromJsonString(ANewScheduleJson);
  FCurrentStatusText := 'Grade de reprodução atualizada com sucesso!';
end;

procedure TFrmPlayer.HandleSyncStatusChange(Sender: TObject; const AStatus: string);
begin
  FCurrentStatusText := AStatus;
end;

procedure TFrmPlayer.tmrPlaybackTickTimer(Sender: TObject);
begin
  // Decrementar tempo restante do item atual
  if FCurrentItemRemainingSec > 0 then
    Dec(FCurrentItemRemainingSec);

  // Se o tempo da mídia estática ou vídeo expirou, avança
  if (FCurrentItemRemainingSec <= 0) and not FIsVideoPlaying then
  begin
    PlayNextScheduleItem;
  end;

  UpdateOSDDisplay;
end;

procedure TFrmPlayer.tmrKioskWatchdogTimer(Sender: TObject);
begin
  // 1. Manter tela acordada e suprimir descanso de tela do SO
  TKioskManager.KeepDisplayAwake;

  // 2. Garantir que a janela esteja sempre no topo em tela cheia
  if WindowState <> wsMaximized then
    WindowState := wsMaximized;
  if FormStyle <> fsStayOnTop then
    FormStyle := fsStayOnTop;
end;

procedure TFrmPlayer.UpdateOSDDisplay;
begin
  if not pnlOSD.Visible then Exit;

  lblOSDClock.Caption := FormatDateTime('dd/mm/yyyy hh:nn:ss', Now);
  lblOSDTitle.Caption := Format('Player: %s | Grade: %s', 
    [FConfig.PlayerName, FScheduler.CurrentResolution.PlaylistName]);
  lblOSDStatus.Caption := FCurrentStatusText;
end;

procedure TFrmPlayer.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // F1: Alternar exibição do OSD de depuração
  if Key = VK_F1 then
  begin
    pnlOSD.Visible := not pnlOSD.Visible;
    Key := 0;
  end
  // F5: Forçar sincronização imediata
  else if Key = VK_F5 then
  begin
    FCurrentStatusText := 'Sincronização manual solicitada...';
    Key := 0;
  end
  // ESC ou Ctrl+Q: Solicitar senha de administrador para sair do Kiosk
  else if (Key = VK_ESCAPE) or ((Key = Ord('Q')) and (ssCtrl in Shift)) then
  begin
    PromptAdminExit;
    Key := 0;
  end;
end;

procedure TFrmPlayer.PromptAdminExit;
var
  InputPass: string;
begin
  TKioskManager.ShowMouseCursor;
  InputPass := '';
  if InputQuery('Digital Signage Kiosk', 'Digite a senha de administrador para encerrar:', InputPass) then
  begin
    if InputPass = FConfig.AdminPassword then
    begin
      Close;
    end
    else
    begin
      ShowMessage('Senha incorreta!');
      TKioskManager.HideMouseCursor;
    end;
  end
  else
    TKioskManager.HideMouseCursor;
end;

end.
