unit uScheduler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpjson, jsonparser;

type
  { Representação de um item de mídia dentro de uma playlist }
  TScheduleMediaItem = record
    MediaID: Int64;
    MD5Hash: string;
    FileName: string;
    MediaType: string;       // 'VIDEO', 'IMAGE', 'HTML', 'STREAM'
    DurationSec: Integer;     // Duração planejada de exibição
    OrderIndex: Integer;
    Transition: string;
    DownloadURL: string;
    LocalFilePath: string;   // Caminho absoluto resolvido no cache local
  end;

  TScheduleMediaItemArray = array of TScheduleMediaItem;

  { Representação de uma playlist }
  TSchedulePlaylist = class
  private
    FPlaylistID: Int64;
    FName: string;
    FIsDefault: Boolean;
    FItems: TScheduleMediaItemArray;
    FTotalDurationSec: Integer;
    procedure RecalculateTotalDuration;
  public
    constructor Create;
    procedure AddItem(const AItem: TScheduleMediaItem);
    procedure Clear;
    function ItemCount: Integer;
    function GetItem(AIndex: Integer): TScheduleMediaItem;
    function IsValid: Boolean;
    
    property PlaylistID: Int64 read FPlaylistID write FPlaylistID;
    property Name: string read FName write FName;
    property IsDefault: Boolean read FIsDefault write FIsDefault;
    property Items: TScheduleMediaItemArray read FItems;
    property TotalDurationSec: Integer read FTotalDurationSec;
  end;

  { Representação de uma regra de agendamento }
  TScheduleRule = class
  private
    FScheduleID: Int64;
    FEventName: string;
    FPriority: Integer;
    FStartDate: TDate;
    FEndDate: TDate;
    FStartTime: TTime;
    FEndTime: TTime;
    FDaysOfWeekMask: string; // Exemplo: '0111110' (Dom=1, Seg=2, Ter=3, Qua=4, Qui=5, Sex=6, Sab=7)
    FPlaylist: TSchedulePlaylist;
  public
    constructor Create;
    destructor Destroy; override;
    
    // Verifica se a regra é válida no momento exato informado
    function IsActiveAt(const ADateTime: TDateTime): Boolean;
    
    property ScheduleID: Int64 read FScheduleID write FScheduleID;
    property EventName: string read FEventName write FEventName;
    property Priority: Integer read FPriority write FPriority;
    property StartDate: TDate read FStartDate write FStartDate;
    property EndDate: TDate read FEndDate write FEndDate;
    property StartTime: TTime read FStartTime write FStartTime;
    property EndTime: TTime read FEndTime write FEndTime;
    property DaysOfWeekMask: string read FDaysOfWeekMask write FDaysOfWeekMask;
    property Playlist: TSchedulePlaylist read FPlaylist write FPlaylist;
  end;

  { Resultado da resolução de grade para o segundo exato }
  TScheduleResolution = record
    HasValidMedia: Boolean;
    IsFallback: Boolean;
    ActiveScheduleID: Int64;
    ActivePlaylistID: Int64;
    PlaylistName: string;
    MediaItem: TScheduleMediaItem;
    ItemIndex: Integer;
    SecondsIntoItem: Integer;
    RemainingSecondsInItem: Integer;
  end;

  { Motor do Scheduler do Player }
  TSignageScheduler = class
  private
    FFallbackPlaylist: TSchedulePlaylist;
    FSchedules: TList; // Lista de TScheduleRule
    FCacheDirectory: string;
    FCurrentPlayingIndex: Integer;
    FCurrentItemStartedAt: TDateTime;
    FCurrentResolution: TScheduleResolution;
    
    function ParsePlaylistFromJson(APlaylistObj: TJSONObject): TSchedulePlaylist;
    procedure ParseScheduleRuleFromJson(ASchedObj: TJSONObject);
    procedure ResolveLocalPaths;
  public
    constructor Create(const ACacheDir: string);
    destructor Destroy; override;
    
    procedure Clear;
    function LoadFromJsonString(const AJsonText: string): Boolean;
    function LoadFromFile(const AFilePath: string): Boolean;
    
    // Resolve e calcula o que deve ser reproduzido no timestamp exato
    function ResolveAt(const ADateTime: TDateTime): TScheduleResolution;
    
    // Avança para o próximo item respeitando a playlist ativa no momento
    function MoveToNextItem(const ADateTime: TDateTime): TScheduleResolution;
    
    // Extrai lista com todos os hashes MD5 que precisam estar em cache
    procedure ExtractRequiredHashes(AOutList: TStrings);
    
    property FallbackPlaylist: TSchedulePlaylist read FFallbackPlaylist;
    property CacheDirectory: string read FCacheDirectory write FCacheDirectory;
    property CurrentResolution: TScheduleResolution read FCurrentResolution;
  end;

