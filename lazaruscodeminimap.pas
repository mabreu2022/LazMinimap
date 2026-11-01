unit LazarusCodeMiniMap;

{$mode objfpc}{$H+}
{$warn 5024 off : no warning about unused parameters}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, ExtCtrls, Menus,
  LCLType, LCLIntf, SynEdit, SynEditTypes, SrcEditorIntf, IDEIntf;

const
  LEFT_MARGIN   = 6;
  RIGHT_MARGIN  = 6;
  HEADER_HEIGHT = 22;

type

  { TCodeMiniMapZoom: Níveis de zoom e escala do minimapa }
  TCodeMiniMapZoom = (
    zmFit,    // Ajustar todo o arquivo à altura da tela (Visão Geral Completa / Sem Zoom)
    zm1x,     // 1x Ultra Compacto (1px por linha)
    zm2x,     // 2x Normal (2px por linha - Padrão)
    zm3x,     // 3x Ampliado (3px por linha)
    zm4x,     // 4x Detalhado (4px por linha)
    zm6x,     // 6x Muito Ampliado (6px por linha - Micro-texto legível)
    zm8x      // 8x Super Ampliado (8px por linha - Leitura direta)
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
    FHeaderColor: TColor;
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
    FHoverBtn: Integer; // 0=nenhum, 1=ZoomOut(-), 2=ZoomReset(Centro), 3=ZoomIn(+)

    // Menu de contexto
    FPopupMenu: TPopupMenu;
    procedure SetSynEdit(AValue: TCustomSynEdit);
    procedure SetZoom(AValue: TCodeMiniMapZoom);
    procedure SetRenderMode(AValue: TCodeMiniMapRenderMode);
    function GetPitchForZoom(AZoom: TCodeMiniMapZoom; AAvailH, ATotalLines: Integer): Double;
    function GetZoomLabel: string;
    procedure ScrollToY(AY: Integer);
    procedure BuildPopupMenu;
    procedure UpdatePopupMenuChecks;
    procedure OnMenuZoomClick(Sender: TObject);
    procedure OnMenuZoomInClick(Sender: TObject);
    procedure OnMenuZoomOutClick(Sender: TObject);
    procedure OnMenuRenderModeClick(Sender: TObject);
    procedure OnMenuWidthClick(Sender: TObject);
    procedure OnMenuToggleVisible(Sender: TObject);
    function IsPascalKeyword(const S: string): Boolean;
    procedure DrawHeaderBar;
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
  FHoverBtn := 0;

  // Tema azul bem clarinho com efeito translúcido na Viewport (código visível por trás)
  FBackColor           := TColor($FFF5EC); // Azul bem clarinho de fundo (#ECF5FF)
  FHeaderColor         := TColor($FFE8D4); // Barra de zoom azul clara (#D4E8FF)
  FBorderColor         := TColor($DEC4A8); // Borda azul suave (#A8C4DE)
  FViewportColor       := TColor($FFE2C4); // Destaque azul claro da área visível (#C4E2FF)
  FViewportHoverColor  := TColor($FFD4A8); // Destaque da viewport ao passar o mouse (#A8D4FF)
  FViewportBorderColor := TColor($CC8038); // Borda nítida azul da viewport (#3880CC)

  // Cores de sintaxe com alto contraste sobre o fundo e sobre a barra azul da viewport
  FKeywordColor    := TColor($A83800); // Azul marinho forte (#0038A8)
  FCommentColor    := TColor($287818); // Verde (#187828)
  FStringColor     := TColor($1040A0); // Terracota escuro (#A04010)
  FDirectiveColor  := TColor($783868); // Roxo (#683878)
  FTypeColor       := TColor($786800); // Teal escuro (#006878)
  FIdentifierColor := TColor($503420); // Azul-ardósia escuro (#203450)

  Hint := 'Mini-mapa: Use [+] e [-] no topo ou Ctrl+Roda do Mouse para Zoom';

  BuildPopupMenu;
end;

destructor TCodeEditorMiniMapControl.Destroy;
begin
  FPopupMenu.Free;
  inherited Destroy;
end;

function TCodeEditorMiniMapControl.GetPitchForZoom(AZoom: TCodeMiniMapZoom; AAvailH, ATotalLines: Integer): Double;
begin
  case AZoom of
    zmFit: Result := Max(0.25, AAvailH / Max(1, ATotalLines));
    zm1x:  Result := 1.0;
    zm2x:  Result := 2.0;
    zm3x:  Result := 3.0;
    zm4x:  Result := 4.0;
    zm6x:  Result := 6.0;
    zm8x:  Result := 8.0;
  else
    Result := 2.0;
  end;
end;

function TCodeEditorMiniMapControl.GetZoomLabel: string;
begin
  case FZoom of
    zmFit: Result := 'Zoom: Fit';
    zm1x:  Result := 'Zoom: 1x';
    zm2x:  Result := 'Zoom: 2x';
    zm3x:  Result := 'Zoom: 3x';
    zm4x:  Result := 'Zoom: 4x';
    zm6x:  Result := 'Zoom: 6x';
    zm8x:  Result := 'Zoom: 8x';
  else
    Result := 'Zoom: 2x';
  end;
end;

procedure TCodeEditorMiniMapControl.BuildPopupMenu;
var
  Item, SubItem: TMenuItem;
begin
  FPopupMenu := TPopupMenu.Create(Self);

  // Ações rápidas de Zoom
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Aumentar Zoom (+)   [Ctrl + Roda p/ Cima]';
  Item.OnClick := @OnMenuZoomInClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Diminuir Zoom (-)   [Ctrl + Roda p/ Baixo]';
  Item.OnClick := @OnMenuZoomOutClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '-';
  FPopupMenu.Items.Add(Item);

  // Submenu Zoom / Escala
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Nível de Zoom / Escala';

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Ajustar Todo o Código à Tela (Fit / Sem Zoom)';
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

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Zoom 6x - Muito Ampliado (6px - Micro-Texto)';
  SubItem.Tag := Ord(zm6x);
  SubItem.OnClick := @OnMenuZoomClick;
  Item.Add(SubItem);

  SubItem := TMenuItem.Create(Item);
  SubItem.Caption := 'Zoom 8x - Super Ampliado (8px - Leitura)';
  SubItem.Tag := Ord(zm8x);
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
  if (FPopupMenu = nil) or (FPopupMenu.Items.Count < 7) then Exit;

  ZoomMenu := FPopupMenu.Items[3];
  for I := 0 to ZoomMenu.Count - 1 do
    ZoomMenu.Items[I].Checked := (ZoomMenu.Items[I].Tag = Ord(FZoom));

  RenderMenu := FPopupMenu.Items[4];
  for I := 0 to RenderMenu.Count - 1 do
    RenderMenu.Items[I].Checked := (RenderMenu.Items[I].Tag = Ord(FRenderMode));

  WidthMenu := FPopupMenu.Items[6];
  for I := 0 to WidthMenu.Count - 1 do
    WidthMenu.Items[I].Checked := (WidthMenu.Items[I].Tag = Width);
end;

procedure TCodeEditorMiniMapControl.OnMenuZoomClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    Zoom := TCodeMiniMapZoom(TMenuItem(Sender).Tag);
end;

procedure TCodeEditorMiniMapControl.OnMenuZoomInClick(Sender: TObject);
begin
  ZoomIn;
end;

procedure TCodeEditorMiniMapControl.OnMenuZoomOutClick(Sender: TObject);
begin
  ZoomOut;
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
      zmFit: ZoomDesc := 'Ajustar Todo o Código (Fit)';
      zm1x:  ZoomDesc := 'Zoom 1x (Ultra Compacto)';
      zm2x:  ZoomDesc := 'Zoom 2x (Normal)';
      zm3x:  ZoomDesc := 'Zoom 3x (Ampliado)';
      zm4x:  ZoomDesc := 'Zoom 4x (Detalhado)';
      zm6x:  ZoomDesc := 'Zoom 6x (Muito Ampliado)';
      zm8x:  ZoomDesc := 'Zoom 8x (Super Ampliado)';
    end;
    Hint := Format('Mini-mapa: %s | Botões [-]/[+] no topo ou Ctrl+Roda do Mouse', [ZoomDesc]);

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
    zm4x:  Zoom := zm6x;
    zm6x:  Zoom := zm8x;
    zm8x:  Exit;
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
    zm6x:  Zoom := zm4x;
    zm8x:  Zoom := zm6x;
  end;
end;

procedure TCodeEditorMiniMapControl.DblClick;
begin
  inherited DblClick;
  // Duplo-clique alterna rapidamente entre visão geral completa (Fit) e Normal (2x)
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

procedure TCodeEditorMiniMapControl.DrawHeaderBar;
var
  BtnMinusRect, BtnPlusRect, CenterRect: TRect;
  Lbl: string;
  TW, TH: Integer;
begin
  // Fundo da barra superior de Zoom
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FHeaderColor;
  Canvas.FillRect(Rect(1, 0, ClientWidth, HEADER_HEIGHT));

  // Linha inferior da barra superior
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FBorderColor;
  Canvas.Pen.Width := 1;
  Canvas.Line(0, HEADER_HEIGHT - 1, ClientWidth, HEADER_HEIGHT - 1);

  BtnMinusRect := Rect(3, 2, 23, HEADER_HEIGHT - 3);
  BtnPlusRect  := Rect(ClientWidth - 23, 2, ClientWidth - 3, HEADER_HEIGHT - 3);
  CenterRect   := Rect(25, 2, ClientWidth - 25, HEADER_HEIGHT - 3);

  // Botão [-] (Zoom Out)
  if FHoverBtn = 1 then
    Canvas.Brush.Color := FViewportHoverColor
  else
    Canvas.Brush.Color := FBackColor;
  Canvas.Pen.Color := FViewportBorderColor;
  Canvas.RoundRect(BtnMinusRect.Left, BtnMinusRect.Top, BtnMinusRect.Right, BtnMinusRect.Bottom, 3, 3);

  // Botão [+] (Zoom In)
  if FHoverBtn = 3 then
    Canvas.Brush.Color := FViewportHoverColor
  else
    Canvas.Brush.Color := FBackColor;
  Canvas.Pen.Color := FViewportBorderColor;
  Canvas.RoundRect(BtnPlusRect.Left, BtnPlusRect.Top, BtnPlusRect.Right, BtnPlusRect.Bottom, 3, 3);

  // Textos dos botões e indicador central de Zoom
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := TColor($683008);

  TW := Canvas.TextWidth('-');
  TH := Canvas.TextHeight('-');
  Canvas.TextOut(BtnMinusRect.Left + ((BtnMinusRect.Right - BtnMinusRect.Left - TW) div 2),
                 BtnMinusRect.Top + ((BtnMinusRect.Bottom - BtnMinusRect.Top - TH) div 2) - 1, '-');

  TW := Canvas.TextWidth('+');
  TH := Canvas.TextHeight('+');
  Canvas.TextOut(BtnPlusRect.Left + ((BtnPlusRect.Right - BtnPlusRect.Left - TW) div 2),
                 BtnPlusRect.Top + ((BtnPlusRect.Bottom - BtnPlusRect.Top - TH) div 2) - 1, '+');

  // Indicador central (ex: "Zoom: 2x")
  Canvas.Font.Size := 7;
  if FHoverBtn = 2 then
    Canvas.Font.Color := TColor($A83800)
  else
    Canvas.Font.Color := TColor($583820);
  Lbl := GetZoomLabel;
  TW := Canvas.TextWidth(Lbl);
  TH := Canvas.TextHeight(Lbl);
  Canvas.TextOut(CenterRect.Left + Max(0, (CenterRect.Right - CenterRect.Left - TW) div 2),
                 CenterRect.Top + ((CenterRect.Bottom - CenterRect.Top - TH) div 2), Lbl);
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
  CharW, BarThickness: Integer;
  UseMicroText: Boolean;
  TokenColor: TColor;

  procedure DrawTokenBar(AX1, AX2: Integer; AColor: TColor);
  var
    B: Integer;
  begin
    Canvas.Pen.Color := AColor;
    for B := 0 to BarThickness - 1 do
      Canvas.Line(AX1, LineY + B, AX2, LineY + B);
  end;

begin
  Len := Length(S);
  if Len = 0 then Exit;

  // Largura horizontal e espessura vertical proporcionais ao nível de Zoom
  if APitch < 1.8 then
  begin
    CharW := 1;
    BarThickness := 1;
  end
  else if APitch < 3.0 then
  begin
    CharW := 2;
    BarThickness := 1;
  end
  else if APitch < 5.0 then
  begin
    CharW := 3;
    BarThickness := 2;
  end
  else
  begin
    CharW := 4;
    BarThickness := 3;
  end;

  // Em zooms altos (6x e 8x) ou quando rmMicroText estiver ativo (>= 3x), renderiza micro-texto legível
  UseMicroText := ((FRenderMode = rmMicroText) and (APitch >= 3.0)) or (APitch >= 5.5);
  if UseMicroText then
  begin
    Canvas.Font.Name := 'Consolas';
    if APitch >= 7.5 then
      Canvas.Font.Size := 6
    else if APitch >= 5.5 then
      Canvas.Font.Size := 5
    else
      Canvas.Font.Size := 4;
    Canvas.Font.Style := [];
    Canvas.Brush.Style := bsClear;
  end;

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
    if UseMicroText then
    begin
      Canvas.Font.Color := FCommentColor;
      Canvas.TextOut(X1, LineY - 1, Copy(S, Indent + 1, Len - Indent));
    end
    else
      DrawTokenBar(X1, X2, FCommentColor);
    Exit;
  end;

  // Diretiva de compilador {$...}
  if (Indent + 2 <= Len) and (S[Indent + 1] = '{') and (S[Indent + 2] = '$') then
  begin
    X1 := CurX;
    X2 := Min(MaxW, X1 + (Len - Indent) * CharW);
    if UseMicroText then
    begin
      Canvas.Font.Color := FDirectiveColor;
      Canvas.TextOut(X1, LineY - 1, Copy(S, Indent + 1, Len - Indent));
    end
    else
      DrawTokenBar(X1, X2, FDirectiveColor);
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
      DrawTokenBar(CurX, Min(MaxW, CurX + 3), FStringColor);
      Inc(CurX, CharW + 2);
      Inc(I);
      Continue;
    end;

    if InString then
    begin
      DrawTokenBar(CurX, Min(MaxW, CurX + 2), FStringColor);
      Inc(CurX, CharW);
      Inc(I);
      Continue;
    end;

    if (Ch = '/') and (I < Len) and (S[I + 1] = '/') then
    begin
      // Restante da linha é comentário
      DrawTokenBar(CurX, Min(MaxW, CurX + (Len - I + 1) * CharW), FCommentColor);
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
        Canvas.TextOut(X1, LineY - 1, WordStr);
        CurX := CurX + Canvas.TextWidth(WordStr) + 2;
      end
      else
      begin
        DrawTokenBar(X1, X2, TokenColor);
        CurX := X2 + CharW;
      end;
    end
    else
    begin
      if not (Ch in [' ', #9]) then
      begin
        DrawTokenBar(CurX, Min(MaxW, CurX + CharW), FIdentifierColor);
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
  AvailH, TotalLines, LinesInWindow, MaxTopLine: Integer;
  Pitch: Double;
  TotalContentH, MaxScroll, ScrollOffsetY: Integer;
  TopLine: Integer;
  Progress: Double;
  FirstLine, LastLine, L, LineY, MaxW: Integer;
  VRect: TRect;
  LineStr: string;
begin
  // 1. Fundo principal azul bem clarinho
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBackColor;
  Canvas.FillRect(ClientRect);

  // Linha divisória esquerda
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FBorderColor;
  Canvas.Pen.Width := 1;
  Canvas.Line(0, 0, 0, ClientHeight);

  // Desenha a barra de controles de Zoom no topo ([-], Zoom, [+])
  DrawHeaderBar;

  if (FSynEdit = nil) or (FSynEdit.Lines = nil) then Exit;

  TotalLines := FSynEdit.Lines.Count;
  if TotalLines <= 0 then Exit;

  AvailH := Max(10, ClientHeight - HEADER_HEIGHT);
  LinesInWindow := Max(1, FSynEdit.LinesInWindow);
  TopLine := Max(1, FSynEdit.TopLine);
  MaxTopLine := Max(1, TotalLines - LinesInWindow + 1);
  MaxW := ClientWidth - RIGHT_MARGIN;

  Pitch := GetPitchForZoom(FZoom, AvailH, TotalLines);

  // 2. Calcula posição da Viewport e intervalo de linhas visíveis
  if FZoom = zmFit then
  begin
    ScrollOffsetY := 0;
    FirstLine := 1;
    LastLine := TotalLines;

    FVTop := HEADER_HEIGHT + Round((TopLine - 1) * Pitch);
    FVHeight := Max(14, Round(LinesInWindow * Pitch));
    FVHeight := Min(ClientHeight - FVTop, FVHeight);
  end
  else
  begin
    TotalContentH := Round(TotalLines * Pitch);

    if TotalContentH <= AvailH then
    begin
      ScrollOffsetY := 0;
      FirstLine := 1;
      LastLine := TotalLines;
      FVTop := HEADER_HEIGHT + Round((TopLine - 1) * Pitch);
      FVHeight := Max(16, Round(LinesInWindow * Pitch));
      FVHeight := Min(ClientHeight - FVTop, FVHeight);
    end
    else
    begin
      MaxScroll := TotalContentH - AvailH;
      Progress := (TopLine - 1) / Max(1, MaxTopLine - 1);
      Progress := Max(0.0, Min(1.0, Progress));

      ScrollOffsetY := Round(Progress * MaxScroll);
      FirstLine := Max(1, Round(ScrollOffsetY / Pitch) + 1);
      LastLine := Min(TotalLines, FirstLine + Round(AvailH / Pitch) + 2);

      FVHeight := Max(20, Round(AvailH * (LinesInWindow / TotalLines)));
      FVHeight := Min(AvailH, FVHeight);
      FVTop := HEADER_HEIGHT + Round(Progress * (AvailH - FVHeight));
    end;
  end;

  // 3. PRIMEIRO desenha o preenchimento azul claro da Viewport (ao fundo),
  //    para que o bloco de código fique 100% visível por cima (efeito transparente)!
  VRect := Rect(1, FVTop, ClientWidth - 1, FVTop + FVHeight);

  Canvas.Brush.Style := bsSolid;
  if FDragging or FHoveringViewport then
    Canvas.Brush.Color := FViewportHoverColor
  else
    Canvas.Brush.Color := FViewportColor;
  Canvas.FillRect(VRect);

  // Barra lateral esquerda de destaque da Viewport (3px)
  Canvas.Brush.Color := FViewportBorderColor;
  Canvas.FillRect(Rect(1, FVTop, 4, FVTop + FVHeight));

  // 4. SEGUNDO: Renderiza as linhas de código POR CIMA da barra azul da Viewport!
  Canvas.Pen.Width := 1;
  for L := FirstLine to LastLine do
  begin
    LineY := HEADER_HEIGHT + Round((L - 1) * Pitch) - ScrollOffsetY;
    if (LineY >= HEADER_HEIGHT) and (LineY < ClientHeight - 1) then
    begin
      LineStr := FSynEdit.Lines[L - 1];
      DrawLineMiniature(LineStr, LineY, MaxW, Pitch);
    end;
  end;

  // 5. TERCEIRO: Desenha APENAS o contorno (bsClear) da Viewport por cima, sem tapar o código!
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := FViewportBorderColor;
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(VRect);

  // Re-desenha o cabeçalho caso alguma linha no limite tenha tocado o topo
  DrawHeaderBar;
end;

procedure TCodeEditorMiniMapControl.ScrollToY(AY: Integer);
var
  AvailH, RelY, TotalLines, LinesInWindow, MaxTopLine: Integer;
  Pitch: Double;
  TotalContentH, VHeight: Integer;
  Progress: Double;
  TargetTopLine: Integer;
begin
  if (FSynEdit = nil) or (FSynEdit.Lines = nil) then Exit;

  TotalLines := FSynEdit.Lines.Count;
  if TotalLines <= 0 then Exit;

  AvailH := Max(10, ClientHeight - HEADER_HEIGHT);
  RelY := Max(0, AY - HEADER_HEIGHT);
  LinesInWindow := Max(1, FSynEdit.LinesInWindow);
  MaxTopLine := Max(1, TotalLines - LinesInWindow + 1);
  Pitch := GetPitchForZoom(FZoom, AvailH, TotalLines);

  if FZoom = zmFit then
  begin
    VHeight := Max(14, Round(LinesInWindow * Pitch));
    VHeight := Min(AvailH, VHeight);
    Progress := (RelY - (VHeight div 2)) / Max(1, AvailH - VHeight);
    Progress := Max(0.0, Min(1.0, Progress));
    TargetTopLine := 1 + Round(Progress * (MaxTopLine - 1));
  end
  else
  begin
    TotalContentH := Round(TotalLines * Pitch);

    if TotalContentH <= AvailH then
    begin
      TargetTopLine := 1 + Round(RelY / Pitch) - (LinesInWindow div 2);
    end
    else
    begin
      VHeight := Max(20, Round(AvailH * (LinesInWindow / TotalLines)));
      VHeight := Min(AvailH, VHeight);
      Progress := (RelY - (VHeight div 2)) / Max(1, AvailH - VHeight);
      Progress := Max(0.0, Min(1.0, Progress));
      TargetTopLine := 1 + Round(Progress * (MaxTopLine - 1));
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
    // Cliques na barra superior de Zoom ([-], Zoom: Nx, [+])
    if Y < HEADER_HEIGHT then
    begin
      if X <= 24 then
        ZoomOut
      else if X >= ClientWidth - 24 then
        ZoomIn
      else
      begin
        // Clique no centro alterna entre Fit (código todo) e 2x (Padrão)
        if FZoom = zmFit then
          Zoom := zm2x
        else
          Zoom := zmFit;
      end;
      Exit;
    end;

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
  NewHoverBtn: Integer;
begin
  inherited MouseMove(Shift, X, Y);

  if FDragging then
  begin
    ScrollToY(Y);
    Exit;
  end;

  NewHoverBtn := 0;
  if Y < HEADER_HEIGHT then
  begin
    if X <= 24 then
      NewHoverBtn := 1
    else if X >= ClientWidth - 24 then
      NewHoverBtn := 3
    else
      NewHoverBtn := 2;
  end;

  IsOverV := (Y >= HEADER_HEIGHT) and (Y >= FVTop) and (Y <= FVTop + FVHeight);
  if (IsOverV <> FHoveringViewport) or (NewHoverBtn <> FHoverBtn) then
  begin
    FHoveringViewport := IsOverV;
    FHoverBtn := NewHoverBtn;
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
  if FHoveringViewport or (FHoverBtn <> 0) then
  begin
    FHoveringViewport := False;
    FHoverBtn := 0;
    Invalidate;
  end;
end;

function TCodeEditorMiniMapControl.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  LinesToScroll: Integer;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);

  // Ctrl + Wheel (ou rolar com o mouse sobre a barra de Zoom no topo): Ajusta o Zoom instantaneamente!
  if (ssCtrl in Shift) or (MousePos.Y < HEADER_HEIGHT) then
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
