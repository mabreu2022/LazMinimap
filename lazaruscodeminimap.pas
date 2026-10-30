unit LazarusCodeMiniMap;

{$mode objfpc}{$H+}
{$warn 5024 off : no warning about unused parameters}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, ExtCtrls, Menus,
  LCLType, LCLIntf, SynEdit, SynEditTypes, SrcEditorIntf, IDEIntf;

const
  LEFT_MARGIN  = 6;
  RIGHT_MARGIN = 6;

type

  { TCodeMiniMapZoom: Níveis de zoom e escala do minimapa }
  TCodeMiniMapZoom = (
    zmFit,    // Ajustar todo o arquivo à altura da tela (Visão Geral Completa / Sem Zoom)
    zm1x,     // 1x Ultra Compacto (1px por linha)
    zm2x,     // 2x Normal (2px por linha - Padrão)
    zm3x,     // 3x Ampliado (3px por linha)
    zm4x      // 4x Detalhado (4px por linha)
  );

  { TCodeMiniMapRenderMode: Estilo de renderização do código }
  TCodeMiniMapRenderMode = (
    rmSyntaxBlocks, // Barras de sintaxe (rápido, limpo e moderno)
    rmMicroText     // Micro-texto legível (mini font)
  );

  { TCodeEditorMiniMapControl: Renderiza a miniatura do código com controle de zoom e viewport }
  TCodeEditorMiniMapControl = class(TCustomControl)
  private
    FSynEdit: TCustomSynEdit;
    FZoom: TCodeMiniMapZoom;
    FRenderMode: TCodeMiniMapRenderMode;
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
    FTypeColor: TColor;
    FIdentifierColor: TColor;

    // Viewport metrics calculadas em Paint
    FVTop: Integer;
    FVHeight: Integer;
    FDragging: Boolean;
    FHoveringViewport: Boolean;

    // Menu de contexto
    FPopupMenu: TPopupMenu;
    procedure SetSynEdit(AValue: TCustomSynEdit);
    procedure SetZoom(AValue: TCodeMiniMapZoom);
    procedure SetRenderMode(AValue: TCodeMiniMapRenderMode);
    procedure ScrollToY(AY: Integer);
    procedure BuildPopupMenu;
    procedure UpdatePopupMenuChecks;
    procedure OnMenuZoomClick(Sender: TObject);
    procedure OnMenuRenderModeClick(Sender: TObject);
    procedure OnMenuWidthClick(Sender: TObject);
    procedure OnMenuToggleVisible(Sender: TObject);
    function IsPascalKeyword(const S: string): Boolean;
    procedure DrawLineMiniature(const S: string; LineY, MaxW: Integer; APitch: Double);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ZoomIn;
    procedure ZoomOut;
    property TargetSynEdit: TCustomSynEdit read FSynEdit write SetSynEdit;
    property Zoom: TCodeMiniMapZoom read FZoom write SetZoom;
    property RenderMode: TCodeMiniMapRenderMode read FRenderMode write SetRenderMode;
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
  ShowHint := True;

  // Zoom padrão: Normal (2px por linha)
  FZoom := zm2x;
  FRenderMode := rmSyntaxBlocks;

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
  FTypeColor       := TColor($4EC9B0); // Verde água (Teal)
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
  Item, SubItem: TMenuItem;
begin
  FPopupMenu := TPopupMenu.Create(Self);

  // Submenu Zoom / Escala
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Zoom / Escala (Ctrl + Roda do Mouse)';

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Ajustar Todo o Código à Tela (Sem Zoom)';
  SubItem.Tag := Ord(zmFit);
  SubItem.OnClick := @OnMenuZoomClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Zoom 1x - Ultra Compacto (1px)';
  SubItem.Tag := Ord(zm1x);
  SubItem.OnClick := @OnMenuZoomClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Zoom 2x - Normal (2px - Padrão)';
  SubItem.Tag := Ord(zm2x);
  SubItem.OnClick := @OnMenuZoomClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Zoom 3x - Ampliado (3px)';
  SubItem.Tag := Ord(zm3x);
  SubItem.OnClick := @OnMenuZoomClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Zoom 4x - Detalhado (4px)';
  SubItem.Tag := Ord(zm4x);
  SubItem.OnClick := @OnMenuZoomClick;
  Item.Add(SubItem);

  FPopupMenu.Items.Add(Item);

  // Submenu Estilo de Renderização
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Estilo Visual';

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Barras de Sintaxe (Rápido e Limpo)';
  SubItem.Tag := Ord(rmSyntaxBlocks);
  SubItem.OnClick := @OnMenuRenderModeClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Micro-Texto Legível (Mini Font)';
  SubItem.Tag := Ord(rmMicroText);
  SubItem.OnClick := @OnMenuRenderModeClick;
  Item.Add(SubItem);

  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '-';
  FPopupMenu.Items.Add(Item);

  // Submenu Largura
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Largura do Mini-mapa';

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := '80 px (Estreito)';
  SubItem.Tag := 80;
  SubItem.OnClick := @OnMenuWidthClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := '110 px (Padrão)';
  SubItem.Tag := 110;
  SubItem.OnClick := @OnMenuWidthClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := '140 px (Médio)';
  SubItem.Tag := 140;
  SubItem.OnClick := @OnMenuWidthClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := '180 px (Largo)';
  SubItem.Tag := 180;
  SubItem.OnClick := @OnMenuWidthClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := '220 px (Extra Largo)';
  SubItem.Tag := 220;
  SubItem.OnClick := @OnMenuWidthClick;
  Item.Add(SubItem);

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