implementation

{ TSchedulePlaylist }

constructor TSchedulePlaylist.Create;
begin
  inherited Create;
  FPlaylistID := 0;
  FName := '';
  FIsDefault := False;
  SetLength(FItems, 0);
  FTotalDurationSec := 0;
end;

procedure TSchedulePlaylist.AddItem(const AItem: TScheduleMediaItem);
var
  Len: Integer;
begin
  Len := Length(FItems);
  SetLength(FItems, Len + 1);
  FItems[Len] := AItem;
  RecalculateTotalDuration;
end;

procedure TSchedulePlaylist.Clear;
begin
  SetLength(FItems, 0);
  FTotalDurationSec := 0;
end;

function TSchedulePlaylist.ItemCount: Integer;
begin
  Result := Length(FItems);
end;

function TSchedulePlaylist.GetItem(AIndex: Integer): TScheduleMediaItem;
begin
  if (AIndex >= 0) and (AIndex < Length(FItems)) then
    Result := FItems[AIndex]
  else
    Result := Default(TScheduleMediaItem);
end;

function TSchedulePlaylist.IsValid: Boolean;
begin
  Result := (Length(FItems) > 0);
end;

procedure TSchedulePlaylist.RecalculateTotalDuration;
var
  i, Total: Integer;
begin
  Total := 0;
  for i := 0 to High(FItems) do
    Total := Total + FItems[i].DurationSec;
  FTotalDurationSec := Total;
end;

{ TScheduleRule }

constructor TScheduleRule.Create;
begin
  inherited Create;
  FScheduleID := 0;
  FPriority := 1;
  FDaysOfWeekMask := '1111111';
  FPlaylist := nil;
end;

destructor TScheduleRule.Destroy;
begin
  if Assigned(FPlaylist) then
    FPlaylist.Free;
  inherited Destroy;
end;

function TScheduleRule.IsActiveAt(const ADateTime: TDateTime): Boolean;
var
  CurDate: TDate;
  CurTime: TTime;
  DayIdx: Integer; // 1 = Domingo, 2 = Segunda, ..., 7 = Sábado
  MaskChar: Char;
begin
  Result := False;

  if (FPlaylist = nil) or (not FPlaylist.IsValid) then Exit;

  CurDate := DateOf(ADateTime);
  CurTime := TimeOf(ADateTime);

  // 1. Validação de Intervalo de Datas
  if (CurDate < FStartDate) or (CurDate > FEndDate) then Exit;

  // 2. Validação do Dia da Semana
  DayIdx := DayOfWeek(ADateTime); // 1 = Dom .. 7 = Sab
  if (Length(FDaysOfWeekMask) = 7) then
  begin
    MaskChar := FDaysOfWeekMask[DayIdx];
    if MaskChar <> '1' then Exit;
  end;

  // 3. Validação de Janela Horária (Hora Início até Hora Fim)
  if FStartTime <= FEndTime then
  begin
    // Janela normal no mesmo dia (ex: 08:00 às 18:00)
    if (CurTime < FStartTime) or (CurTime > FEndTime) then Exit;
  end
  else
  begin
    // Janela que ultrapassa a meia-noite (ex: 22:00 às 04:00)
    if (CurTime < FStartTime) and (CurTime > FEndTime) then Exit;
  end;

  Result := True;
end;

{ TSignageScheduler }

constructor TSignageScheduler.Create(const ACacheDir: string);
begin
  inherited Create;
  FCacheDirectory := IncludeTrailingPathDelimiter(ACacheDir);
  FFallbackPlaylist := TSchedulePlaylist.Create;
  FFallbackPlaylist.IsDefault := True;
  FSchedules := TList.Create;
  FCurrentPlayingIndex := 0;
  FCurrentItemStartedAt := 0;
  FCurrentResolution := Default(TScheduleResolution);
end;

destructor TSignageScheduler.Destroy;
begin
  Clear;
  FFallbackPlaylist.Free;
  FSchedules.Free;
  inherited Destroy;
end;

procedure TSignageScheduler.Clear;
var
  i: Integer;
begin
  FFallbackPlaylist.Clear;
  for i := 0 to FSchedules.Count - 1 do
    TScheduleRule(FSchedules[i]).Free;
  FSchedules.Clear;
  FCurrentPlayingIndex := 0;
  FCurrentResolution := Default(TScheduleResolution);
end;

function TSignageScheduler.ParsePlaylistFromJson(APlaylistObj: TJSONObject): TSchedulePlaylist;
var
  Pl: TSchedulePlaylist;
  ItemsArr: TJSONArray;
  ItemObj: TJSONObject;
  i: Integer;
  MediaItem: TScheduleMediaItem;
