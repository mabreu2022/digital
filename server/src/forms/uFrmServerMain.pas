unit uFrmServerMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, ExtCtrls,
  StdCtrls, Grids, Buttons, IniFiles, md5, FileUtil, LazFileUtils, LCLIntf,
  fphttpserver, httpdefs, sqldb, IBConnection,
  uDbConnection, uSignageQueries, uPlayerApiController, uLibVlcWrapper, uMediaDurationDetector;

type
  { Thread do Servidor HTTP }
  TServerHttpThread = class(TThread)
  private
    FServer: TFPHttpServer;
    FPort: Word;
    FApiController: TPlayerApiController;
    FErrorMsg: string;
    procedure HandleRequest(Sender: TObject; var ARequest: TFPHTTPConnectionRequest; var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Word; AApiController: TPlayerApiController);
    destructor Destroy; override;
    procedure StopServer;
    property ErrorMsg: string read FErrorMsg;
  end;

  { TFrmServerMain }
  TFrmServerMain = class(TForm)
    PageControlMain: TPageControl;
    TabServidor: TTabSheet;
    TabTelas: TTabSheet;
    TabMidias: TTabSheet;
    TabPlaylists: TTabSheet;
    TabAgendamentos: TTabSheet;

    // Aba 1: Servidor & Monitor
    PanelTopStatus: TPanel;
    ShapeStatus: TShape;
    LblServerStatus: TLabel;
    BtnStartServer: TBitBtn;
    BtnStopServer: TBitBtn;
    GroupBoxConfig: TGroupBox;
    LblHttpPort: TLabel;
    EditHttpPort: TEdit;
    LblDbHost: TLabel;
    EditDbHost: TEdit;
    LblDbPath: TLabel;
    EditDbPath: TEdit;
    LblDbUser: TLabel;
    EditDbUser: TEdit;
    LblDbPass: TLabel;
    EditDbPass: TEdit;
    BtnSaveConfig: TBitBtn;
    BtnTestDb: TBitBtn;
    GroupBoxLogs: TGroupBox;
    MemoLogs: TMemo;
    PanelLogActions: TPanel;
    BtnClearLogs: TBitBtn;

    // Aba 2: Telas
    PanelTelasTop: TPanel;
    BtnRefreshTelas: TBitBtn;
    BtnDeleteTela: TBitBtn;
    BtnOpenWebPlayer: TBitBtn;
    GridTelas: TStringGrid;

    // Aba 3: Mídias & Preview
    PanelMidiasTop: TPanel;
    BtnAddMedia: TBitBtn;
    BtnAddYouTube: TBitBtn;
    BtnDeleteMedia: TBitBtn;
    BtnRefreshMidias: TBitBtn;
    BtnOpenMediaFolder: TBitBtn;
    PanelMidiasLeft: TPanel;
    GridMidias: TStringGrid;
    SplitterMidias: TSplitter;
    PanelMidiasRight: TPanel;
    GroupBoxPreview: TGroupBox;
    PanelPreviewImage: TPanel;
    PanelVideoCanvas: TPanel;
    ImagePreview: TImage;
    PanelPreviewMeta: TPanel;
    LblPreviewTitle: TLabel;
    LblPreviewFileName: TLabel;
    LblPreviewType: TLabel;
    LblPreviewResolution: TLabel;
    LblPreviewMD5: TLabel;
    PanelMediaControls: TPanel;
    BtnPlayMedia: TBitBtn;
    BtnStopMedia: TBitBtn;
    BtnOpenExternal: TBitBtn;
    OpenDialogMedia: TOpenDialog;

    // Aba 4: Playlists
    PanelPlaylistsLeft: TPanel;
    PanelPlaylistsRight: TPanel;
    SplitterPlaylists: TSplitter;
    PanelPlaylistsLeftTop: TPanel;
    BtnNewPlaylist: TBitBtn;
    BtnSetDefaultPlaylist: TBitBtn;
    BtnDeletePlaylist: TBitBtn;
    BtnRefreshPlaylists: TBitBtn;
    GridPlaylists: TStringGrid;
    PanelPlaylistsRightTop: TPanel;
    BtnAddPlaylistItem: TBitBtn;
    BtnMoveItemUp: TBitBtn;
    BtnMoveItemDown: TBitBtn;
    BtnDeletePlaylistItem: TBitBtn;
    GridPlaylistItens: TStringGrid;

    // Aba 5: Agendamentos
    PanelAgendamentosTop: TPanel;
    BtnNewAgendamento: TBitBtn;
    BtnDeleteAgendamento: TBitBtn;
    BtnRefreshAgendamentos: TBitBtn;
    GridAgendamentos: TStringGrid;

    TimerAutoRefresh: TTimer;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure PageControlMainChange(Sender: TObject);
    procedure BtnStartServerClick(Sender: TObject);
    procedure BtnStopServerClick(Sender: TObject);
    procedure BtnSaveConfigClick(Sender: TObject);
    procedure BtnTestDbClick(Sender: TObject);
    procedure BtnClearLogsClick(Sender: TObject);

    // Telas
    procedure BtnRefreshTelasClick(Sender: TObject);
    procedure BtnDeleteTelaClick(Sender: TObject);
    procedure BtnOpenWebPlayerClick(Sender: TObject);

    // Mídias
    procedure BtnAddMediaClick(Sender: TObject);
    procedure BtnAddYouTubeClick(Sender: TObject);
    procedure BtnDeleteMediaClick(Sender: TObject);
    procedure BtnRefreshMidiasClick(Sender: TObject);
    procedure BtnOpenMediaFolderClick(Sender: TObject);
    procedure GridMidiasSelection(Sender: TObject; aCol, aRow: Integer);
    procedure BtnPlayMediaClick(Sender: TObject);
    procedure BtnStopMediaClick(Sender: TObject);
    procedure BtnOpenExternalClick(Sender: TObject);

    // Playlists
    procedure GridPlaylistsSelection(Sender: TObject; aCol, aRow: Integer);
    procedure BtnNewPlaylistClick(Sender: TObject);
    procedure BtnSetDefaultPlaylistClick(Sender: TObject);
    procedure BtnDeletePlaylistClick(Sender: TObject);
    procedure BtnRefreshPlaylistsClick(Sender: TObject);
    procedure BtnAddPlaylistItemClick(Sender: TObject);
    procedure BtnMoveItemUpClick(Sender: TObject);
    procedure BtnMoveItemDownClick(Sender: TObject);
    procedure BtnDeletePlaylistItemClick(Sender: TObject);

    // Agendamentos
    procedure BtnNewAgendamentoClick(Sender: TObject);
    procedure BtnDeleteAgendamentoClick(Sender: TObject);
    procedure BtnRefreshAgendamentosClick(Sender: TObject);

    procedure TimerAutoRefreshTimer(Sender: TObject);
  private
    FDbManager: TFirebirdConnectionManager;
    FApiController: TPlayerApiController;
    FServerThread: TServerHttpThread;
    FConfigFile: string;

    FVlcEngine: TLibVlcEngine;
    FVlcPlayer: TLibVlcPlayer;
    FIsVlcInitialized: Boolean;
    FIsVideoPlaying: Boolean;
    FIsVideoPaused: Boolean;
    FCurrentPlayingFile: string;

    procedure LoadConfig;
    procedure SaveConfig;
    procedure SynchronizeDatabaseSequences(AConn: TIBConnection; ATrans: TSQLTransaction);
    procedure UpdateServerUiState(const ARunning: Boolean);
    procedure SyncLogMessage(Data: PtrInt);
    procedure OnApiLog(const ALogMsg: string);
    procedure LogMessage(const AMsg: string);
    procedure OnVideoMediaEnd(Sender: TObject);
    procedure StopEmbeddedVideo;
    function FindMediaFilePath(const AFileName: string): string;
    function GetSelectedPlaylistId: Int64;
    function CopyMediaAndGetInfo(const ASourceFile: string; out AFileName, AMd5: string; out ASizeBytes: Int64; out AMimeType, ATipoMidia: string): Boolean;
  public
  end;

var
  FrmServerMain: TFrmServerMain;

implementation

{$R *.lfm}

{ TServerHttpThread }

constructor TServerHttpThread.Create(APort: Word; AApiController: TPlayerApiController);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPort := APort;
  FApiController := AApiController;
  FServer := TFPHttpServer.Create(nil);
  FServer.Port := FPort;
  FServer.Threaded := False;
  FServer.OnRequest := @HandleRequest;
end;

destructor TServerHttpThread.Destroy;
begin
  StopServer;
  FreeAndNil(FServer);
  inherited Destroy;
end;

procedure TServerHttpThread.HandleRequest(Sender: TObject; var ARequest: TFPHTTPConnectionRequest; var AResponse: TFPHTTPConnectionResponse);
begin
  if Assigned(FApiController) then
    FApiController.RouteRequest(ARequest, AResponse);
end;

procedure TServerHttpThread.Execute;
begin
  try
    FServer.Active := True;
  except
    on E: Exception do
      FErrorMsg := E.Message;
  end;
end;

procedure TServerHttpThread.StopServer;
begin
  if Assigned(FServer) and FServer.Active then
  begin
    try
      FServer.Active := False;
    except
    end;
  end;
  Terminate;
end;

{ TFrmServerMain }

procedure TFrmServerMain.FormCreate(Sender: TObject);
var
  AppDir: string;