procedure TCodeEditorMiniMapControl.UpdatePopupMenuChecks;
var
  ZoomMenu, RenderMenu, WidthMenu: TMenuItem;
  I: Integer;
begin
  if (FPopupMenu = nil) or (FPopupMenu.Items.Count < 4) then Exit;

  ZoomMenu := FPopupMenu.Items[0];
  for I := 0 to ZoomMenu.Count - 1 do
    ZoomMenu.Items[I].Checked := (ZoomMenu.Items[I].Tag = Ord(FZoom));

  RenderMenu := FPopupMenu.Items[1];
  for I := 0 to RenderMenu.Count - 1 do
    RenderMenu.Items[I].Checked := (RenderMenu.Items[I].Tag = Ord(FRenderMode));

  WidthMenu := FPopupMenu.Items[3];
  for I := 0 to WidthMenu.Count - 1 do
    WidthMenu.Items[I].Checked := (WidthMenu.Items[I].Tag = Width);
end;

procedure TCodeEditorMiniMapControl.OnMenuZoomClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    Zoom := TCodeMiniMapZoom(TMenuItem(Sender).Tag);
end;

procedure TCodeEditorMiniMapControl.OnMenuRenderModeClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    RenderMode := TCodeMiniMapRenderMode(TMenuItem(Sender).Tag);
end;

procedure TCodeEditorMiniMapControl.OnMenuWidthClick(Sender: TObject);
begin
  if Sender is TMenuItem then
  begin
    Width := TMenuItem(Sender).Tag;
    UpdatePopupMenuChecks;
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

procedure TCodeEditorMiniMapControl.SetZoom(AValue: TCodeMiniMapZoom);
var
  ZoomDesc: string;
begin
  if FZoom <> AValue then
  begin
    FZoom := AValue;
    UpdatePopupMenuChecks;

    case FZoom of
      zmFit: ZoomDesc := 'Ajustar Todo o Código (Sem Zoom)';
      zm1x:  ZoomDesc := 'Zoom 1x (Ultra Compacto)';
      zm2x:  ZoomDesc := 'Zoom 2x (Normal)';
      zm3x:  ZoomDesc := 'Zoom 3x (Ampliado)';
      zm4x:  ZoomDesc := 'Zoom 4x (Detalhado)';
    end;
    Hint := Format('Mini-mapa: %s [Ctrl+Wheel para alterar]', [ZoomDesc]);

    Invalidate;
  end;
end;

procedure TCodeEditorMiniMapControl.SetRenderMode(AValue: TCodeMiniMapRenderMode);
begin
  if FRenderMode <> AValue then
  begin
    FRenderMode := AValue;
    UpdatePopupMenuChecks;
    Invalidate;
  end;
end;

procedure TCodeEditorMiniMapControl.ZoomIn;
begin
  case FZoom of
    zmFit: Zoom := zm1x;
    zm1x:  Zoom := zm2x;
    zm2x:  Zoom := zm3x;
    zm3x:  Zoom := zm4x;
    zm4x:  Exit;
  end;
end;

procedure TCodeEditorMiniMapControl.ZoomOut;
begin
  case FZoom of
    zmFit: Exit;
    zm1x:  Zoom := zmFit;
    zm2x:  Zoom := zm1x;
    zm3x:  Zoom := zm2x;
    zm4x:  Zoom := zm3x;
  end;
