unit uKioskUtils;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls
  {$IFDEF WINDOWS}
  , Windows
  {$ENDIF}
  {$IFDEF UNIX}
  , BaseUnix, Unix
  {$ENDIF};

type
  { TKioskManager }
  TKioskManager = class
  private
    class var FIsCursorHidden: Boolean;
    class var FScreensaverDisabled: Boolean;
  public
    // Configura a janela em modo Kiosk absoluto
    class procedure ApplyKioskMode(AForm: TCustomForm);
    
    // Ocultar/Exibir cursor do mouse
    class procedure HideMouseCursor;
    class procedure ShowMouseCursor;
    
    // Prevenir suspensão de tela / Protetor de tela
    class procedure DisableScreenSaver;
    class procedure RestoreScreenSaver;
    
    // Mantém a tela acordada (chamado em timer periódico se necessário)
    class procedure KeepDisplayAwake;
  end;

implementation

{ TKioskManager }

class procedure TKioskManager.ApplyKioskMode(AForm: TCustomForm);
begin
  if AForm = nil then Exit;

  // 1. Remover bordas e decorações de janela
  AForm.BorderStyle := bsNone;
  
  // 2. Maximizar e fixar no topo (Kiosk Fullscreen)
  AForm.WindowState := wsMaximized;
  AForm.FormStyle := fsStayOnTop;
  
  // 3. Forçar dimensões da tela primária
  AForm.Left := 0;
  AForm.Top := 0;
  AForm.Width := Screen.Width;
  AForm.Height := Screen.Height;

  // 4. Ocultar cursor no formulário
  AForm.Cursor := crNone;
  
  // 5. Aplicar bloqueios de sistema
  HideMouseCursor;
  DisableScreenSaver;
end;

class procedure TKioskManager.HideMouseCursor;
begin
  if FIsCursorHidden then Exit;

  {$IFDEF WINDOWS}
  ShowCursor(False);
  {$ENDIF}

  {$IFDEF UNIX}
  // No Linux/X11, podemos configurar o cursor global do Screen
  Screen.Cursor := crNone;
  // Opcional: invocar 'unclutter -idle 0' ou xset via processo se disponível
  {$ENDIF}

  FIsCursorHidden := True;
end;

class procedure TKioskManager.ShowMouseCursor;
begin
  if not FIsCursorHidden then Exit;

  {$IFDEF WINDOWS}
  ShowCursor(True);
  {$ENDIF}

  {$IFDEF UNIX}
  Screen.Cursor := crDefault;
  {$ENDIF}

  FIsCursorHidden := False;
end;

class procedure TKioskManager.DisableScreenSaver;
{$IFDEF WINDOWS}
const
  ES_CONTINUOUS       = $80000000;
  ES_SYSTEM_REQUIRED  = $00000001;
  ES_DISPLAY_REQUIRED = $00000002;
  ES_AWAYMODE_REQUIRED= $00000040;
{$ENDIF}
begin
  if FScreensaverDisabled then Exit;

  {$IFDEF WINDOWS}
  // Informa ao kernel do Windows que o display e o sistema devem permanecer ativos
  SetThreadExecutionState(ES_CONTINUOUS or ES_SYSTEM_REQUIRED or ES_DISPLAY_REQUIRED);
  {$ENDIF}

  {$IFDEF UNIX}
  // No Linux, desabilitar DPMS e Screensaver via xset / xdg-screensaver
  fpSystem('xset s off -dpms >/dev/null 2>&1');
  fpSystem('xset s noblank >/dev/null 2>&1');
  {$ENDIF}

  FScreensaverDisabled := True;
end;

class procedure TKioskManager.RestoreScreenSaver;
{$IFDEF WINDOWS}
const
  ES_CONTINUOUS = $80000000;
{$ENDIF}
begin
  if not FScreensaverDisabled then Exit;

  {$IFDEF WINDOWS}
  SetThreadExecutionState(ES_CONTINUOUS);
  {$ENDIF}

  {$IFDEF UNIX}
  fpSystem('xset s on +dpms >/dev/null 2>&1');
  {$ENDIF}

  FScreensaverDisabled := False;
end;

class procedure TKioskManager.KeepDisplayAwake;
begin
  {$IFDEF WINDOWS}
  SetThreadExecutionState($80000000 or $00000001 or $00000002);
  {$ENDIF}

  {$IFDEF UNIX}
  // Reset de screensaver do servidor X11
  fpSystem('xset s reset >/dev/null 2>&1');
  {$ENDIF}
end;

end.