begin
  AppDir := ExtractFilePath(ParamStr(0));
  FConfigFile := AppDir + 'config' + PathDelim + 'database.ini';
  if not FileExists(FConfigFile) then
    FConfigFile := AppDir + '..' + PathDelim + 'config' + PathDelim + 'database.ini';

  FDbManager := TFirebirdConnectionManager.Create;
  FApiController := TPlayerApiController.Create(FDbManager);
  FApiController.OnLog := @OnApiLog;

  // Configuração das Grids
  GridTelas.Cells[0, 0] := 'ID';
  GridTelas.Cells[1, 0] := 'Nome da Tela';
  GridTelas.Cells[2, 0] := 'IP Local';
  GridTelas.Cells[3, 0] := 'Status';
  GridTelas.Cells[4, 0] := 'Versão';
  GridTelas.Cells[5, 0] := 'Último Heartbeat';
  GridTelas.Cells[6, 0] := 'UUID';

  GridMidias.Cells[0, 0] := 'ID';
  GridMidias.Cells[1, 0] := 'Nome de Exibição';
  GridMidias.Cells[2, 0] := 'Arquivo';
  GridMidias.Cells[3, 0] := 'Tipo';
  GridMidias.Cells[4, 0] := 'Duração (s)';
  GridMidias.Cells[5, 0] := 'Tamanho (MB)';
  GridMidias.Cells[6, 0] := 'Hash MD5';

  GridPlaylists.Cells[0, 0] := 'ID';
  GridPlaylists.Cells[1, 0] := 'Nome da Playlist';
  GridPlaylists.Cells[2, 0] := 'Padrão';
  GridPlaylists.Cells[3, 0] := 'Ativa';

  GridPlaylistItens.Cells[0, 0] := 'Ordem';
  GridPlaylistItens.Cells[1, 0] := 'Mídia';
  GridPlaylistItens.Cells[2, 0] := 'Tipo';
  GridPlaylistItens.Cells[3, 0] := 'Duração (s)';
  GridPlaylistItens.Cells[4, 0] := 'Transição';
  GridPlaylistItens.Cells[5, 0] := 'Item ID';

  GridAgendamentos.Cells[0, 0] := 'ID';
  GridAgendamentos.Cells[1, 0] := 'Evento / Campanha';
  GridAgendamentos.Cells[2, 0] := 'Playlist';
  GridAgendamentos.Cells[3, 0] := 'Destino (Tela / IP)';
  GridAgendamentos.Cells[4, 0] := 'Período';
  GridAgendamentos.Cells[5, 0] := 'Horário';
  GridAgendamentos.Cells[6, 0] := 'Dias';
  GridAgendamentos.Cells[7, 0] := 'Prioridade';
  GridAgendamentos.Cells[8, 0] := 'Ativo';

  // Inicialização da Engine de Vídeo LibVLC
  FVlcEngine := TLibVlcEngine.Create;
  FIsVlcInitialized := FVlcEngine.Initialize(['--avcodec-hw=any', '--quiet', '--no-video-title-show']);
  if FIsVlcInitialized then
  begin
    FVlcPlayer := TLibVlcPlayer.Create(FVlcEngine, PanelVideoCanvas);
    FVlcPlayer.OnMediaEnd := @OnVideoMediaEnd;
    LogMessage('Engine de vídeo LibVLC inicializada (' + FVlcEngine.Version + ').');
  end
  else
    LogMessage('Aviso: LibVLC não detectada no sistema. Preview embutido utilizará fallback externo.');

  LoadConfig;
  UpdateServerUiState(False);

  // Sincronizar geradores/sequences de chaves primárias do banco Firebird
  try
    SynchronizeDatabaseSequences(nil, nil);
  except
  end;

  // Iniciar servidor automaticamente
  BtnStartServerClick(Self);

  // Carregar dados iniciais
  BtnRefreshTelasClick(Self);
  BtnRefreshMidiasClick(Self);
  BtnRefreshPlaylistsClick(Self);
  BtnRefreshAgendamentosClick(Self);
  TimerAutoRefresh.Enabled := True;
end;

procedure TFrmServerMain.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  StopEmbeddedVideo;
end;

procedure TFrmServerMain.FormDestroy(Sender: TObject);
begin
  TimerAutoRefresh.Enabled := False;
  StopEmbeddedVideo;
  FreeAndNil(FVlcPlayer);
  FreeAndNil(FVlcEngine);
  BtnStopServerClick(Self);
  FreeAndNil(FApiController);
  FreeAndNil(FDbManager);
end;

procedure TFrmServerMain.LoadConfig;
var
  Ini: TIniFile;
begin
  if FileExists(FConfigFile) then
  begin
    Ini := TIniFile.Create(FConfigFile);
    try
      EditDbHost.Text := Ini.ReadString('Database', 'Host', '127.0.0.1');
      EditDbPath.Text := Ini.ReadString('Database', 'Database', '/opt/firebird/dados/digitalsign.fdb');
      EditDbUser.Text := Ini.ReadString('Database', 'User', 'SYSDBA');
      EditDbPass.Text := Ini.ReadString('Database', 'Password', 'masterkey');
      EditHttpPort.Text := Ini.ReadString('Server', 'HttpPort', '8080');
    finally
      Ini.Free;
    end;
  end
  else
  begin
    EditDbHost.Text := '127.0.0.1';
    EditDbPath.Text := '/opt/firebird/dados/digitalsign.fdb';
    EditDbUser.Text := 'SYSDBA';
    EditDbPass.Text := 'masterkey';
    EditHttpPort.Text := '8080';
  end;
end;

procedure TFrmServerMain.SaveConfig;
var
  Ini: TIniFile;
  Dir: string;
begin
  Dir := ExtractFilePath(FConfigFile);
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  Ini := TIniFile.Create(FConfigFile);
  try
    Ini.WriteString('Database', 'Host', EditDbHost.Text);
    Ini.WriteString('Database', 'Database', EditDbPath.Text);
    Ini.WriteString('Database', 'User', EditDbUser.Text);
    Ini.WriteString('Database', 'Password', EditDbPass.Text);
    Ini.WriteString('Server', 'HttpPort', EditHttpPort.Text);
  finally
    Ini.Free;
  end;
  LogMessage('Configurações salvas em ' + FConfigFile);
end;

procedure TFrmServerMain.SynchronizeDatabaseSequences(AConn: TIBConnection; ATrans: TSQLTransaction);
const
  Tables: array[0..4] of string = ('MIDIAS', 'TELAS', 'PLAYLISTS', 'PLAYLIST_ITENS', 'AGENDAMENTOS');
var
  LocalConn: TIBConnection;
  LocalTrans: TSQLTransaction;
  OwnConn: Boolean;
  Qry: TSQLQuery;
  i: Integer;
  MaxId: Int64;
  Tbl: string;
begin
  OwnConn := (AConn = nil) or (ATrans = nil);
  if OwnConn then
  begin
    if FDbManager = nil then Exit;
    LocalConn := FDbManager.CreateConnection(LocalTrans);
  end
  else
  begin
    LocalConn := AConn;
    LocalTrans := ATrans;
  end;

  Qry := TSQLQuery.Create(nil);
  try
    if OwnConn then
      LocalConn.Connected := True;

    Qry.Database := LocalConn;
    Qry.Transaction := LocalTrans;

    for i := 0 to High(Tables) do
    begin
      Tbl := Tables[i];
      try
        Qry.SQL.Text := 'SELECT COALESCE(MAX(ID), 0) AS MAX_ID FROM ' + Tbl;
        Qry.Open;
        MaxId := Qry.FieldByName('MAX_ID').AsLargeInt;
        Qry.Close;

        if MaxId > 0 then
        begin
          try
            Qry.SQL.Text := 'ALTER TABLE ' + Tbl + ' ALTER ID RESTART WITH ' + IntToStr(MaxId + 1);
            Qry.ExecSQL;
            LocalTrans.CommitRetaining;
          except
          end;
        end;
      except
      end;
    end;
  finally
    Qry.Free;
    if OwnConn then
    begin
      LocalTrans.Free;
      LocalConn.Free;
    end;
  end;
end;

procedure TFrmServerMain.UpdateServerUiState(const ARunning: Boolean);
begin
  if ARunning then
  begin
    ShapeStatus.Brush.Color := clLime;
    LblServerStatus.Caption := 'SERVIDOR ONLINE NA PORTA ' + EditHttpPort.Text;
    BtnStartServer.Enabled := False;
    BtnStopServer.Enabled := True;
    EditHttpPort.Enabled := False;
  end
  else
  begin
    ShapeStatus.Brush.Color := clRed;
    LblServerStatus.Caption := 'SERVIDOR PARADO';
    BtnStartServer.Enabled := True;
    BtnStopServer.Enabled := False;
    EditHttpPort.Enabled := True;
  end;
end;

procedure TFrmServerMain.SyncLogMessage(Data: PtrInt);
var
  MsgStr: string;
begin
  if Data <> 0 then
  begin
    MsgStr := PString(Pointer(Data))^;
    Dispose(PString(Pointer(Data)));
    LogMessage(MsgStr);
  end;
end;

procedure TFrmServerMain.OnApiLog(const ALogMsg: string);
var
  P: PString;
begin
  New(P);
  P^ := ALogMsg;
  Application.QueueAsyncCall(@SyncLogMessage, PtrInt(Pointer(P)));