begin
  Pl := TSchedulePlaylist.Create;
  if APlaylistObj = nil then Exit(Pl);

  Pl.PlaylistID := APlaylistObj.Get('id', Int64(0));
  Pl.Name := APlaylistObj.Get('name', '');
  Pl.IsDefault := (APlaylistObj.Get('is_default', 0) = 1);

  ItemsArr := APlaylistObj.Get('items', TJSONArray(nil));
  if ItemsArr <> nil then
  begin
    for i := 0 to ItemsArr.Count - 1 do
    begin
      ItemObj := ItemsArr.Objects[i];
      MediaItem := Default(TScheduleMediaItem);
      MediaItem.MediaID := ItemObj.Get('media_id', Int64(0));
      MediaItem.MD5Hash := ItemObj.Get('hash_md5', '');
      MediaItem.FileName := ItemObj.Get('filename', '');
      MediaItem.MediaType := UpperCase(ItemObj.Get('type', 'VIDEO'));
      MediaItem.DurationSec := ItemObj.Get('duration_sec', 10);
      MediaItem.OrderIndex := ItemObj.Get('order', i + 1);
      MediaItem.Transition := ItemObj.Get('transition', 'CUT');
      MediaItem.DownloadURL := ItemObj.Get('download_url', '');

      Pl.AddItem(MediaItem);
    end;
  end;

  Result := Pl;
end;

procedure TSignageScheduler.ParseScheduleRuleFromJson(ASchedObj: TJSONObject);
var
  Rule: TScheduleRule;
  DaysArr: TJSONArray;
  Mask: string;
  i, Val: Integer;
  PlObj: TJSONObject;
begin
  if ASchedObj = nil then Exit;

  Rule := TScheduleRule.Create;
  Rule.ScheduleID := ASchedObj.Get('id', Int64(0));
  Rule.EventName := ASchedObj.Get('event_name', '');
  Rule.Priority := ASchedObj.Get('priority', 1);

  // Formato de Data: YYYY-MM-DD
  Rule.StartDate := ScanDateTime('yyyy-mm-dd', ASchedObj.Get('start_date', '2000-01-01'));
  Rule.EndDate := ScanDateTime('yyyy-mm-dd', ASchedObj.Get('end_date', '2099-12-31'));

  // Formato de Hora: HH:NN:SS
  Rule.StartTime := ScanDateTime('hh:nn:ss', ASchedObj.Get('start_time', '00:00:00'));
  Rule.EndTime := ScanDateTime('hh:nn:ss', ASchedObj.Get('end_time', '23:59:59'));

  // Parser dos dias da semana (array de 1..7 ou string de 7 caracteres)
  if ASchedObj.Find('days_of_week') is TJSONArray then
  begin
    DaysArr := ASchedObj.Get('days_of_week', TJSONArray(nil));
    Mask := '0000000';
    for i := 0 to DaysArr.Count - 1 do
    begin
      Val := DaysArr.Integers[i]; // 1 = Dom .. 7 = Sab
      if (Val >= 1) and (Val <= 7) then
        Mask[Val] := '1';
    end;
    Rule.DaysOfWeekMask := Mask;
  end
  else
    Rule.DaysOfWeekMask := ASchedObj.Get('days_of_week', '1111111');

  // Playlist do agendamento
  PlObj := ASchedObj.Get('playlist', TJSONObject(nil));
  if PlObj <> nil then
    Rule.Playlist := ParsePlaylistFromJson(PlObj);

  FSchedules.Add(Rule);
end;

procedure TSignageScheduler.ResolveLocalPaths;
var
  i, j: Integer;
  Rule: TScheduleRule;
  Item: ^TScheduleMediaItem;
begin
  // Resolver caminhos na playlist padrão
  for i := 0 to High(FFallbackPlaylist.FItems) do
  begin
    Item := @FFallbackPlaylist.FItems[i];
    Item^.LocalFilePath := FCacheDirectory + Item^.MD5Hash + ExtractFileExt(Item^.FileName);
    if not FileExists(Item^.LocalFilePath) then
      Item^.LocalFilePath := FCacheDirectory + Item^.FileName;
  end;

  // Resolver caminhos nos agendamentos
  for i := 0 to FSchedules.Count - 1 do
  begin
    Rule := TScheduleRule(FSchedules[i]);
    if Rule.Playlist <> nil then
    begin
      for j := 0 to High(Rule.Playlist.FItems) do
      begin
        Item := @Rule.Playlist.FItems[j];
        Item^.LocalFilePath := FCacheDirectory + Item^.MD5Hash + ExtractFileExt(Item^.FileName);
        if not FileExists(Item^.LocalFilePath) then
          Item^.LocalFilePath := FCacheDirectory + Item^.FileName;
      end;
    end;
  end;
