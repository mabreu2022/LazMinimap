unit LazarusCodeMiniMap;

{$mode objfpc}{$H+}
{$warn 5024 off : no warning about unused parameters}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, ExtCtrls, Menus,
  LCLType, LCLIntf, SynEdit, SynEditTypes, SrcEditorIntf, IDEIntf;

const
  LINE_PITCH   = 2; // 2 pixels verticais por linha de código
  CHAR_WIDTH   = 2; // 2 pixels horizontais por caractere
  LEFT_MARGIN  = 6;
  RIGHT_MARGIN = 6;

type

  { TCodeEditorMiniMapControl: Renderiza a miniatura do código e barra de viewport }
  TCodeEditorMiniMapControl = class(TCustomControl)
  private
    FSynEdit: TCustomSynEdit;
    FBackColor: TColor;
    FBorderColor: TColor;
    FViewportColor: TColor;
    FViewportHoverColor: TColor;
    FViewportBorderColor: TColor;

    // Cores de sintaxe do código no minimapa
    FKeywordColor: TColor;
    FCommentColor: TColor;
    FStringColor: TColor;
    FDirectiveColor: TColor;
    FIdentifierColor: TColor;

    // Viewport metrics calculadas em Paint
    FVTop: Integer;
    FVHeight: Integer;
    FDragging: Boolean;
    FHoveringViewport: Boolean;

    // Menu de contexto
    FPopupMenu: TPopupMenu;
    procedure SetSynEdit(AValue: TCustomSynEdit);
    procedure ScrollToY(AY: Integer);
    procedure BuildPopupMenu;
    procedure OnMenuWidthClick(Sender: TObject);
    procedure OnMenuToggleVisible(Sender: TObject);
    function IsPascalKeyword(const S: string): Boolean;
    procedure DrawLineMiniature(const S: string; LineY, MaxW: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property TargetSynEdit: TCustomSynEdit read FSynEdit write SetSynEdit;
  end;

  { TCodeEditorMiniMapManager: Monitora abas do editor e acopla o minimapa à direita do TSynEdit }
  TCodeEditorMiniMapManager = class(TComponent)
  private
    FMiniMap: TCodeEditorMiniMapControl;
    FHookedSynEdit: TCustomSynEdit;
    FTimer: TTimer;
    FUpdating: Boolean;
    FLastTopLine: Integer;
    FLastLineCount: Integer;
    FLastLinesInWindow: Integer;
    procedure OnEditorChange(Sender: TObject);
    procedure OnSynStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    procedure OnTimer(Sender: TObject);
    procedure HookSynEdit(ASynEdit: TCustomSynEdit);
    procedure UnhookSynEdit;
    procedure UpdateActiveEditor;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property MiniMap: TCodeEditorMiniMapControl read FMiniMap;
  end;

procedure Register;

implementation

var
  CodeMiniMapGlobal: TCodeEditorMiniMapManager = nil;

{ TCodeEditorMiniMapControl }

constructor TCodeEditorMiniMapControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 110;
  DoubleBuffered := True;
  Cursor := crHandPoint;
  ShowHint := False;

  // Tema escuro moderno de alto contraste (estilo VSCode / Delphi)
  FBackColor           := TColor($1E1E1E);
  FBorderColor         := TColor($2D2D2D);
  FViewportColor       := TColor($33363B);
  FViewportHoverColor  := TColor($42464D);
  FViewportBorderColor := TColor($585D66);

  // Cores de sintaxe
  FKeywordColor    := TColor($569CD6); // Azul
  FCommentColor    := TColor($6A9955); // Verde
  FStringColor     := TColor($CE9178); // Laranja claro
  FDirectiveColor  := TColor($9E9E9E); // Cinza médio
  FIdentifierColor := TColor($CCCCCC); // Texto claro

  BuildPopupMenu;
end;

destructor TCodeEditorMiniMapControl.Destroy;
begin
  FPopupMenu.Free;
  inherited Destroy;
end;

procedure TCodeEditorMiniMapControl.BuildPopupMenu;
var
  Item: TMenuItem;
begin
  FPopupMenu := TPopupMenu.Create(Self);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Largura: 80 px';
  Item.Tag := 80;
  Item.OnClick := @OnMenuWidthClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Largura: 110 px (Padrão)';
  Item.Tag := 110;
  Item.OnClick := @OnMenuWidthClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Largura: 140 px';
  Item.Tag := 140;
  Item.OnClick := @OnMenuWidthClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Largura: 180 px';
  Item.Tag := 180;
  Item.OnClick := @OnMenuWidthClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '-';
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Ocultar Mini-mapa de Código';
  Item.OnClick := @OnMenuToggleVisible;
  FPopupMenu.Items.Add(Item);

  PopupMenu := FPopupMenu;
end;

procedure TCodeEditorMiniMapControl.OnMenuWidthClick(Sender: TObject);
begin
  if Sender is TMenuItem then
  begin
    Width := TMenuItem(Sender).Tag;
    Invalidate;
  end;
end;

procedure TCodeEditorMiniMapControl.OnMenuToggleVisible(Sender: TObject);
begin
  Visible := False;
end;

procedure TCodeEditorMiniMapControl.SetSynEdit(AValue: TCustomSynEdit);
begin
  if FSynEdit <> AValue then
  begin
    FSynEdit := AValue;
    Invalidate;
  end;
end;

function TCodeEditorMiniMapControl.IsPascalKeyword(const S: string): Boolean;
const
  Keywords: array[0..36] of string = (
    'unit', 'interface', 'implementation', 'initialization', 'finalization',
    'uses', 'type', 'class', 'const', 'var', 'function', 'procedure',
    'constructor', 'destructor', 'begin', 'end', 'if', 'then', 'else',
    'while', 'for', 'do', 'to', 'downto', 'repeat', 'until', 'try',
    'finally', 'except', 'case', 'of', 'record', 'property', 'read',
    'write', 'override', 'inherited'
  );
var
  I: Integer;
  L: string;
begin
  L := LowerCase(S);
  for I := Low(Keywords) to High(Keywords) do
    if L = Keywords[I] then Exit(True);
  Result := False;
end;

procedure TCodeEditorMiniMapControl.DrawLineMiniature(const S: string; LineY, MaxW: Integer);
var
  Len, I, WordStart: Integer;
  Indent: Integer;
  X1, X2: Integer;
  WordStr: string;
  InString: Boolean;
  CurX: Integer;
  Ch: Char;
begin
  Len := Length(S);
  if Len = 0 then Exit;

  // Calcula indentação inicial
  Indent := 0;
  while (Indent < Len) and (S[Indent + 1] in [' ', #9]) do
  begin
    if S[Indent + 1] = #9 then
      Inc(Indent, 2)
    else
      Inc(Indent);
  end;

  if Indent >= Len then Exit;

  CurX := LEFT_MARGIN + Min(60, Indent * CHAR_WIDTH);

  // Linha de comentário completo
  if (Indent + 2 <= Len) and (S[Indent + 1] = '/') and (S[Indent + 2] = '/') then
  begin
    X1 := CurX;
    X2 := Min(MaxW, X1 + (Len - Indent) * CHAR_WIDTH);
    Canvas.Pen.Color := FCommentColor;
    Canvas.Line(X1, LineY, X2, LineY);
    Exit;
  end;

  // Diretiva de compilador {$...}
  if (Indent + 2 <= Len) and (S[Indent + 1] = '{') and (S[Indent + 2] = '$') then
  begin
    X1 := CurX;
    X2 := Min(MaxW, X1 + (Len - Indent) * CHAR_WIDTH);
    Canvas.Pen.Color := FDirectiveColor;
    Canvas.Line(X1, LineY, X2, LineY);
    Exit;
  end;

  // Tokenização rápida dos identificadores e palavras da linha
  I := Indent + 1;
  InString := False;
  while (I <= Len) and (CurX < MaxW) do
  begin
    Ch := S[I];

    if Ch = '''' then
    begin
      InString := not InString;
      Canvas.Pen.Color := FStringColor;
      Canvas.Line(CurX, LineY, Min(MaxW, CurX + 3), LineY);
      Inc(CurX, 4);
      Inc(I);
      Continue;
    end;

    if InString then
    begin
      Canvas.Pen.Color := FStringColor;
      Canvas.Line(CurX, LineY, Min(MaxW, CurX + 2), LineY);
      Inc(CurX, 2);
      Inc(I);
      Continue;
    end;

    if (Ch = '/') and (I < Len) and (S[I + 1] = '/') then
    begin
      // Restante da linha é comentário
      Canvas.Pen.Color := FCommentColor;
      Canvas.Line(CurX, LineY, Min(MaxW, CurX + (Len - I + 1) * CHAR_WIDTH), LineY);
      Break;
    end;

    if Ch in ['a'..'z', 'A'..'Z', '_'] then
    begin
      WordStart := I;
      while (I <= Len) and (S[I] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
        Inc(I);
      WordStr := Copy(S, WordStart, I - WordStart);

      if IsPascalKeyword(WordStr) then
        Canvas.Pen.Color := FKeywordColor
      else if (Length(WordStr) > 1) and (WordStr[1] in ['T', 'I']) and (WordStr[2] in ['A'..'Z']) then
        Canvas.Pen.Color := TColor($4EC9B0) // Tipos/Classes (Teal)
      else
        Canvas.Pen.Color := FIdentifierColor;

      X1 := CurX;
      X2 := Min(MaxW, X1 + Length(WordStr) * CHAR_WIDTH);
      Canvas.Line(X1, LineY, X2, LineY);
      CurX := X2 + 2;
    end
    else
    begin
      if not (Ch in [' ', #9]) then
      begin
        Canvas.Pen.Color := FIdentifierColor;
        Canvas.Line(CurX, LineY, Min(MaxW, CurX + 2), LineY);
        Inc(CurX, 3);
      end
      else
        Inc(CurX, 2);
      Inc(I);
    end;
  end;
end;

procedure TCodeEditorMiniMapControl.Paint;
var
  H, TotalLines, LinesInWindow, MaxTopLine: Integer;
  TotalContentH, MaxScroll, ScrollOffsetY: Integer;
  TopLine: Integer;
  Progress: Double;
  FirstLine, LastLine, L, LineY, MaxW: Integer;
  VRect: TRect;
  LineStr: string;
begin
  // Fundo principal
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBackColor;
  Canvas.FillRect(ClientRect);

  // Linha divisória esquerda
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FBorderColor;
  Canvas.Pen.Width := 1;
  Canvas.Line(0, 0, 0, ClientHeight);

  if (FSynEdit = nil) or (FSynEdit.Lines = nil) then Exit;

  TotalLines := FSynEdit.Lines.Count;
  if TotalLines <= 0 then Exit;

  H := ClientHeight;
  LinesInWindow := Max(1, FSynEdit.LinesInWindow);
  TopLine := Max(1, FSynEdit.TopLine);
  MaxTopLine := Max(1, TotalLines - LinesInWindow + 1);
  TotalContentH := TotalLines * LINE_PITCH;
  MaxW := ClientWidth - RIGHT_MARGIN;

  // 1. Cálculo de rolagem do minimapa e limites visíveis
  if TotalContentH <= H then
  begin
    ScrollOffsetY := 0;
    FirstLine := 1;
    LastLine := TotalLines;
    FVHeight := Max(16, Round(LinesInWindow * LINE_PITCH));
    FVTop := Round((TopLine - 1) * LINE_PITCH);
  end
  else
  begin
    MaxScroll := TotalContentH - H;
    Progress := (TopLine - 1) / Max(1, MaxTopLine - 1);
    Progress := Max(0.0, Min(1.0, Progress));

    ScrollOffsetY := Round(Progress * MaxScroll);
    FirstLine := Max(1, (ScrollOffsetY div LINE_PITCH) + 1);
    LastLine := Min(TotalLines, FirstLine + (H div LINE_PITCH) + 2);

    FVHeight := Max(20, Round(H * (LinesInWindow / TotalLines)));
    FVHeight := Min(H, FVHeight);
    FVTop := Round(Progress * (H - FVHeight));
  end;

  // 2. Renderiza as linhas de código visíveis na área do minimapa
  Canvas.Pen.Width := 1;
  for L := FirstLine to LastLine do
  begin
    LineY := (L - 1) * LINE_PITCH - ScrollOffsetY;
    if (LineY >= 0) and (LineY < H) then
    begin
      LineStr := FSynEdit.Lines[L - 1];
      DrawLineMiniature(LineStr, LineY, MaxW);
    end;
  end;

  // 3. Renderiza o retângulo translúcido da Viewport (área ativa visível no editor)
  VRect := Rect(1, FVTop, ClientWidth - 1, FVTop + FVHeight);

  Canvas.Brush.Style := bsSolid;
  if FDragging or FHoveringViewport then
    Canvas.Brush.Color := FViewportHoverColor
  else
    Canvas.Brush.Color := FViewportColor;

  Canvas.FillRect(VRect);

  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FViewportBorderColor;
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(VRect);
end;

procedure TCodeEditorMiniMapControl.ScrollToY(AY: Integer);
var
  H, TotalLines, LinesInWindow, MaxTopLine: Integer;
  TotalHeight, VHeight: Integer;
  Progress: Double;
  TargetTopLine: Integer;
begin
  if (FSynEdit = nil) or (FSynEdit.Lines = nil) then Exit;

  TotalLines := FSynEdit.Lines.Count;
  if TotalLines <= 0 then Exit;

  H := ClientHeight;
  LinesInWindow := Max(1, FSynEdit.LinesInWindow);
  MaxTopLine := Max(1, TotalLines - LinesInWindow + 1);
  TotalHeight := TotalLines * LINE_PITCH;

  if TotalHeight <= H then
  begin
    TargetTopLine := 1 + (AY div LINE_PITCH) - (LinesInWindow div 2);
  end
  else
  begin
    VHeight := Max(20, Round(H * (LinesInWindow / TotalLines)));
    VHeight := Min(H, VHeight);
    Progress := (AY - (VHeight div 2)) / Max(1, H - VHeight);
    Progress := Max(0.0, Min(1.0, Progress));
    TargetTopLine := 1 + Round(Progress * (MaxTopLine - 1));
  end;

  TargetTopLine := Max(1, Min(MaxTopLine, TargetTopLine));
  if FSynEdit.TopLine <> TargetTopLine then
  begin
    FSynEdit.TopLine := TargetTopLine;
    Invalidate;
  end;
end;

procedure TCodeEditorMiniMapControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    MouseCapture := True;
    ScrollToY(Y);
  end;
end;

procedure TCodeEditorMiniMapControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  IsOverV: Boolean;
begin
  inherited MouseMove(Shift, X, Y);

  if FDragging then
  begin
    ScrollToY(Y);
    Exit;
  end;

  IsOverV := (Y >= FVTop) and (Y <= FVTop + FVHeight);
  if IsOverV <> FHoveringViewport then
  begin
    FHoveringViewport := IsOverV;
    Invalidate;
  end;
end;

procedure TCodeEditorMiniMapControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragging then
  begin
    FDragging := False;
    MouseCapture := False;
    Invalidate;
  end;
end;

procedure TCodeEditorMiniMapControl.MouseLeave;
begin
  inherited MouseLeave;
  if FHoveringViewport then
  begin
    FHoveringViewport := False;
    Invalidate;
  end;
end;

function TCodeEditorMiniMapControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  LinesToScroll: Integer;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if (FSynEdit <> nil) and (FSynEdit.Lines <> nil) then
  begin
    LinesToScroll := 5;
    if WheelDelta > 0 then
      FSynEdit.TopLine := Max(1, FSynEdit.TopLine - LinesToScroll)
    else
      FSynEdit.TopLine := Min(FSynEdit.Lines.Count, FSynEdit.TopLine + LinesToScroll);
    Invalidate;
    Result := True;
  end;
end;

{ TCodeEditorMiniMapManager }

constructor TCodeEditorMiniMapManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FMiniMap := TCodeEditorMiniMapControl.Create(Self);
  FMiniMap.Width := 110;
  FMiniMap.Visible := False;

  if SourceEditorManagerIntf <> nil then
  begin
    SourceEditorManagerIntf.RegisterChangeEvent(semEditorActivate, @OnEditorChange);
    SourceEditorManagerIntf.RegisterChangeEvent(semEditorStatus, @OnEditorChange);
    SourceEditorManagerIntf.RegisterChangeEvent(semEditorDestroy, @OnEditorChange);
    SourceEditorManagerIntf.RegisterChangeEvent(semWindowActivate, @OnEditorChange);
  end;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 60; // 16 FPS para sincronização suave
  FTimer.OnTimer := @OnTimer;
  FTimer.Enabled := True;
end;

destructor TCodeEditorMiniMapManager.Destroy;
begin
  FTimer.Free;

  if SourceEditorManagerIntf <> nil then
  begin
    SourceEditorManagerIntf.UnRegisterChangeEvent(semEditorActivate, @OnEditorChange);
    SourceEditorManagerIntf.UnRegisterChangeEvent(semEditorStatus, @OnEditorChange);
    SourceEditorManagerIntf.UnRegisterChangeEvent(semEditorDestroy, @OnEditorChange);
    SourceEditorManagerIntf.UnRegisterChangeEvent(semWindowActivate, @OnEditorChange);
  end;

  UnhookSynEdit;
  FMiniMap.Free;

  inherited Destroy;
end;

procedure TCodeEditorMiniMapManager.HookSynEdit(ASynEdit: TCustomSynEdit);
begin
  UnhookSynEdit;
  FHookedSynEdit := ASynEdit;
  FMiniMap.TargetSynEdit := ASynEdit;
  if FHookedSynEdit <> nil then
  begin
    FHookedSynEdit.RegisterStatusChangedHandler(@OnSynStatusChange, [scTopLine, scLinesInWindow, scModified]);
    FLastTopLine := FHookedSynEdit.TopLine;
    FLastLinesInWindow := FHookedSynEdit.LinesInWindow;
    if FHookedSynEdit.Lines <> nil then
      FLastLineCount := FHookedSynEdit.Lines.Count
    else
      FLastLineCount := 0;
  end;
  FMiniMap.Invalidate;
end;

procedure TCodeEditorMiniMapManager.UnhookSynEdit;
begin
  if FHookedSynEdit <> nil then
  begin
    try
      FHookedSynEdit.UnRegisterStatusChangedHandler(@OnSynStatusChange);
    except
      // salvaguarda se o controle já estiver em destruição
    end;
    FHookedSynEdit := nil;
  end;
  FMiniMap.TargetSynEdit := nil;
end;

procedure TCodeEditorMiniMapManager.OnSynStatusChange(Sender: TObject; Changes: TSynStatusChanges);
begin
  FMiniMap.Invalidate;
end;

procedure TCodeEditorMiniMapManager.OnEditorChange(Sender: TObject);
begin
  UpdateActiveEditor;
end;

procedure TCodeEditorMiniMapManager.OnTimer(Sender: TObject);
begin
  UpdateActiveEditor;
end;

procedure TCodeEditorMiniMapManager.UpdateActiveEditor;
var
  CurEditor: TSourceEditorInterface;
  SynCtrl: TWinControl;
  TargetSyn: TCustomSynEdit;
  P: TWinControl;
begin
  if FUpdating then Exit;
  FUpdating := True;
  try
    if SourceEditorManagerIntf = nil then
    begin
      if FMiniMap.Visible then FMiniMap.Visible := False;
      Exit;
    end;

    CurEditor := SourceEditorManagerIntf.ActiveEditor;
    if CurEditor = nil then
    begin
      if FMiniMap.Visible then FMiniMap.Visible := False;
      Exit;
    end;

    SynCtrl := CurEditor.EditorControl;
    if (SynCtrl = nil) or not (SynCtrl is TCustomSynEdit) or not SynCtrl.HandleAllocated or not SynCtrl.IsVisible then
    begin
      if FMiniMap.Visible then FMiniMap.Visible := False;
      Exit;
    end;

    TargetSyn := TCustomSynEdit(SynCtrl);
    P := TargetSyn.Parent;
    if (P = nil) or not P.HandleAllocated or not P.IsVisible then
    begin
      if FMiniMap.Visible then FMiniMap.Visible := False;
      Exit;
    end;

    // Conecta como filho do contêiner do SynEdit alinhado à direita
    if FMiniMap.Parent <> P then
    begin
      FMiniMap.Parent := P;
      FMiniMap.Align := alRight;
      FMiniMap.BringToFront;
    end;

    if FHookedSynEdit <> TargetSyn then
      HookSynEdit(TargetSyn);

    if not FMiniMap.Visible then
    begin
      FMiniMap.Visible := True;
      FMiniMap.BringToFront;
    end;

    // Redesenha caso propriedades essenciais tenham mudado
    if (TargetSyn.TopLine <> FLastTopLine) or
       (TargetSyn.LinesInWindow <> FLastLinesInWindow) or
       ((TargetSyn.Lines <> nil) and (TargetSyn.Lines.Count <> FLastLineCount)) then
    begin
      FLastTopLine := TargetSyn.TopLine;
      FLastLinesInWindow := TargetSyn.LinesInWindow;
      if TargetSyn.Lines <> nil then
        FLastLineCount := TargetSyn.Lines.Count
      else
        FLastLineCount := 0;
      FMiniMap.Invalidate;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure Register;
begin
  if CodeMiniMapGlobal = nil then
    CodeMiniMapGlobal := TCodeEditorMiniMapManager.Create(nil);
end;

initialization

finalization
  FreeAndNil(CodeMiniMapGlobal);

end.