end;

procedure TFrmServerMain.LogMessage(const AMsg: string);
begin
  MemoLogs.Lines.Add(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' - ' + AMsg);
  while MemoLogs.Lines.Count > 1000 do
    MemoLogs.Lines.Delete(0);
end;

procedure TFrmServerMain.BtnStartServerClick(Sender: TObject);
var
  PortVal: Integer;
begin
  if Assigned(FServerThread) then Exit;

  PortVal := StrToIntDef(EditHttpPort.Text, 8080);
  LogMessage('Iniciando servidor HTTP REST na porta ' + IntToStr(PortVal) + '...');

  try
    FServerThread := TServerHttpThread.Create(PortVal, FApiController);
    FServerThread.Start;
    UpdateServerUiState(True);
    LogMessage('Servidor ativo e pronto para receber conexões dos Players!');
  except
    on E: Exception do
    begin
      LogMessage('FALHA AO INICIAR SERVIDOR: ' + E.Message);
      UpdateServerUiState(False);
    end;
  end;
end;

procedure TFrmServerMain.BtnStopServerClick(Sender: TObject);
begin
  if Assigned(FServerThread) then
  begin
    LogMessage('Encerrando servidor HTTP...');
    FServerThread.StopServer;
    FServerThread.WaitFor;
    FreeAndNil(FServerThread);
    UpdateServerUiState(False);
    LogMessage('Servidor parado.');
  end;
end;

procedure TFrmServerMain.BtnSaveConfigClick(Sender: TObject);
begin
  SaveConfig;
  ShowMessage('Configurações salvas com sucesso!');
end;

procedure TFrmServerMain.BtnTestDbClick(Sender: TObject);
var
  Msg: string;
begin
  SaveConfig;
  if FDbManager.TestConnection(Msg) then
    ShowMessage('[SUCESSO] Conectado com sucesso ao Firebird!' + LineEnding + Msg)
  else
    ShowMessage('[ERRO] Falha ao conectar ao Firebird:' + LineEnding + Msg);
end;

procedure TFrmServerMain.BtnClearLogsClick(Sender: TObject);
begin
  MemoLogs.Clear;
end;

{ Telas }

procedure TFrmServerMain.BtnRefreshTelasClick(Sender: TObject);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
  Row: Integer;