end;

function TSignageScheduler.LoadFromJsonString(const AJsonText: string): Boolean;
var
  Parser: TJSONParser;
  RootObj: TJSONObject;
  FallbackObj: TJSONObject;
  SchedsArr: TJSONArray;
  i: Integer;
begin
  Result := False;
  Clear;

  Parser := TJSONParser.Create(AJsonText);
  try
    try
      RootObj := TJSONObject(Parser.Parse);
      if RootObj = nil then Exit;

      try
        // 1. Parse da Playlist Padrão de Fallback
        FallbackObj := RootObj.Get('fallback_playlist', TJSONObject(nil));
        if FallbackObj <> nil then
        begin
          FFallbackPlaylist.Free;
          FFallbackPlaylist := ParsePlaylistFromJson(FallbackObj);
          FFallbackPlaylist.IsDefault := True;
        end;

        // 2. Parse da Grade de Agendamentos
        SchedsArr := RootObj.Get('schedules', TJSONArray(nil));
        if SchedsArr <> nil then
        begin
          for i := 0 to SchedsArr.Count - 1 do
            ParseScheduleRuleFromJson(SchedsArr.Objects[i]);
        end;

        ResolveLocalPaths;
        Result := True;
      finally
        RootObj.Free;
      end;
    except
      on E: Exception do
        Result := False;
    end;
  finally
    Parser.Free;
  end;
end;

function TSignageScheduler.LoadFromFile(const AFilePath: string): Boolean;
var
  Stream: TStringList;
begin
  Result := False;
  if not FileExists(AFilePath) then Exit;

  Stream := TStringList.Create;
  try
    Stream.LoadFromFile(AFilePath);
    Result := LoadFromJsonString(Stream.Text);
  finally
    Stream.Free;
  end;
end;

function TSignageScheduler.ResolveAt(const ADateTime: TDateTime): TScheduleResolution;
var
  i: Integer;
  BestRule, CurRule: TScheduleRule;
  SelectedPlaylist: TSchedulePlaylist;
  TargetIndex: Integer;
begin
  Result := Default(TScheduleResolution);
  BestRule := nil;

  // 1. Procurar o agendamento ativo com a MAIOR prioridade
  for i := 0 to FSchedules.Count - 1 do
  begin
    CurRule := TScheduleRule(FSchedules[i]);
    if CurRule.IsActiveAt(ADateTime) then
    begin
      if (BestRule = nil) or (CurRule.Priority > BestRule.Priority) then
        BestRule := CurRule;
    end;
  end;

  // 2. Selecionar Playlist (Agendamento prioritário ou Fallback Padrão)
  if BestRule <> nil then
  begin
    SelectedPlaylist := BestRule.Playlist;
    Result.IsFallback := False;
    Result.ActiveScheduleID := BestRule.ScheduleID;
  end
  else
  begin
    SelectedPlaylist := FFallbackPlaylist;
    Result.IsFallback := True;
    Result.ActiveScheduleID := 0;
  end;

  if (SelectedPlaylist = nil) or (SelectedPlaylist.ItemCount = 0) then
  begin
    Result.HasValidMedia := False;
    Exit;
  end;

  // 3. Resolver item na playlist
  TargetIndex := FCurrentPlayingIndex mod SelectedPlaylist.ItemCount;
  Result.HasValidMedia := True;
  Result.ActivePlaylistID := SelectedPlaylist.PlaylistID;
  Result.PlaylistName := SelectedPlaylist.Name;
  Result.ItemIndex := TargetIndex;
  Result.MediaItem := SelectedPlaylist.GetItem(TargetIndex);
  Result.SecondsIntoItem := 0;
  Result.RemainingSecondsInItem := Result.MediaItem.DurationSec;

  FCurrentResolution := Result;
end;

function TSignageScheduler.MoveToNextItem(const ADateTime: TDateTime): TScheduleResolution;
begin
  Inc(FCurrentPlayingIndex);
  FCurrentItemStartedAt := ADateTime;
  Result := ResolveAt(ADateTime);
end;

procedure TSignageScheduler.ExtractRequiredHashes(AOutList: TStrings);
var
  i, j: Integer;
  Rule: TScheduleRule;
begin
  if AOutList = nil then Exit;

  for i := 0 to FFallbackPlaylist.ItemCount - 1 do
    AOutList.Add(FFallbackPlaylist.GetItem(i).MD5Hash);

  for i := 0 to FSchedules.Count - 1 do
  begin
    Rule := TScheduleRule(FSchedules[i]);
    if Rule.Playlist <> nil then
    begin
      for j := 0 to Rule.Playlist.ItemCount - 1 do
        AOutList.Add(Rule.Playlist.GetItem(j).MD5Hash);
    end;
  end;
end;

end.