end;

procedure TCodeEditorMiniMapControl.DblClick;
begin
  inherited DblClick;
  // Duplo-clique alterna rapidamente entre visão geral completa (Sem Zoom) e Normal
  if FZoom = zmFit then
    Zoom := zm2x
  else
    Zoom := zmFit;
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

procedure TCodeEditorMiniMapControl.DrawLineMiniature(const S: string; LineY, MaxW: Integer; APitch: Double);
var
  Len, I, WordStart: Integer;
  Indent: Integer;
  X1, X2: Integer;
  WordStr: string;
  InString: Boolean;
  CurX: Integer;
  Ch: Char;
  CharW: Integer;
  UseMicroText: Boolean;
  TokenColor: TColor;
begin
  Len := Length(S);
  if Len = 0 then Exit;

  // Largura horizontal proporcional ao zoom
  if APitch < 1.8 then
    CharW := 1
  else if APitch >= 3.5 then
    CharW := 3
  else
    CharW := 2;

  UseMicroText := (FRenderMode = rmMicroText) and (APitch >= 3.0);

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

  CurX := LEFT_MARGIN + Min(60, Indent * CharW);

  // Linha de comentário completo
  if (Indent + 2 <= Len) and (S[Indent + 1] = '/') and (S[Indent + 2] = '/') then
  begin
    X1 := CurX;
    X2 := Min(MaxW, X1 + (Len - Indent) * CharW);
    Canvas.Pen.Color := FCommentColor;
    Canvas.Line(X1, LineY, X2, LineY);
    Exit;
  end;

  // Diretiva de compilador {$...}
  if (Indent + 2 <= Len) and (S[Indent + 1] = '{') and (S[Indent + 2] = '$') then
  begin
    X1 := CurX;
    X2 := Min(MaxW, X1 + (Len - Indent) * CharW);
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
      Inc(CurX, CharW + 2);
      Inc(I);
      Continue;
    end;

    if InString then
    begin
      Canvas.Pen.Color := FStringColor;
      Canvas.Line(CurX, LineY, Min(MaxW, CurX + 2), LineY);
      Inc(CurX, CharW);
      Inc(I);
      Continue;
    end;

    if (Ch = '/') and (I < Len) and (S[I + 1] = '/') then
    begin
      // Restante da linha é comentário
      Canvas.Pen.Color := FCommentColor;
      Canvas.Line(CurX, LineY, Min(MaxW, CurX + (Len - I + 1) * CharW), LineY);
      Break;
    end;

    if Ch in ['a'..'z', 'A'..'Z', '_'] then
    begin
      WordStart := I;
      while (I <= Len) and (S[I] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
        Inc(I);
      WordStr := Copy(S, WordStart, I - WordStart);

      if IsPascalKeyword(WordStr) then
        TokenColor := FKeywordColor
      else if (Length(WordStr) > 1) and (WordStr[1] in ['T', 'I']) and (WordStr[2] in ['A'..'Z']) then
        TokenColor := FTypeColor
      else
        TokenColor := FIdentifierColor;

      X1 := CurX;
      X2 := Min(MaxW, X1 + Length(WordStr) * CharW);

      if UseMicroText then
      begin
        Canvas.Font.Color := TokenColor;
        Canvas.TextOut(X1, LineY - 2, WordStr);
        CurX := CurX + Canvas.TextWidth(WordStr) + 2;
      end
      else
      begin
        Canvas.Pen.Color := TokenColor;
        Canvas.Line(X1, LineY, X2, LineY);
        CurX := X2 + CharW;
      end;
    end
    else
    begin
      if not (Ch in [' ', #9]) then
      begin
        Canvas.Pen.Color := FIdentifierColor;
        Canvas.Line(CurX, LineY, Min(MaxW, CurX + CharW), LineY);
        Inc(CurX, CharW + 1);
      end
      else
        Inc(CurX, CharW);
      Inc(I);
    end;
  end;
end;

procedure TCodeEditorMiniMapControl.Paint;
var
  H, TotalLines, LinesInWindow, MaxTopLine: Integer;
  Pitch: Double;
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
  MaxW := ClientWidth - RIGHT_MARGIN;

  if (FRenderMode = rmMicroText) then
  begin
    Canvas.Font.Name := 'Arial';
    Canvas.Font.Size := 3;
    Canvas.Brush.Style := bsClear;
  end;

  // 1. Determina o Pitch e limites de acordo com o nível de Zoom
  case FZoom of
    zmFit:
    begin
      // SEM ZOOM: Ajusta o documento inteiro na altura da janela
      Pitch := H / Max(1, TotalLines);
      ScrollOffsetY := 0;
      FirstLine := 1;
      LastLine := TotalLines;

      FVTop := Round((TopLine - 1) * Pitch);
      FVHeight := Max(14, Round(LinesInWindow * Pitch));
      FVHeight := Min(H - FVTop, FVHeight);
    end;

    zm1x, zm2x, zm3x, zm4x:
    begin
      case FZoom of
        zm1x: Pitch := 1.0;
        zm2x: Pitch := 2.0;
        zm3x: Pitch := 3.0;
        zm4x: Pitch := 4.0;
      else
        Pitch := 2.0;
      end;

      TotalContentH := Round(TotalLines * Pitch);

      if TotalContentH <= H then
      begin
        ScrollOffsetY := 0;
        FirstLine := 1;
        LastLine := TotalLines;
        FVTop := Round((TopLine - 1) * Pitch);
        FVHeight := Max(16, Round(LinesInWindow * Pitch));
      end
      else
      begin
        MaxScroll := TotalContentH - H;
        Progress := (TopLine - 1) / Max(1, MaxTopLine - 1);
        Progress := Max(0.0, Min(1.0, Progress));

        ScrollOffsetY := Round(Progress * MaxScroll);
        FirstLine := Max(1, Round(ScrollOffsetY / Pitch) + 1);
        LastLine := Min(TotalLines, FirstLine + Round(H / Pitch) + 2);

        FVHeight := Max(20, Round(H * (LinesInWindow / TotalLines)));
        FVHeight := Min(H, FVHeight);
        FVTop := Round(Progress * (H - FVHeight));
      end;
    end;
  end;

  // 2. Renderiza as linhas de código visíveis na área do minimapa
  Canvas.Pen.Width := 1;
  for L := FirstLine to LastLine do
  begin
    LineY := Round((L - 1) * Pitch) - ScrollOffsetY;
    if (LineY >= 0) and (LineY < H) then
    begin
      LineStr := FSynEdit.Lines[L - 1];
      DrawLineMiniature(LineStr, LineY, MaxW, Pitch);
    end;
  end;

  // 3. Renderiza o retângulo translúcido da Viewport (área visível no editor)
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
  Pitch: Double;
  TotalContentH, VHeight: Integer;
  Progress: Double;
  TargetTopLine: Integer;
begin
  if (FSynEdit = nil) or (FSynEdit.Lines = nil) then Exit;

  TotalLines := FSynEdit.Lines.Count;
  if TotalLines <= 0 then Exit;

  H := ClientHeight;
  LinesInWindow := Max(1, FSynEdit.LinesInWindow);
  MaxTopLine := Max(1, TotalLines - LinesInWindow + 1);

  case FZoom of
    zmFit:
    begin
      Pitch := H / Max(1, TotalLines);
      VHeight := Max(14, Round(LinesInWindow * Pitch));
      VHeight := Min(H, VHeight);
      Progress := (AY - (VHeight div 2)) / Max(1, H - VHeight);
      Progress := Max(0.0, Min(1.0, Progress));
      TargetTopLine := 1 + Round(Progress * (MaxTopLine - 1));
    end;

    zm1x, zm2x, zm3x, zm4x:
    begin
      case FZoom of
        zm1x: Pitch := 1.0;
        zm2x: Pitch := 2.0;
        zm3x: Pitch := 3.0;
        zm4x: Pitch := 4.0;
      else
        Pitch := 2.0;
      end;

      TotalContentH := Round(TotalLines * Pitch);

      if TotalContentH <= H then
      begin
        TargetTopLine := 1 + Round(AY / Pitch) - (LinesInWindow div 2);
      end
      else
      begin
        VHeight := Max(20, Round(H * (LinesInWindow / TotalLines)));
        VHeight := Min(H, VHeight);
        Progress := (AY - (VHeight div 2)) / Max(1, H - VHeight);
        Progress := Max(0.0, Min(1.0, Progress));
        TargetTopLine := 1 + Round(Progress * (MaxTopLine - 1));
      end;
    end;
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
  end
  else if Button = mbRight then
  begin
    UpdatePopupMenuChecks;
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

  // Ctrl + Wheel: Ajusta o Zoom instantaneamente!
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      ZoomIn
    else
      ZoomOut;
    Result := True;
    Exit;
  end;

  // Sem Ctrl: Rola o código do editor
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
