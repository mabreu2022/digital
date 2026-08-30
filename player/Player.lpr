program Player;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  uFrmPlayer,
  uKioskUtils,
  uLibVlcWrapper,
  uScheduler,
  uCacheManager,
  uProofOfPlay,
  uSyncWorker,
  uPlayerConfig;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TFrmPlayer, FrmPlayer);
  Application.Run;
end.