begin
  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'SELECT ID, NOME, IP_LOCAL, IP_PUBLICO, STATUS, VERSAO_PLAYER, ULTIMO_HEARTBEAT, UUID ' +
                    'FROM TELAS ORDER BY NOME';
    Qry.Open;

    GridTelas.RowCount := 1;
    Row := 1;
    while not Qry.EOF do
    begin
      GridTelas.RowCount := Row + 1;
      GridTelas.Cells[0, Row] := Qry.FieldByName('ID').AsString;
      GridTelas.Cells[1, Row] := Qry.FieldByName('NOME').AsString;
      GridTelas.Cells[2, Row] := Qry.FieldByName('IP_LOCAL').AsString;
      GridTelas.Cells[3, Row] := Qry.FieldByName('STATUS').AsString;
      GridTelas.Cells[4, Row] := Qry.FieldByName('VERSAO_PLAYER').AsString;
      if not Qry.FieldByName('ULTIMO_HEARTBEAT').IsNull then
        GridTelas.Cells[5, Row] := FormatDateTime('yyyy-mm-dd hh:nn:ss', Qry.FieldByName('ULTIMO_HEARTBEAT').AsDateTime)
      else
        GridTelas.Cells[5, Row] := '-';
      GridTelas.Cells[6, Row] := Qry.FieldByName('UUID').AsString;
      Inc(Row);
      Qry.Next;
    end;
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnDeleteTelaClick(Sender: TObject);
var
  TelaID, TelaNome: string;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  if (GridTelas.Row < 1) or (GridTelas.Cells[0, GridTelas.Row] = '') then
  begin
    ShowMessage('Selecione uma tela para excluir.');
    Exit;
  end;

  TelaID := GridTelas.Cells[0, GridTelas.Row];
  TelaNome := GridTelas.Cells[1, GridTelas.Row];

  if MessageDlg('Confirmação', 'Deseja realmente remover a tela "' + TelaNome + '"?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'DELETE FROM LOGS_EXIBICAO WHERE TELA_ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := StrToInt64(TelaID);
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM AGENDAMENTOS WHERE TELA_ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := StrToInt64(TelaID);
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM TELAS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := StrToInt64(TelaID);
    Qry.ExecSQL;
    Trans.Commit;

    BtnRefreshTelasClick(Self);
    LogMessage('Tela "' + TelaNome + '" removida com sucesso.');
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnOpenWebPlayerClick(Sender: TObject);
var
  Url: string;
begin
  Url := 'http://localhost:' + Trim(EditHttpPort.Text) + '/player';
  OpenURL(Url);
  LogMessage('Web Signage Player aberto no navegador: ' + Url);
end;

{ Mídias }

function TFrmServerMain.CopyMediaAndGetInfo(const ASourceFile: string; out AFileName, AMd5: string; out ASizeBytes: Int64; out AMimeType, ATipoMidia: string): Boolean;
var
  MediaDir, DestFile, Ext: string;
begin
  Result := False;
  if not FileExists(ASourceFile) then Exit;

  AFileName := ExtractFileName(ASourceFile);
  MediaDir := ExtractFilePath(ParamStr(0)) + 'media' + PathDelim;
  if not DirectoryExists(MediaDir) then
    ForceDirectories(MediaDir);

  DestFile := MediaDir + AFileName;
  if not CopyFile(ASourceFile, DestFile, [cffOverwriteFile]) then
  begin
    ShowMessage('Erro ao copiar arquivo para ' + DestFile);
    Exit;
  end;

  // Copia também para ../media se existir para dev
  if DirectoryExists(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'media') then
    CopyFile(ASourceFile, ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'media' + PathDelim + AFileName, [cffOverwriteFile]);

  AMd5 := LowerCase(MD5Print(MD5File(DestFile)));
  with TFileStream.Create(DestFile, fmOpenRead or fmShareDenyNone) do
  try
    ASizeBytes := Size;
  finally
    Free;
  end;

  Ext := LowerCase(ExtractFileExt(DestFile));
  if (Ext = '.mp4') or (Ext = '.mkv') or (Ext = '.avi') or (Ext = '.mov') then
  begin
    ATipoMidia := 'VIDEO';
    AMimeType := 'video/mp4';
  end
  else if (Ext = '.jpg') or (Ext = '.jpeg') then
  begin
    ATipoMidia := 'IMAGE';
    AMimeType := 'image/jpeg';
  end
  else if (Ext = '.png') then
  begin
    ATipoMidia := 'IMAGE';
    AMimeType := 'image/png';
  end
  else if (Ext = '.webp') then
  begin
    ATipoMidia := 'IMAGE';
    AMimeType := 'image/webp';
  end
  else
  begin
    ATipoMidia := 'IMAGE';
    AMimeType := 'application/octet-stream';
  end;

  Result := True;
end;

function ExtractYouTubeVideoId(const AUrl: string): string;
var
  S: string;
  P, PEnd: Integer;
begin
  Result := '';
  S := Trim(AUrl);
  if S = '' then Exit;

  // 1. Caso youtu.be/ID
  if Pos('youtu.be/', S) > 0 then
  begin
    P := Pos('youtu.be/', S) + 9;
    Result := Copy(S, P, Length(S));
    PEnd := Pos('?', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    PEnd := Pos('/', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    Exit;
  end;

  // 2. Caso /shorts/ID ou /embed/ID ou /live/ID
  if Pos('/shorts/', S) > 0 then
  begin
    P := Pos('/shorts/', S) + 8;
    Result := Copy(S, P, Length(S));
    PEnd := Pos('?', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    PEnd := Pos('/', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    Exit;
  end;

  if Pos('/live/', S) > 0 then
  begin
    P := Pos('/live/', S) + 6;
    Result := Copy(S, P, Length(S));
    PEnd := Pos('?', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    PEnd := Pos('/', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    Exit;
  end;

  if Pos('/embed/', S) > 0 then
  begin
    P := Pos('/embed/', S) + 7;
    Result := Copy(S, P, Length(S));
    PEnd := Pos('?', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    PEnd := Pos('/', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    Exit;
  end;

  // 3. Caso padrão watch?v=ID ou v=ID
  if Pos('v=', S) > 0 then
  begin
    P := Pos('v=', S) + 2;
    Result := Copy(S, P, Length(S));
    PEnd := Pos('&', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    PEnd := Pos('#', Result);
    if PEnd > 0 then Result := Copy(Result, 1, PEnd - 1);
    Exit;
  end;

  // Se o usuário digitou apenas o ID
  if (Length(S) = 11) and (Pos('/', S) = 0) and (Pos('?', S) = 0) then
    Result := S;
end;

procedure TFrmServerMain.BtnAddYouTubeClick(Sender: TObject);
var
  UrlStr, NomeStr, VideoId, HashVal: string;
  DuracaoSec: Integer;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  UrlStr := InputBox('Adicionar Vídeo do YouTube / Link',
    'Cole a URL do vídeo do YouTube (ex: https://www.youtube.com/watch?v=... ou https://youtu.be/...):', '');
  UrlStr := Trim(UrlStr);
  if UrlStr = '' then Exit;

  VideoId := ExtractYouTubeVideoId(UrlStr);
  if VideoId = '' then
  begin
    ShowMessage('Não foi possível identificar o ID do vídeo do YouTube. Verifique o link informado.');
    Exit;
  end;

  NomeStr := InputBox('Nome de Exibição', 'Informe o nome para identificação no sistema:', 'YouTube - ' + VideoId);
  NomeStr := Trim(NomeStr);
  if NomeStr = '' then NomeStr := 'YouTube - ' + VideoId;

  // Vídeos do YouTube tocam 100% até o fim nativo
  DuracaoSec := 0;

  // Gerar MD5 a partir do ID do YouTube para unicidade
  HashVal := MD5Print(MD5String('youtube:' + VideoId));

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;

    // Sincronizar sequence de chave primária antes de inserir
    SynchronizeDatabaseSequences(Conn, Trans);

    Qry.SQL.Text := 'SELECT ID FROM MIDIAS WHERE HASH_MD5 = :MD5';
    Qry.ParamByName('MD5').AsString := HashVal;
    Qry.Open;

    if not Qry.EOF then
    begin
      // Já existe: atualiza
      Qry.Close;
      Qry.SQL.Text := 'UPDATE MIDIAS SET NOME_EXIBICAO = :NOME, DURACAO_PADRAO_SEG = :DUR, URL_DOWNLOAD = :URL WHERE HASH_MD5 = :MD5';
      Qry.ParamByName('NOME').AsString := NomeStr;
      Qry.ParamByName('DUR').AsInteger := DuracaoSec;
      Qry.ParamByName('URL').AsString := 'https://www.youtube.com/watch?v=' + VideoId;
      Qry.ParamByName('MD5').AsString := HashVal;
      Qry.ExecSQL;
    end
    else
    begin
      // Novo registro
      Qry.Close;
      Qry.SQL.Text :=
        'INSERT INTO MIDIAS (NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, TIPO_MIDIA, ' +
        '  MIME_TYPE, DURACAO_PADRAO_SEG, URL_DOWNLOAD, STATUS) ' +
        'VALUES (:NOME, :ARQ, :MD5, 0, ''STREAM'', ''video/youtube'', :DUR, :URL, ''READY'')';
      Qry.ParamByName('NOME').AsString := NomeStr;
      Qry.ParamByName('ARQ').AsString := 'youtube_' + VideoId;
      Qry.ParamByName('MD5').AsString := HashVal;
      Qry.ParamByName('DUR').AsInteger := DuracaoSec;
      Qry.ParamByName('URL').AsString := 'https://www.youtube.com/watch?v=' + VideoId;
      Qry.ExecSQL;
    end;

    Trans.Commit;

    LogMessage('Mídia YouTube "' + NomeStr + '" gravada com sucesso (Reprodução integral até o fim)!');
    BtnRefreshMidiasClick(Self);
    ShowMessage('Vídeo do YouTube cadastrado com sucesso no catálogo de mídias!');
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnAddMediaClick(Sender: TObject);
var
  SourceFile, FileName, MD5Str, MimeType, TipoMidia, DisplayName: string;
  SizeBytes: Int64;
  DuracaoSec: Integer;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  if not OpenDialogMedia.Execute then Exit;

  SourceFile := OpenDialogMedia.FileName;
  if not CopyMediaAndGetInfo(SourceFile, FileName, MD5Str, SizeBytes, MimeType, TipoMidia) then Exit;

  DisplayName := InputBox('Adicionar Mídia', 'Nome de Exibição da Mídia:', ChangeFileExt(FileName, ''));
  if DisplayName = '' then DisplayName := FileName;

  if TipoMidia = 'VIDEO' then
  begin
    // Detecta duração real do vídeo automaticamente sem intervenção do usuário
    DuracaoSec := DetectVideoDurationSeconds(SourceFile);
    LogMessage(Format('Vídeo "%s": Duração detectada automaticamente = %d segundos', [DisplayName, DuracaoSec]));
  end
  else
    DuracaoSec := 10; // Duração padrão de exibição de imagens em segundos

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;

    // Sincronizar sequence de chave primária antes de inserir
    SynchronizeDatabaseSequences(Conn, Trans);

    Qry.SQL.Text := 'SELECT ID FROM MIDIAS WHERE HASH_MD5 = :MD5';
    Qry.ParamByName('MD5').AsString := MD5Str;
    Qry.Open;

    if not Qry.EOF then
    begin
      // Já existe: atualiza
      Qry.Close;
      Qry.SQL.Text := 'UPDATE MIDIAS SET NOME_EXIBICAO = :NOME, DURACAO_PADRAO_SEG = :DUR WHERE HASH_MD5 = :MD5';
      Qry.ParamByName('NOME').AsString := DisplayName;
      Qry.ParamByName('DUR').AsInteger := DuracaoSec;
      Qry.ParamByName('MD5').AsString := MD5Str;
      Qry.ExecSQL;
    end
    else
    begin
      // Novo registro
      Qry.Close;
      Qry.SQL.Text := 'INSERT INTO MIDIAS (NOME_EXIBICAO, NOME_ARQUIVO, HASH_MD5, TAMANHO_BYTES, TIPO_MIDIA, MIME_TYPE, DURACAO_PADRAO_SEG, URL_DOWNLOAD) ' +
                      'VALUES (:NOME, :ARQ, :MD5, :TAM, :TIPO, :MIME, :DUR, :URL)';
      Qry.ParamByName('NOME').AsString := DisplayName;
      Qry.ParamByName('ARQ').AsString := FileName;
      Qry.ParamByName('MD5').AsString := MD5Str;
      Qry.ParamByName('TAM').AsLargeInt := SizeBytes;
      Qry.ParamByName('TIPO').AsString := TipoMidia;
      Qry.ParamByName('MIME').AsString := MimeType;
      Qry.ParamByName('DUR').AsInteger := DuracaoSec;
      Qry.ParamByName('URL').AsString := '/media/' + FileName;
      Qry.ExecSQL;
    end;

    Trans.Commit;

    BtnRefreshMidiasClick(Self);
    LogMessage(Format('Mídia "%s" (%s, %ds) adicionada com sucesso ao catálogo!', [DisplayName, TipoMidia, DuracaoSec]));
    ShowMessage('Mídia adicionada com sucesso ao catálogo!');
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnDeleteMediaClick(Sender: TObject);
var
  MediaID, MediaNome: string;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  if (GridMidias.Row < 1) or (GridMidias.Cells[0, GridMidias.Row] = '') then
  begin
    ShowMessage('Selecione uma mídia para excluir.');
    Exit;
  end;

  MediaID := GridMidias.Cells[0, GridMidias.Row];
  MediaNome := GridMidias.Cells[1, GridMidias.Row];

  if MessageDlg('Confirmação', 'Deseja realmente remover a mídia "' + MediaNome + '" do catálogo?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'DELETE FROM PLAYLIST_ITENS WHERE MIDIA_ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := StrToInt64(MediaID);
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM MIDIAS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := StrToInt64(MediaID);
    Qry.ExecSQL;
    Trans.Commit;

    BtnRefreshMidiasClick(Self);
    LogMessage('Mídia "' + MediaNome + '" removida.');
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnRefreshMidiasClick(Sender: TObject);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
  Row: Integer;
begin
  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'SELECT ID, NOME_EXIBICAO, NOME_ARQUIVO, TIPO_MIDIA, DURACAO_PADRAO_SEG, TAMANHO_BYTES, HASH_MD5 ' +
                    'FROM MIDIAS ORDER BY ID DESC';
    Qry.Open;

    GridMidias.RowCount := 1;
    Row := 1;
    while not Qry.EOF do
    begin
      GridMidias.RowCount := Row + 1;
      GridMidias.Cells[0, Row] := Qry.FieldByName('ID').AsString;
      GridMidias.Cells[1, Row] := Qry.FieldByName('NOME_EXIBICAO').AsString;
      GridMidias.Cells[2, Row] := Qry.FieldByName('NOME_ARQUIVO').AsString;
      GridMidias.Cells[3, Row] := Qry.FieldByName('TIPO_MIDIA').AsString;
      GridMidias.Cells[4, Row] := Qry.FieldByName('DURACAO_PADRAO_SEG').AsString;
      GridMidias.Cells[5, Row] := FormatFloat('0.00', Qry.FieldByName('TAMANHO_BYTES').AsLargeInt / (1024 * 1024));
      GridMidias.Cells[6, Row] := Qry.FieldByName('HASH_MD5').AsString;
      Inc(Row);
      Qry.Next;
    end;
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;

  // Atualiza também a lista de playlists e preview da primeira mídia
  GridPlaylistsSelection(Self, 0, GridPlaylists.Row);
  if GridMidias.RowCount > 1 then
    GridMidiasSelection(Self, 0, 1)
  else
    GridMidiasSelection(Self, 0, 0);
end;

procedure TFrmServerMain.PageControlMainChange(Sender: TObject);
begin
  if PageControlMain.ActivePage <> TabMidias then
    StopEmbeddedVideo;

  if PageControlMain.ActivePage = TabPlaylists then
    BtnRefreshPlaylistsClick(Self)
  else if PageControlMain.ActivePage = TabMidias then
    BtnRefreshMidiasClick(Self)
  else if PageControlMain.ActivePage = TabAgendamentos then
    BtnRefreshAgendamentosClick(Self)
  else if PageControlMain.ActivePage = TabTelas then
    BtnRefreshTelasClick(Self);
end;

procedure TFrmServerMain.OnVideoMediaEnd(Sender: TObject);
begin
  FIsVideoPlaying := False;
  FIsVideoPaused := False;
  FCurrentPlayingFile := '';
  BtnPlayMedia.Caption := '▶️ Reproduzir';
  BtnStopMedia.Enabled := False;
end;

procedure TFrmServerMain.StopEmbeddedVideo;
begin
  if Assigned(FVlcPlayer) then
    FVlcPlayer.Stop;

  FIsVideoPlaying := False;
  FIsVideoPaused := False;
  FCurrentPlayingFile := '';

  BtnPlayMedia.Caption := '▶️ Reproduzir';
  BtnStopMedia.Enabled := False;
  PanelVideoCanvas.Visible := False;
end;

function TFrmServerMain.FindMediaFilePath(const AFileName: string): string;
var
  MediaDirs: array[0..1] of string;
  i: Integer;
begin
  Result := '';
  if Trim(AFileName) = '' then Exit;

  MediaDirs[0] := ExtractFilePath(ParamStr(0)) + 'media' + PathDelim;
  MediaDirs[1] := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'media' + PathDelim;

  for i := 0 to High(MediaDirs) do
  begin
    if FileExists(MediaDirs[i] + AFileName) then
    begin
      Result := MediaDirs[i] + AFileName;
      Break;
    end;
  end;
end;

procedure TFrmServerMain.GridMidiasSelection(Sender: TObject; aCol, aRow: Integer);
var
  FileName, FilePath, Tipo: string;
begin
  StopEmbeddedVideo;

  if (aRow < 1) or (aRow >= GridMidias.RowCount) or (GridMidias.Cells[2, aRow] = '') then
  begin
    ImagePreview.Picture.Clear;
    ImagePreview.Visible := True;
    PanelVideoCanvas.Visible := False;
    LblPreviewTitle.Caption := 'Nenhuma mídia selecionada';
    LblPreviewFileName.Caption := '';
    LblPreviewType.Caption := '';
    LblPreviewResolution.Caption := '';
    LblPreviewMD5.Caption := '';
    BtnPlayMedia.Enabled := False;
    BtnStopMedia.Enabled := False;
    BtnOpenExternal.Enabled := False;
    Exit;
  end;

  FileName := GridMidias.Cells[2, aRow];
  Tipo := UpperCase(GridMidias.Cells[3, aRow]);
  FilePath := FindMediaFilePath(FileName);

  LblPreviewTitle.Caption := GridMidias.Cells[1, aRow];
  LblPreviewFileName.Caption := 'Arquivo: ' + FileName;
  LblPreviewType.Caption := 'Tipo: ' + Tipo + ' | Duração: ' + GridMidias.Cells[4, aRow] + 's';
  LblPreviewResolution.Caption := 'Tamanho: ' + GridMidias.Cells[5, aRow] + ' MB';
  LblPreviewMD5.Caption := 'MD5: ' + Copy(GridMidias.Cells[6, aRow], 1, 16) + '...';
  BtnStopMedia.Enabled := False;

  if (Tipo = 'STREAM') or (Tipo = 'YOUTUBE') then
  begin
    BtnPlayMedia.Enabled := True;
    BtnOpenExternal.Enabled := True;
    BtnPlayMedia.Caption := '🌐 Abrir no Navegador';
    ImagePreview.Picture.Clear;
    ImagePreview.Visible := True;
    PanelVideoCanvas.Visible := False;
    LblPreviewResolution.Caption := 'Transmissão Online (YouTube / Web)';
  end
  else
  begin
    BtnPlayMedia.Enabled := (FilePath <> '') and FileExists(FilePath);
    BtnOpenExternal.Enabled := (FilePath <> '') and FileExists(FilePath);

    if (Tipo = 'IMAGE') and (FilePath <> '') and FileExists(FilePath) then
    begin
      PanelVideoCanvas.Visible := False;
      ImagePreview.Visible := True;
      try
        ImagePreview.Picture.LoadFromFile(FilePath);
        LblPreviewResolution.Caption := Format('Resolução: %dx%d (%s MB)',
          [ImagePreview.Picture.Width, ImagePreview.Picture.Height, GridMidias.Cells[5, aRow]]);
      except
        ImagePreview.Picture.Clear;
      end;
      BtnPlayMedia.Caption := '👁️ Abrir Imagem';
    end
    else if (Tipo = 'VIDEO') then
    begin
      ImagePreview.Picture.Clear;
      ImagePreview.Visible := False;
      PanelVideoCanvas.Visible := True;
      BtnPlayMedia.Caption := '▶️ Reproduzir';
    end
    else
    begin
      ImagePreview.Picture.Clear;
      ImagePreview.Visible := True;
      PanelVideoCanvas.Visible := False;
      BtnPlayMedia.Caption := '▶️ Reproduzir';
    end;
  end;
end;

procedure TFrmServerMain.BtnPlayMediaClick(Sender: TObject);
var
  FileName, FilePath, Tipo: string;
begin
  if (GridMidias.Row < 1) or (GridMidias.Cells[2, GridMidias.Row] = '') then Exit;
  FileName := GridMidias.Cells[2, GridMidias.Row];
  Tipo := UpperCase(GridMidias.Cells[3, GridMidias.Row]);

  if (Tipo = 'STREAM') or (Tipo = 'YOUTUBE') then
  begin
    if Pos('youtube_', FileName) = 1 then
      OpenURL('https://www.youtube.com/watch?v=' + Copy(FileName, 9, Length(FileName)))
    else
      OpenURL(FileName);
    Exit;
  end;

  FilePath := FindMediaFilePath(FileName);

  if (FilePath = '') or not FileExists(FilePath) then
  begin
    ShowMessage('Arquivo de mídia não encontrado: ' + FileName);
    Exit;
  end;

  if Tipo = 'VIDEO' then
  begin
    if FIsVlcInitialized and Assigned(FVlcPlayer) then
    begin
      if FIsVideoPlaying and not FIsVideoPaused then
      begin
        // Pausar
        FVlcPlayer.Pause;
        FIsVideoPaused := True;
        BtnPlayMedia.Caption := '▶️ Continuar';
      end
      else if FIsVideoPlaying and FIsVideoPaused then
      begin
        // Continuar
        FVlcPlayer.Resume;
        FIsVideoPaused := False;
        BtnPlayMedia.Caption := '⏸️ Pausar';
        BtnStopMedia.Enabled := True;
      end
      else
      begin
        // Iniciar nova reprodução embutida
        ImagePreview.Visible := False;
        PanelVideoCanvas.Visible := True;
        PanelVideoCanvas.BringToFront;

        if FVlcPlayer.PlayFile(FilePath) then
        begin
          FIsVideoPlaying := True;
          FIsVideoPaused := False;
          FCurrentPlayingFile := FilePath;
          BtnPlayMedia.Caption := '⏸️ Pausar';
          BtnStopMedia.Enabled := True;
        end
        else
        begin
          ShowMessage('Não foi possível reproduzir o vídeo na engine LibVLC embutida.');
        end;
      end;
    end
    else
    begin
      // Fallback para player externo caso a libvlc não esteja instalada no SO
      if MessageDlg('LibVLC Não Encontrada',
        'A biblioteca LibVLC (libvlc.so / libvlc.dll) não está disponível no sistema operacional para reprodução embutida.' + LineEnding + LineEnding +
        'Deseja abrir o vídeo no reprodutor padrão do sistema?',
        mtInformation, [mbYes, mbNo], 0) = mrYes then
      begin
        OpenDocument(FilePath);
      end;
    end;
  end
  else
  begin
    // Imagens e outros formatos
    OpenDocument(FilePath);
  end;
end;

procedure TFrmServerMain.BtnStopMediaClick(Sender: TObject);
begin
  StopEmbeddedVideo;
  if (GridMidias.Row >= 1) and (GridMidias.Cells[2, GridMidias.Row] <> '') then
  begin
    if UpperCase(GridMidias.Cells[3, GridMidias.Row]) = 'VIDEO' then
      PanelVideoCanvas.Visible := True;
  end;
end;

procedure TFrmServerMain.BtnOpenExternalClick(Sender: TObject);
var
  FileName, FilePath, Tipo: string;
begin
  if (GridMidias.Row < 1) or (GridMidias.Cells[2, GridMidias.Row] = '') then Exit;
  FileName := GridMidias.Cells[2, GridMidias.Row];
  Tipo := UpperCase(GridMidias.Cells[3, GridMidias.Row]);

  if (Tipo = 'STREAM') or (Tipo = 'YOUTUBE') then
  begin
    if Pos('youtube_', FileName) = 1 then
      OpenURL('https://www.youtube.com/watch?v=' + Copy(FileName, 9, Length(FileName)))
    else
      OpenURL(FileName);
    Exit;
  end;

  FilePath := FindMediaFilePath(FileName);

  if (FilePath <> '') and FileExists(FilePath) then
    OpenDocument(FilePath)
  else
    ShowMessage('Arquivo de mídia não encontrado: ' + FileName);
end;

procedure TFrmServerMain.BtnOpenMediaFolderClick(Sender: TObject);
var
  MediaDir: string;
begin
  MediaDir := ExtractFilePath(ParamStr(0)) + 'media' + PathDelim;
  if not DirectoryExists(MediaDir) then
    ForceDirectories(MediaDir);
  OpenDocument(MediaDir);
end;

{ Playlists }

function TFrmServerMain.GetSelectedPlaylistId: Int64;
begin
  Result := 0;
  if (GridPlaylists.Row >= 1) and (GridPlaylists.Cells[0, GridPlaylists.Row] <> '') then
    Result := StrToInt64Def(GridPlaylists.Cells[0, GridPlaylists.Row], 0);
end;

procedure TFrmServerMain.GridPlaylistsSelection(Sender: TObject; aCol, aRow: Integer);
var
  PID: Int64;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
  Row: Integer;
begin
  PID := GetSelectedPlaylistId;
  GridPlaylistItens.RowCount := 1;
  if PID = 0 then Exit;

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'SELECT pi.ID, pi.ORDEM, m.NOME_EXIBICAO, m.TIPO_MIDIA, pi.DURACAO_EXIBICAO_SEG, pi.TRANSICAO ' +
                    'FROM PLAYLIST_ITENS pi ' +
                    'JOIN MIDIAS m ON m.ID = pi.MIDIA_ID ' +
                    'WHERE pi.PLAYLIST_ID = :PID ' +
                    'ORDER BY pi.ORDEM';
    Qry.ParamByName('PID').AsLargeInt := PID;
    Qry.Open;

    Row := 1;
    while not Qry.EOF do
    begin
      GridPlaylistItens.RowCount := Row + 1;
      GridPlaylistItens.Cells[0, Row] := Qry.FieldByName('ORDEM').AsString;
      GridPlaylistItens.Cells[1, Row] := Qry.FieldByName('NOME_EXIBICAO').AsString;
      GridPlaylistItens.Cells[2, Row] := Qry.FieldByName('TIPO_MIDIA').AsString;
      GridPlaylistItens.Cells[3, Row] := Qry.FieldByName('DURACAO_EXIBICAO_SEG').AsString;
      GridPlaylistItens.Cells[4, Row] := Qry.FieldByName('TRANSICAO').AsString;
      GridPlaylistItens.Cells[5, Row] := Qry.FieldByName('ID').AsString;
      Inc(Row);
      Qry.Next;
    end;
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnRefreshPlaylistsClick(Sender: TObject);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
  Row, OldRow: Integer;
begin
  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'SELECT ID, NOME, IS_PADRAO, ATIVA FROM PLAYLISTS ORDER BY ID';
    Qry.Open;

    OldRow := GridPlaylists.Row;
    GridPlaylists.RowCount := 1;
    Row := 1;
    while not Qry.EOF do
    begin
      GridPlaylists.RowCount := Row + 1;
      GridPlaylists.Cells[0, Row] := Qry.FieldByName('ID').AsString;
      GridPlaylists.Cells[1, Row] := Qry.FieldByName('NOME').AsString;
      if Qry.FieldByName('IS_PADRAO').AsInteger = 1 then
        GridPlaylists.Cells[2, Row] := 'SIM (Fallback)'
      else
        GridPlaylists.Cells[2, Row] := 'NÃO';
      if Qry.FieldByName('ATIVA').AsInteger = 1 then
        GridPlaylists.Cells[3, Row] := 'SIM'
      else
        GridPlaylists.Cells[3, Row] := 'NÃO';
      Inc(Row);
      Qry.Next;
    end;

    if GridPlaylists.RowCount > 1 then
    begin
      if (OldRow >= 1) and (OldRow < GridPlaylists.RowCount) then
        GridPlaylists.Row := OldRow
      else
        GridPlaylists.Row := 1;
      GridPlaylistsSelection(Self, 0, GridPlaylists.Row);
    end
    else
    begin
      GridPlaylistItens.RowCount := 1;
    end;
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnNewPlaylistClick(Sender: TObject);
var
  Nome, Desc: string;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  Nome := InputBox('Nova Playlist', 'Nome da Playlist:', '');
  if Nome = '' then Exit;
  Desc := InputBox('Nova Playlist', 'Descrição (opcional):', '');

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'INSERT INTO PLAYLISTS (NOME, DESCRICAO, IS_PADRAO, ATIVA) VALUES (:NOME, :DESC, 0, 1)';
    Qry.ParamByName('NOME').AsString := Nome;
    Qry.ParamByName('DESC').AsString := Desc;
    Qry.ExecSQL;
    Trans.Commit;

    BtnRefreshPlaylistsClick(Self);
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnSetDefaultPlaylistClick(Sender: TObject);
var
  PID: Int64;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  PID := GetSelectedPlaylistId;
  if PID = 0 then
  begin
    ShowMessage('Selecione uma playlist para definir como padrão.');
    Exit;
  end;

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'UPDATE PLAYLISTS SET IS_PADRAO = 0';
    Qry.ExecSQL;
    Qry.SQL.Text := 'UPDATE PLAYLISTS SET IS_PADRAO = 1 WHERE ID = :PID';
    Qry.ParamByName('PID').AsLargeInt := PID;
    Qry.ExecSQL;
    Trans.Commit;

    BtnRefreshPlaylistsClick(Self);
    ShowMessage('Playlist definida como Padrão de Fallback!');
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnDeletePlaylistClick(Sender: TObject);
var
  PID: Int64;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  PID := GetSelectedPlaylistId;
  if PID = 0 then
  begin
    ShowMessage('Selecione uma playlist para remover.');
    Exit;
  end;

  if MessageDlg('Confirmação', 'Deseja excluir a playlist selecionada?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'DELETE FROM AGENDAMENTOS WHERE PLAYLIST_ID = :PID';
    Qry.ParamByName('PID').AsLargeInt := PID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = :PID';
    Qry.ParamByName('PID').AsLargeInt := PID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'DELETE FROM PLAYLISTS WHERE ID = :PID';
    Qry.ParamByName('PID').AsLargeInt := PID;
    Qry.ExecSQL;
    Trans.Commit;

    BtnRefreshPlaylistsClick(Self);
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnAddPlaylistItemClick(Sender: TObject);
var
  PID, MidiaID: Int64;
  MediaList: TStringList;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
  MaxOrdem, DuracaoSec: Integer;
  ChosenIdx: Integer;
  TransStr: string;
begin
  PID := GetSelectedPlaylistId;
  if PID = 0 then
  begin
    ShowMessage('Selecione uma playlist na lista da esquerda primeiro.');
    Exit;
  end;

  MediaList := TStringList.Create;
  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'SELECT ID, NOME_EXIBICAO, TIPO_MIDIA, DURACAO_PADRAO_SEG FROM MIDIAS ORDER BY NOME_EXIBICAO';
    Qry.Open;

    while not Qry.EOF do
    begin
      MediaList.AddObject(Format('%d: %s [%s]', [Qry.FieldByName('ID').AsLargeInt, Qry.FieldByName('NOME_EXIBICAO').AsString, Qry.FieldByName('TIPO_MIDIA').AsString]),
                          TObject(Pointer(PtrInt(Qry.FieldByName('ID').AsLargeInt))));
      Qry.Next;
    end;

    if MediaList.Count = 0 then
    begin
      ShowMessage('Não há mídias cadastradas no catálogo. Adicione mídias primeiro na aba "Catálogo de Mídias".');
      Exit;
    end;

    // Seleção de mídia
    ChosenIdx := 0;
    if not InputQuery('Adicionar Mídia à Playlist', 'Escolha o número/índice da mídia:' + LineEnding + MediaList.Text, TransStr) then
      Exit;

    MidiaID := StrToInt64Def(Trim(Copy(TransStr, 1, Pos(':', TransStr + ':') - 1)), 0);
    if MidiaID = 0 then
      MidiaID := StrToInt64Def(Trim(TransStr), 0);

    if MidiaID = 0 then
    begin
      ShowMessage('ID de mídia inválido.');
      Exit;
    end;

    // Herda a duração padrão da mídia automaticamente (sem necessidade de perguntar ao usuário)
    Qry.Close;
    Qry.SQL.Text := 'SELECT TIPO_MIDIA, DURACAO_PADRAO_SEG FROM MIDIAS WHERE ID = :MID';
    Qry.ParamByName('MID').AsLargeInt := MidiaID;
    Qry.Open;
    if not Qry.EOF then
      DuracaoSec := Qry.FieldByName('DURACAO_PADRAO_SEG').AsInteger
    else
      DuracaoSec := 10;

    // Calcular próxima ordem
    Qry.Close;
    Qry.SQL.Text := 'SELECT COALESCE(MAX(ORDEM), 0) + 1 AS NEXT_ORD FROM PLAYLIST_ITENS WHERE PLAYLIST_ID = :PID';
    Qry.ParamByName('PID').AsLargeInt := PID;
    Qry.Open;
    MaxOrdem := Qry.FieldByName('NEXT_ORD').AsInteger;

    Qry.Close;
    Qry.SQL.Text := 'INSERT INTO PLAYLIST_ITENS (PLAYLIST_ID, MIDIA_ID, ORDEM, DURACAO_EXIBICAO_SEG, TRANSICAO) ' +
                    'VALUES (:PID, :MID, :ORD, :DUR, ''CUT'')';
    Qry.ParamByName('PID').AsLargeInt := PID;
    Qry.ParamByName('MID').AsLargeInt := MidiaID;
    Qry.ParamByName('ORD').AsInteger := MaxOrdem;
    Qry.ParamByName('DUR').AsInteger := DuracaoSec;
    Qry.ExecSQL;
    Trans.Commit;

    GridPlaylistsSelection(Self, 0, GridPlaylists.Row);
  finally
    MediaList.Free;
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnMoveItemUpClick(Sender: TObject);
var
  CurRow, PrevRow: Integer;
  CurItemID, PrevItemID: Int64;
  CurOrd, PrevOrd: Integer;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  CurRow := GridPlaylistItens.Row;
  if CurRow <= 1 then Exit;
  PrevRow := CurRow - 1;

  CurItemID := StrToInt64Def(GridPlaylistItens.Cells[5, CurRow], 0);
  PrevItemID := StrToInt64Def(GridPlaylistItens.Cells[5, PrevRow], 0);
  CurOrd := StrToIntDef(GridPlaylistItens.Cells[0, CurRow], 0);
  PrevOrd := StrToIntDef(GridPlaylistItens.Cells[0, PrevRow], 0);

  if (CurItemID = 0) or (PrevItemID = 0) then Exit;

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;

    Qry.SQL.Text := 'UPDATE PLAYLIST_ITENS SET ORDEM = :ORD WHERE ID = :ID';
    Qry.ParamByName('ORD').AsInteger := PrevOrd;
    Qry.ParamByName('ID').AsLargeInt := CurItemID;
    Qry.ExecSQL;

    Qry.ParamByName('ORD').AsInteger := CurOrd;
    Qry.ParamByName('ID').AsLargeInt := PrevItemID;
    Qry.ExecSQL;
    Trans.Commit;

    GridPlaylistsSelection(Self, 0, GridPlaylists.Row);
    GridPlaylistItens.Row := PrevRow;
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnMoveItemDownClick(Sender: TObject);
var
  CurRow, NextRow: Integer;
  CurItemID, NextItemID: Int64;
  CurOrd, NextOrd: Integer;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  CurRow := GridPlaylistItens.Row;
  if (CurRow < 1) or (CurRow >= GridPlaylistItens.RowCount - 1) then Exit;
  NextRow := CurRow + 1;

  CurItemID := StrToInt64Def(GridPlaylistItens.Cells[5, CurRow], 0);
  NextItemID := StrToInt64Def(GridPlaylistItens.Cells[5, NextRow], 0);
  CurOrd := StrToIntDef(GridPlaylistItens.Cells[0, CurRow], 0);
  NextOrd := StrToIntDef(GridPlaylistItens.Cells[0, NextRow], 0);

  if (CurItemID = 0) or (NextItemID = 0) then Exit;

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;

    Qry.SQL.Text := 'UPDATE PLAYLIST_ITENS SET ORDEM = :ORD WHERE ID = :ID';
    Qry.ParamByName('ORD').AsInteger := NextOrd;
    Qry.ParamByName('ID').AsLargeInt := CurItemID;
    Qry.ExecSQL;

    Qry.ParamByName('ORD').AsInteger := CurOrd;
    Qry.ParamByName('ID').AsLargeInt := NextItemID;
    Qry.ExecSQL;
    Trans.Commit;

    GridPlaylistsSelection(Self, 0, GridPlaylists.Row);
    GridPlaylistItens.Row := NextRow;
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnDeletePlaylistItemClick(Sender: TObject);
var
  ItemID: Int64;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  if (GridPlaylistItens.Row < 1) or (GridPlaylistItens.Cells[5, GridPlaylistItens.Row] = '') then
  begin
    ShowMessage('Selecione um item da playlist para remover.');
    Exit;
  end;

  ItemID := StrToInt64Def(GridPlaylistItens.Cells[5, GridPlaylistItens.Row], 0);
  if ItemID = 0 then Exit;

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'DELETE FROM PLAYLIST_ITENS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := ItemID;
    Qry.ExecSQL;
    Trans.Commit;

    GridPlaylistsSelection(Self, 0, GridPlaylists.Row);
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

{ Agendamentos }

procedure TFrmServerMain.BtnRefreshAgendamentosClick(Sender: TObject);
var
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
  Row: Integer;
  DataIniStr, DataFimStr, HoraIniStr, HoraFimStr: string;
begin
  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'SELECT a.ID, a.NOME_EVENTO, p.NOME AS PLAYLIST_NOME, ' +
                    't.NOME AS TELA_NOME, t.IP_LOCAL AS TELA_IP, ' +
                    'a.DATA_INICIO, a.DATA_FIM, a.HORA_INICIO, a.HORA_FIM, a.DIAS_SEMANA, a.PRIORIDADE, a.ATIVO ' +
                    'FROM AGENDAMENTOS a ' +
                    'JOIN PLAYLISTS p ON p.ID = a.PLAYLIST_ID ' +
                    'LEFT JOIN TELAS t ON t.ID = a.TELA_ID ' +
                    'ORDER BY a.PRIORIDADE DESC, a.ID DESC';
    Qry.Open;

    GridAgendamentos.RowCount := 1;
    Row := 1;
    while not Qry.EOF do
    begin
      GridAgendamentos.RowCount := Row + 1;
      GridAgendamentos.Cells[0, Row] := Qry.FieldByName('ID').AsString;
      GridAgendamentos.Cells[1, Row] := Qry.FieldByName('NOME_EVENTO').AsString;
      GridAgendamentos.Cells[2, Row] := Qry.FieldByName('PLAYLIST_NOME').AsString;
      
      if Qry.FieldByName('TELA_NOME').IsNull or (Trim(Qry.FieldByName('TELA_NOME').AsString) = '') then
        GridAgendamentos.Cells[3, Row] := '[TODAS AS TELAS - GLOBAL]'
      else
        GridAgendamentos.Cells[3, Row] := Qry.FieldByName('TELA_NOME').AsString + ' (' + Qry.FieldByName('TELA_IP').AsString + ')';

      if not Qry.FieldByName('DATA_INICIO').IsNull then
        DataIniStr := FormatDateTime('yyyy-mm-dd', Qry.FieldByName('DATA_INICIO').AsDateTime)
      else
        DataIniStr := '';

      if not Qry.FieldByName('DATA_FIM').IsNull then
        DataFimStr := FormatDateTime('yyyy-mm-dd', Qry.FieldByName('DATA_FIM').AsDateTime)
      else
        DataFimStr := '';

      if not Qry.FieldByName('HORA_INICIO').IsNull then
        HoraIniStr := FormatDateTime('hh:nn:ss', Qry.FieldByName('HORA_INICIO').AsDateTime)
      else
        HoraIniStr := '';

      if not Qry.FieldByName('HORA_FIM').IsNull then
        HoraFimStr := FormatDateTime('hh:nn:ss', Qry.FieldByName('HORA_FIM').AsDateTime)
      else
        HoraFimStr := '';

      GridAgendamentos.Cells[4, Row] := DataIniStr + ' a ' + DataFimStr;
      GridAgendamentos.Cells[5, Row] := HoraIniStr + ' às ' + HoraFimStr;
      GridAgendamentos.Cells[6, Row] := Qry.FieldByName('DIAS_SEMANA').AsString;
      GridAgendamentos.Cells[7, Row] := Qry.FieldByName('PRIORIDADE').AsString;
      if (not Qry.FieldByName('ATIVO').IsNull) and (Qry.FieldByName('ATIVO').AsInteger = 1) then
        GridAgendamentos.Cells[8, Row] := 'SIM'
      else
        GridAgendamentos.Cells[8, Row] := 'NÃO';
      Inc(Row);
      Qry.Next;
    end;
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

function ConvertDaysToMask(const ADays: string): string;
var
  Mask: string;
  CleanStr: string;
  i: Integer;
begin
  CleanStr := Trim(ADays);
  if (Length(CleanStr) = 7) and (CleanStr[1] in ['0', '1']) and (CleanStr[2] in ['0', '1']) then
    Exit(CleanStr);

  Mask := '0000000';
  for i := 1 to 7 do
  begin
    if Pos(IntToStr(i), CleanStr) > 0 then
      Mask[i] := '1';
  end;
  if Mask = '0000000' then
    Mask := '1111111';
  Result := Mask;
end;

function ParseSafeDate(const AStr: string; const ADefault: TDate): TDate;
var
  Y, M, D: Word;
  DashPos1, DashPos2: SizeInt;
  SlashPos1, SlashPos2: SizeInt;
  Trimmed: string;
begin
  Result := ADefault;
  Trimmed := Trim(AStr);
  if Trimmed = '' then Exit;

  DashPos1 := Pos('-', Trimmed);
  if DashPos1 > 0 then
  begin
    DashPos2 := Pos('-', Trimmed, DashPos1 + 1);
    if DashPos2 > 0 then
    begin
      Y := StrToIntDef(Copy(Trimmed, 1, DashPos1 - 1), 0);
      M := StrToIntDef(Copy(Trimmed, DashPos1 + 1, DashPos2 - DashPos1 - 1), 0);
      D := StrToIntDef(Copy(Trimmed, DashPos2 + 1, Length(Trimmed)), 0);
      if (Y >= 2000) and (M in [1..12]) and (D in [1..31]) then
        Exit(EncodeDate(Y, M, D));
    end;
  end;

  SlashPos1 := Pos('/', Trimmed);
  if SlashPos1 > 0 then
  begin
    SlashPos2 := Pos('/', Trimmed, SlashPos1 + 1);
    if SlashPos2 > 0 then
    begin
      D := StrToIntDef(Copy(Trimmed, 1, SlashPos1 - 1), 0);
      M := StrToIntDef(Copy(Trimmed, SlashPos1 + 1, SlashPos2 - SlashPos1 - 1), 0);
      Y := StrToIntDef(Copy(Trimmed, SlashPos2 + 1, Length(Trimmed)), 0);
      if (Y >= 2000) and (M in [1..12]) and (D in [1..31]) then
        Exit(EncodeDate(Y, M, D));
    end;
  end;
end;

function ParseSafeTime(const AStr: string; const ADefault: TTime): TTime;
var
  H, N, S: Word;
  ColonPos1, ColonPos2: SizeInt;
  Trimmed: string;
begin
  Result := ADefault;
  Trimmed := Trim(AStr);
  if Trimmed = '' then Exit;

  ColonPos1 := Pos(':', Trimmed);
  if ColonPos1 > 0 then
  begin
    ColonPos2 := Pos(':', Trimmed, ColonPos1 + 1);
    H := StrToIntDef(Copy(Trimmed, 1, ColonPos1 - 1), 0);
    if ColonPos2 > 0 then
    begin
      N := StrToIntDef(Copy(Trimmed, ColonPos1 + 1, ColonPos2 - ColonPos1 - 1), 0);
      S := StrToIntDef(Copy(Trimmed, ColonPos2 + 1, Length(Trimmed)), 0);
    end
    else
    begin
      N := StrToIntDef(Copy(Trimmed, ColonPos1 + 1, Length(Trimmed)), 0);
      S := 0;
    end;

    if (H <= 23) and (N <= 59) and (S <= 59) then
      Exit(EncodeTime(H, N, S, 0));
  end;
end;

procedure TFrmServerMain.BtnNewAgendamentoClick(Sender: TObject);
var
  NomeEvento, TempStr: string;
  PlaylistID, TelaID: Int64;
  DataIni, DataFim, HoraIni, HoraFim, DiasSemana: string;
  Prioridade: Integer;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
  PlaylistsList, TelasList: TStringList;
begin
  PlaylistsList := TStringList.Create;
  TelasList := TStringList.Create;
  TelasList.Add('0: [TODAS AS TELAS - GLOBAL]');

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;

    // Buscar Playlists
    Qry.SQL.Text := 'SELECT ID, NOME FROM PLAYLISTS WHERE ATIVA = 1 ORDER BY NOME';
    Qry.Open;
    while not Qry.EOF do
    begin
      PlaylistsList.Add(Format('%d: %s', [Qry.FieldByName('ID').AsLargeInt, Qry.FieldByName('NOME').AsString]));
      Qry.Next;
    end;

    if PlaylistsList.Count = 0 then
    begin
      ShowMessage('Nenhuma playlist ativa encontrada. Crie uma playlist primeiro.');
      Exit;
    end;

    // Buscar Telas
    Qry.Close;
    Qry.SQL.Text := 'SELECT ID, NOME, IP_LOCAL FROM TELAS ORDER BY NOME';
    Qry.Open;
    while not Qry.EOF do
    begin
      TelasList.Add(Format('%d: %s (%s)', [Qry.FieldByName('ID').AsLargeInt, Qry.FieldByName('NOME').AsString, Qry.FieldByName('IP_LOCAL').AsString]));
      Qry.Next;
    end;

    NomeEvento := InputBox('Novo Agendamento', 'Nome da Campanha / Evento:', 'Campanha Especial');
    if NomeEvento = '' then Exit;

    // Escolher Playlist
    TempStr := '';
    if not InputQuery('Escolha a Playlist', 'Digite o ID da Playlist:' + LineEnding + PlaylistsList.Text, TempStr) then Exit;
    PlaylistID := StrToInt64Def(Trim(Copy(TempStr, 1, Pos(':', TempStr + ':') - 1)), 0);
    if PlaylistID = 0 then PlaylistID := StrToInt64Def(Trim(TempStr), 0);
    if PlaylistID = 0 then
    begin
      ShowMessage('ID de playlist inválido.');
      Exit;
    end;

    // Escolher Tela de Destino
    TempStr := '';
    if not InputQuery('Direcionamento por IP / Tela', 'Digite o ID da tela (0 = Todas as Telas):' + LineEnding + TelasList.Text, TempStr) then Exit;
    TelaID := StrToInt64Def(Trim(Copy(TempStr, 1, Pos(':', TempStr + ':') - 1)), 0);
    if (TelaID = 0) and (Trim(TempStr) <> '0') and (Trim(TempStr) <> '') then
      TelaID := StrToInt64Def(Trim(TempStr), 0);

    DataIni := InputBox('Data Inicial', 'Data de Início (AAAA-MM-DD):', FormatDateTime('yyyy-mm-dd', Date));
    DataFim := InputBox('Data Final', 'Data de Término (AAAA-MM-DD):', FormatDateTime('yyyy-mm-dd', Date + 30));
    HoraIni := InputBox('Horário Inicial', 'Hora Inicial (HH:MM:SS):', '00:00:00');
    HoraFim := InputBox('Horário Final', 'Hora Final (HH:MM:SS):', '23:59:59');
    DiasSemana := InputBox('Dias da Semana', 'Dias ativos (1=Dom,2=Seg,3=Ter,4=Qua,5=Qui,6=Sex,7=Sab):', '1,2,3,4,5,6,7');
    Prioridade := StrToIntDef(InputBox('Prioridade', 'Prioridade (ex: 10 = Normal, 100 = Alta):', '10'), 10);

    Qry.Close;
    if TelaID > 0 then
    begin
      Qry.SQL.Text := 'INSERT INTO AGENDAMENTOS (NOME_EVENTO, PLAYLIST_ID, TELA_ID, DATA_INICIO, DATA_FIM, HORA_INICIO, HORA_FIM, DIAS_SEMANA, PRIORIDADE, ATIVO) ' +
                      'VALUES (:NOME, :PID, :TELA, :DINI, :DFIM, :HINI, :HFIM, :DIAS, :PRIO, 1)';
      Qry.ParamByName('TELA').AsLargeInt := TelaID;
    end
    else
    begin
      Qry.SQL.Text := 'INSERT INTO AGENDAMENTOS (NOME_EVENTO, PLAYLIST_ID, TELA_ID, DATA_INICIO, DATA_FIM, HORA_INICIO, HORA_FIM, DIAS_SEMANA, PRIORIDADE, ATIVO) ' +
                      'VALUES (:NOME, :PID, NULL, :DINI, :DFIM, :HINI, :HFIM, :DIAS, :PRIO, 1)';
    end;

    Qry.ParamByName('NOME').AsString := NomeEvento;
    Qry.ParamByName('PID').AsLargeInt := PlaylistID;
    Qry.ParamByName('DINI').AsDate := ParseSafeDate(DataIni, Date);
    Qry.ParamByName('DFIM').AsDate := ParseSafeDate(DataFim, Date + 30);
    Qry.ParamByName('HINI').AsTime := ParseSafeTime(HoraIni, EncodeTime(0, 0, 0, 0));
    Qry.ParamByName('HFIM').AsTime := ParseSafeTime(HoraFim, EncodeTime(23, 59, 59, 0));
    Qry.ParamByName('DIAS').AsString := ConvertDaysToMask(DiasSemana);
    Qry.ParamByName('PRIO').AsInteger := Prioridade;
    Qry.ExecSQL;
    Trans.Commit;

    BtnRefreshAgendamentosClick(Self);
    LogMessage('Agendamento "' + NomeEvento + '" criado com sucesso!');
    ShowMessage('Agendamento criado com sucesso!');
  finally
    PlaylistsList.Free;
    TelasList.Free;
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.BtnDeleteAgendamentoClick(Sender: TObject);
var
  AgendamentoID: Int64;
  Conn: TIBConnection;
  Trans: TSQLTransaction;
  Qry: TSQLQuery;
begin
  if (GridAgendamentos.Row < 1) or (GridAgendamentos.Cells[0, GridAgendamentos.Row] = '') then
  begin
    ShowMessage('Selecione um agendamento para excluir.');
    Exit;
  end;

  AgendamentoID := StrToInt64Def(GridAgendamentos.Cells[0, GridAgendamentos.Row], 0);
  if AgendamentoID = 0 then Exit;

  if MessageDlg('Confirmação', 'Deseja remover o agendamento selecionado?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Conn := FDbManager.CreateConnection(Trans);
  Qry := TSQLQuery.Create(nil);
  try
    Conn.Connected := True;
    Qry.Database := Conn;
    Qry.Transaction := Trans;
    Qry.SQL.Text := 'DELETE FROM AGENDAMENTOS WHERE ID = :ID';
    Qry.ParamByName('ID').AsLargeInt := AgendamentoID;
    Qry.ExecSQL;
    Trans.Commit;

    BtnRefreshAgendamentosClick(Self);
  finally
    Qry.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure TFrmServerMain.TimerAutoRefreshTimer(Sender: TObject);
begin
  // Atualiza a lista de telas periodicamente para refletir status online/heartbeat
  if TabTelas.IsVisible then
    BtnRefreshTelasClick(Self);
end;

end.
