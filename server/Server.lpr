program Server;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // Framework LCL
  Forms,
  uDbConnection, uSignageQueries, uPlayerApiController, uLibVlcWrapper, uFrmServerMain;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TFrmServerMain, FrmServerMain);
  Application.Run;
end.
