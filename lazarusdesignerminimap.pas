unit LazarusDesignerMiniMap;

{$mode objfpc}{$H+}
{$warn 5024 off : no warning about unused parameters}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, ExtCtrls, StdCtrls,
  ComCtrls, Menus, LCLType, LCLIntf, PropEdits, FormEditingIntf, IDEIntf;

const
  // Resolução de referência Full HD 1080p
  REF_SCREEN_WIDTH  = 1920;
  REF_SCREEN_HEIGHT = 1080;

type

  { TMiniMapCorner: Cantos de ancoragem no editor de formulários e modo destacado }
  TMiniMapCorner = (
    mmcBottomLeft,   // Canto Inferior Esquerdo (Padrão)
    mmcBottomRight,  // Canto Inferior Direito
    mmcTopLeft,      // Canto Superior Esquerdo
    mmcTopRight,     // Canto Superior Direito
    mmcFloating      // Destacado livremente pelo usuário
  );

  { TFormDesignerMiniMapControl: Renderiza a tela de 1080p, o Form e gerencia docking/arraste }
  TFormDesignerMiniMapControl = class(TCustomControl)
  private
    FTargetForm: TCustomForm;
    FSelectedComponent: TComponent;
    FHoveredComponent: TComponent;
    FScale: Double;
    FScreenRect: TRect;
    FFormRect: TRect;
    FHeaderHeight: Integer;
    FMargin: Integer;
    FBackColor: TColor;
    FHeaderColor: TColor;
    FBorderColor: TColor;
    FScreenColor: TColor;
    FSelectionColor: TColor;

    // Gestão de destaque (arraste livre) e ancoragem
    FCorner: TMiniMapCorner;
    FCollapsed: Boolean;
    FNormalHeight: Integer;
    FDraggingWin: Boolean;
    FDragMouseStart: TPoint;
    FDragWinStart: TPoint;
    FFloatingOffset: TPoint;

    // Menu de contexto e botões de cabeçalho
    FPopupMenu: TPopupMenu;
    procedure SetTargetForm(AValue: TCustomForm);
    procedure SetSelectedComponent(AValue: TComponent);
    procedure SetCorner(AValue: TMiniMapCorner);
    procedure SetCollapsed(AValue: Boolean);
    function GetControlBoundsInForm(ACtrl: TControl): TRect;
    function FindComponentAtMiniPos(AX, AY: Integer): TComponent;
    procedure CalculateMetrics;
    procedure DrawControlRecursive(ACtrl: TControl; AFormOrigin: TPoint; ADepth: Integer = 0);
    procedure DrawNonVisualComponents(AFormOrigin: TPoint);
    procedure BuildPopupMenu;
    procedure OnMenuCornerClick(Sender: TObject);
    procedure OnMenuCollapseClick(Sender: TObject);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property TargetForm: TCustomForm read FTargetForm write SetTargetForm;
    property SelectedComponent: TComponent read FSelectedComponent write SetSelectedComponent;
    property Corner: TMiniMapCorner read FCorner write SetCorner;
    property Collapsed: Boolean read FCollapsed write SetCollapsed;
    property FloatingOffset: TPoint read FFloatingOffset write FFloatingOffset;
  end;

  { TMiniMapFloatingWindow: Janela flutuante sem borda otimizada para o Form Designer }
  TMiniMapFloatingWindow = class(TCustomForm)
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
  end;

  { TFormDesignerMiniMapManager: Gerencia posicionamento, cantos e visibilidade no Form Designer }
  TFormDesignerMiniMapManager = class(TComponent)
  private
    FWin: TMiniMapFloatingWindow;
    FMiniMap: TFormDesignerMiniMapControl;
    FTimer: TTimer;
    FLastBounds: TRect;
    FLastSignature: Int64;
    FUpdating: Boolean;
    function ComputeSignature(AForm: TCustomForm): Int64;
    function IsFormDesignerActiveAndVisible(AForm: TCustomForm; out ADesignArea: TWinControl): Boolean;
    function FindActiveDesignedForm(out ADesignArea: TWinControl): TCustomForm;
    procedure OnTimer(Sender: TObject);
    procedure OnChangeLookupRoot;
    procedure OnSetSelection(const ASelection: TPersistentSelectionList);
    procedure OnModified(Sender: TObject);
    procedure UpdatePositionAndState;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property MiniMap: TFormDesignerMiniMapControl read FMiniMap;
  end;

procedure Register;

implementation

var
  DesignerMiniMapGlobal: TFormDesignerMiniMapManager = nil;

{ TFormDesignerMiniMapControl }

constructor TFormDesignerMiniMapControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 204;
  Height := 136;
  FNormalHeight := 136;
  FMargin := 6;
  FHeaderHeight := 20;

  // Canto padrão inicial: Inferior Esquerdo (como no Delphi)
  FCorner := mmcBottomLeft;
  FCollapsed := False;
  FFloatingOffset := Point(20, 20);

  // Cores do tema escuro moderno
  FBackColor := TColor($1E1E1E);
  FHeaderColor := TColor($2A2A2A);
  FBorderColor := TColor($3E3E3E);
  FScreenColor := TColor($121214); // Monitor 1080p
  FSelectionColor := TColor($00A2E8);

  DoubleBuffered := True;
  Cursor := crHandPoint;
  ShowHint := True;

  BuildPopupMenu;
end;

destructor TFormDesignerMiniMapControl.Destroy;
begin
  FPopupMenu.Free;
  inherited Destroy;
end;

procedure TFormDesignerMiniMapControl.BuildPopupMenu;
var
  Item: TMenuItem;
begin
  FPopupMenu := TPopupMenu.Create(Self);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Ancorar no Canto Inferior Esquerdo (Padrão)';
  Item.Tag := Ord(mmcBottomLeft);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Ancorar no Canto Inferior Direito';
  Item.Tag := Ord(mmcBottomRight);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Ancorar no Canto Superior Esquerdo';
  Item.Tag := Ord(mmcTopLeft);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Ancorar no Canto Superior Direito';
  Item.Tag := Ord(mmcTopRight);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '-';
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Destacado (Mover Livremente)';
  Item.Tag := Ord(mmcFloating);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Recolher / Expandir Mini-mapa';
  Item.OnClick := @OnMenuCollapseClick;
  FPopupMenu.Items.Add(Item);

  PopupMenu := FPopupMenu;
end;

procedure TFormDesignerMiniMapControl.OnMenuCornerClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    Corner := TMiniMapCorner(TMenuItem(Sender).Tag);
end;

procedure TFormDesignerMiniMapControl.OnMenuCollapseClick(Sender: TObject);
begin
  Collapsed := not Collapsed;
end;

procedure TFormDesignerMiniMapControl.SetTargetForm(AValue: TCustomForm);
begin
  if FTargetForm <> AValue then
  begin
    FTargetForm := AValue;
    Invalidate;
  end;
end;

procedure TFormDesignerMiniMapControl.SetSelectedComponent(AValue: TComponent);
begin
  if FSelectedComponent <> AValue then
  begin
    FSelectedComponent := AValue;
    Invalidate;
  end;
end;

procedure TFormDesignerMiniMapControl.SetCorner(AValue: TMiniMapCorner);
begin
  if FCorner <> AValue then
  begin
    FCorner := AValue;
    Invalidate;
  end;
end;

procedure TFormDesignerMiniMapControl.SetCollapsed(AValue: Boolean);
var
  ParentForm: TCustomForm;
begin
  if FCollapsed <> AValue then
  begin
    FCollapsed := AValue;
    ParentForm := GetParentForm(Self);
    if ParentForm <> nil then
    begin
      if FCollapsed then
      begin
        Height := FHeaderHeight + 2;
        ParentForm.Height := FHeaderHeight + 2;
      end
      else
      begin
        Height := FNormalHeight;
        ParentForm.Height := FNormalHeight;
      end;
    end;
    Invalidate;
  end;
end;

function TFormDesignerMiniMapControl.GetControlBoundsInForm(ACtrl: TControl): TRect;
var
  ParentCtrl: TWinControl;
  L, T: Integer;
  LoopGuard: Integer;
begin
  if (ACtrl = nil) or (FTargetForm = nil) then
    Exit(Rect(0, 0, 0, 0));

  L := ACtrl.Left;
  T := ACtrl.Top;
  ParentCtrl := ACtrl.Parent;
  LoopGuard := 0;
  while (ParentCtrl <> nil) and (ParentCtrl <> FTargetForm) and (LoopGuard < 20) do
  begin
    Inc(LoopGuard);
    Inc(L, ParentCtrl.Left);
    Inc(T, ParentCtrl.Top);
    ParentCtrl := ParentCtrl.Parent;
  end;
  Result := Bounds(L, T, ACtrl.Width, ACtrl.Height);
end;

procedure TFormDesignerMiniMapControl.CalculateMetrics;
var
  AvailW, AvailH: Integer;
  FormW, FormH: Integer;
  FormL, FormT: Integer;
  FW, FH: Integer;
begin
  AvailW := ClientWidth - (2 * FMargin);
  AvailH := ClientHeight - FHeaderHeight - (2 * FMargin);

  // Escala exata comparada a uma tela de 1080p (1920 x 1080)
  FScale := Min(AvailW / REF_SCREEN_WIDTH, AvailH / REF_SCREEN_HEIGHT);

  FScreenRect.Left := FMargin + ((AvailW - Round(REF_SCREEN_WIDTH * FScale)) div 2);
  FScreenRect.Top := FHeaderHeight + FMargin + ((AvailH - Round(REF_SCREEN_HEIGHT * FScale)) div 2);
  FScreenRect.Right := FScreenRect.Left + Round(REF_SCREEN_WIDTH * FScale);
  FScreenRect.Bottom := FScreenRect.Top + Round(REF_SCREEN_HEIGHT * FScale);

  if FTargetForm = nil then
  begin
    FFormRect := Rect(0, 0, 0, 0);
    Exit;
  end;

  FormW := Max(10, FTargetForm.Width);
  FormH := Max(10, FTargetForm.Height);
  FW := Max(4, Round(FormW * FScale));
  FH := Max(4, Round(FormH * FScale));

  // Posição do Form na tela de 1080p:
  // Encostado no canto superior esquerdo (zero espaço vazio na esquerda!)
  FormL := FScreenRect.Left + 2;
  FormT := FScreenRect.Top + 2;

  FFormRect := Rect(FormL, FormT, FormL + FW, FormT + FH);
end;

procedure TFormDesignerMiniMapControl.DrawControlRecursive(ACtrl: TControl; AFormOrigin: TPoint; ADepth: Integer);
var
  I: Integer;
  RInForm: TRect;
  ML, MT, MW, MH: Integer;
  CRect: TRect;
  IsSel, IsHov: Boolean;
  ClassNm: string;
begin
  if (ACtrl = nil) or not ACtrl.Visible or (ADepth > 10) then Exit;

  RInForm := GetControlBoundsInForm(ACtrl);
  ML := AFormOrigin.X + Round(RInForm.Left * FScale);
  MT := AFormOrigin.Y + Round(RInForm.Top * FScale);
  MW := Max(2, Round(RInForm.Right * FScale) - Round(RInForm.Left * FScale));
  MH := Max(2, Round(RInForm.Bottom * FScale) - Round(RInForm.Top * FScale));
  CRect := Rect(ML, MT, ML + MW, MT + MH);

  IsSel := (GlobalDesignHook <> nil) and GlobalDesignHook.IsSelected(ACtrl);
  IsHov := (ACtrl = FHoveredComponent);

  ClassNm := ACtrl.ClassName;

  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;

  if (ACtrl is TCustomPanel) or (Pos('Panel', ClassNm) > 0) or (Pos('GroupBox', ClassNm) > 0) then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TColor($2A2B30);
    Canvas.Pen.Color := TColor($42444C);
    Canvas.Rectangle(CRect);
  end
  else if (ACtrl is TCustomButton) or (Pos('Button', ClassNm) > 0) then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TColor($3A4452);
    Canvas.Pen.Color := TColor($58657A);
    Canvas.RoundRect(CRect.Left, CRect.Top, CRect.Right, CRect.Bottom, 2, 2);
  end
  else if (ACtrl is TCustomEdit) or (Pos('Edit', ClassNm) > 0) or (Pos('Memo', ClassNm) > 0) then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TColor($18191B);
    Canvas.Pen.Color := TColor($484B52);
    Canvas.Rectangle(CRect);
  end
  else if (ACtrl is TCustomLabel) or (Pos('Label', ClassNm) > 0) then
  begin
    Canvas.Pen.Color := TColor($9AA0A6);
    Canvas.Line(CRect.Left, CRect.Top + (MH div 2), Min(CRect.Right, CRect.Left + Max(3, MW - 1)), CRect.Top + (MH div 2));
  end
  else if (Pos('Grid', ClassNm) > 0) or (Pos('List', ClassNm) > 0) or (Pos('Tree', ClassNm) > 0) then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TColor($202226);
    Canvas.Pen.Color := TColor($3D414A);
    Canvas.Rectangle(CRect);
  end
  else
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TColor($25282E);
    Canvas.Pen.Color := TColor($444852);
    Canvas.Rectangle(CRect);
  end;

  if IsSel then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := FSelectionColor;
    Canvas.Pen.Width := 2;
    Canvas.Rectangle(CRect);
  end
  else if IsHov then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := clYellow;
    Canvas.Pen.Width := 1;
    Canvas.Rectangle(CRect);
  end;

  if ACtrl is TWinControl then
  begin
    for I := 0 to TWinControl(ACtrl).ControlCount - 1 do
      DrawControlRecursive(TWinControl(ACtrl).Controls[I], AFormOrigin, ADepth + 1);
  end;
end;

procedure TFormDesignerMiniMapControl.DrawNonVisualComponents(AFormOrigin: TPoint);
var
  I, X, Y: Integer;
  Comp: TComponent;
  MX, MY: Integer;
  CRect: TRect;
  IsSel: Boolean;
begin
  if FTargetForm = nil then Exit;

  for I := 0 to FTargetForm.ComponentCount - 1 do
  begin
    Comp := FTargetForm.Components[I];
    if Comp is TControl then Continue;

    GetComponentLeftTopOrDesignInfo(Comp, X, Y);
    if (X >= 0) and (Y >= 0) then
    begin
      MX := AFormOrigin.X + Round(X * FScale);
      MY := AFormOrigin.Y + Round(Y * FScale);
      CRect := Rect(MX, MY, MX + 6, MY + 6);

      IsSel := (GlobalDesignHook <> nil) and GlobalDesignHook.IsSelected(Comp);

      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TColor($754515);
      Canvas.Pen.Color := TColor($C07525);
      Canvas.Pen.Width := 1;
      Canvas.Rectangle(CRect);

      if IsSel then
      begin
        Canvas.Brush.Style := bsClear;
        Canvas.Pen.Color := FSelectionColor;
        Canvas.Pen.Width := 2;
        Canvas.Rectangle(CRect);
      end;
    end;
  end;
end;

procedure TFormDesignerMiniMapControl.Paint;
var
  I: Integer;
  HeaderStr, ResStr, CornerTag: string;
  PctW, PctH: Double;
  CenterX, CenterY: Integer;
begin
  // Fundo externo da janela do Mini-mapa
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBackColor;
  Canvas.Pen.Color := FBorderColor;
  Canvas.Pen.Width := 1;
  Canvas.RoundRect(0, 0, ClientWidth, ClientHeight, 4, 4);

  // Barra de cabeçalho
  Canvas.Brush.Color := FHeaderColor;
  Canvas.FillRect(Rect(1, 1, ClientWidth - 1, FHeaderHeight));
  Canvas.Pen.Color := FBorderColor;
  Canvas.Line(1, FHeaderHeight, ClientWidth - 1, FHeaderHeight);

  // Tag do canto atual
  case FCorner of
    mmcBottomLeft:  CornerTag := '[↙]';
    mmcBottomRight: CornerTag := '[↘]';
    mmcTopLeft:     CornerTag := '[↖]';
    mmcTopRight:    CornerTag := '[↗]';
    mmcFloating:    CornerTag := '[⚓]';
  end;

  // Botão de recolher/expandir no canto direito da barra de título
  Canvas.Font.Size := 7;
  Canvas.Font.Color := TColor($AAAAAA);
  Canvas.Brush.Style := bsClear;
  if FCollapsed then
    Canvas.TextOut(ClientWidth - 16, 3, '+')
  else
    Canvas.TextOut(ClientWidth - 16, 3, '-');

  // Ícone de ancoragem
  Canvas.TextOut(ClientWidth - 36, 3, CornerTag);

  // Título e dimensões do formulário
  if FTargetForm <> nil then
  begin
    PctW := (FTargetForm.Width / REF_SCREEN_WIDTH) * 100.0;
    PctH := (FTargetForm.Height / REF_SCREEN_HEIGHT) * 100.0;
    HeaderStr := Format('%s [%dx%d] (%d%%x%d%%)', [FTargetForm.Name, FTargetForm.Width, FTargetForm.Height, Round(PctW), Round(PctH)]);
  end
  else
    HeaderStr := 'Form Designer (1080p)';

  Canvas.TextOut(6, 4, HeaderStr);

  // Se estiver recolhido, não desenha o corpo
  if FCollapsed then Exit;

  CalculateMetrics;

  // 1. Desenha a Tela de 1080p (Monitor Full HD)
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FScreenColor;
  Canvas.Pen.Color := TColor($3A3C42);
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(FScreenRect);

  // Linhas guia de centro de tela
  CenterX := FScreenRect.Left + ((FScreenRect.Right - FScreenRect.Left) div 2);
  CenterY := FScreenRect.Top + ((FScreenRect.Bottom - FScreenRect.Top) div 2);
  Canvas.Pen.Color := TColor($202226);
  Canvas.Line(CenterX, FScreenRect.Top + 1, CenterX, FScreenRect.Bottom - 1);
  Canvas.Line(FScreenRect.Left + 1, CenterY, FScreenRect.Right - 1, CenterY);

  // Legenda 1080p
  Canvas.Font.Size := 6;
  Canvas.Font.Color := TColor($555A66);
  ResStr := '1080p';
  Canvas.TextOut(FScreenRect.Right - Canvas.TextWidth(ResStr) - 3, FScreenRect.Bottom - Canvas.TextHeight(ResStr) - 1, ResStr);

  if FTargetForm = nil then Exit;

  // 2. Desenha o Formulário proporcional na tela de 1080p
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor($2E3036);
  Canvas.Pen.Color := TColor($585C66);
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(FFormRect);

  // Barra de título do formulário
  if (FFormRect.Bottom - FFormRect.Top) > 6 then
  begin
    Canvas.Brush.Color := TColor($3E424C);
    Canvas.FillRect(Rect(FFormRect.Left + 1, FFormRect.Top + 1, FFormRect.Right - 1, FFormRect.Top + 3));
  end;

  // 3. Desenha controles do formulário
  for I := 0 to FTargetForm.ControlCount - 1 do
    DrawControlRecursive(FTargetForm.Controls[I], Point(FFormRect.Left, FFormRect.Top));

  // 4. Desenha componentes não-visuais
  DrawNonVisualComponents(Point(FFormRect.Left, FFormRect.Top));
end;

function TFormDesignerMiniMapControl.FindComponentAtMiniPos(AX, AY: Integer): TComponent;
var
  I, X, Y: Integer;
  Comp: TComponent;
  R: TRect;
  BestMatch: TControl;
  SmallestArea: Integer;
  Area: Integer;
  FormX, FormY: Integer;

  procedure CheckCtrlRecursive(ACtrl: TControl; ADepth: Integer = 0);
  var
    J: Integer;
    CR: TRect;
  begin
    if (ACtrl = nil) or not ACtrl.Visible or (ADepth > 10) then Exit;
    CR := GetControlBoundsInForm(ACtrl);
    if PtInRect(CR, Point(FormX, FormY)) then
    begin
      Area := (CR.Right - CR.Left) * (CR.Bottom - CR.Top);
      if Area < SmallestArea then
      begin
        SmallestArea := Area;
        BestMatch := ACtrl;
      end;
    end;
    if ACtrl is TWinControl then
    begin
      for J := 0 to TWinControl(ACtrl).ControlCount - 1 do
        CheckCtrlRecursive(TWinControl(ACtrl).Controls[J], ADepth + 1);
    end;
  end;

begin
  Result := nil;
  if (FTargetForm = nil) or (FScale <= 0) then Exit;

  FormX := Round((AX - FFormRect.Left) / FScale);
  FormY := Round((AY - FFormRect.Top) / FScale);

  for I := 0 to FTargetForm.ComponentCount - 1 do
  begin
    Comp := FTargetForm.Components[I];
    if Comp is TControl then Continue;
    GetComponentLeftTopOrDesignInfo(Comp, X, Y);
    if (X >= 0) and (Y >= 0) then
    begin
      R := Bounds(X, Y, 24, 24);
      if PtInRect(R, Point(FormX, FormY)) then
        Exit(Comp);
    end;
  end;

  BestMatch := nil;
  SmallestArea := MaxInt;

  for I := 0 to FTargetForm.ControlCount - 1 do
    CheckCtrlRecursive(FTargetForm.Controls[I]);

  if BestMatch <> nil then
    Result := BestMatch
  else if PtInRect(FFormRect, Point(AX, AY)) then
    Result := FTargetForm;
end;

procedure TFormDesignerMiniMapControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  TargetComp: TComponent;
  ParentWin: TCustomForm;
begin
  inherited MouseDown(Button, Shift, X, Y);

  // Clique na barra de cabeçalho
  if Y <= FHeaderHeight then
  begin
    // Clique no botão de recolher '-' / '+'
    if X >= ClientWidth - 20 then
    begin
      Collapsed := not Collapsed;
      Exit;
    end;

    // Clique no ícone de canto: cicla entre os 4 cantos
    if (X >= ClientWidth - 40) and (X < ClientWidth - 20) then
    begin
      case FCorner of
        mmcBottomLeft:  Corner := mmcBottomRight;
        mmcBottomRight: Corner := mmcTopRight;
        mmcTopRight:    Corner := mmcTopLeft;
        mmcTopLeft:     Corner := mmcBottomLeft;
        mmcFloating:    Corner := mmcBottomLeft;
      end;
      Exit;
    end;

    // Inicia o arraste da janela (para destacar e mover livremente)
    if Button = mbLeft then
    begin
      ParentWin := GetParentForm(Self);
      if ParentWin <> nil then
      begin
        FDraggingWin := True;
        MouseCapture := True;
        FDragMouseStart := ClientToScreen(Point(X, Y));
        FDragWinStart := Point(ParentWin.Left, ParentWin.Top);
      end;
      Exit;
    end;
  end;

  // Clique no corpo do mini-mapa: seleção de componentes
  if (Button = mbLeft) and (FTargetForm <> nil) and not FCollapsed then
  begin
    TargetComp := FindComponentAtMiniPos(X, Y);
    if (TargetComp <> nil) and (GlobalDesignHook <> nil) then
    begin
      GlobalDesignHook.SelectOnlyThis(TargetComp);
      FSelectedComponent := TargetComp;
      Invalidate;
    end;
  end;
end;

procedure TFormDesignerMiniMapControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  CurScreen: TPoint;
  ParentWin: TCustomForm;
  NewLeft, NewTop: Integer;
  HoverComp: TComponent;
begin
  inherited MouseMove(Shift, X, Y);

  // Se estiver arrastando a janela pela barra de título (modo destacável)
  if FDraggingWin then
  begin
    ParentWin := GetParentForm(Self);
    if ParentWin <> nil then
    begin
      CurScreen := ClientToScreen(Point(X, Y));
      NewLeft := FDragWinStart.X + (CurScreen.X - FDragMouseStart.X);
      NewTop := FDragWinStart.Y + (CurScreen.Y - FDragMouseStart.Y);
      ParentWin.SetBounds(NewLeft, NewTop, ParentWin.Width, ParentWin.Height);
      FCorner := mmcFloating; // Torna-se destacado e flutuante
    end;
    Exit;
  end;

  if (FTargetForm <> nil) and not FCollapsed then
  begin
    HoverComp := FindComponentAtMiniPos(X, Y);
    if HoverComp <> FHoveredComponent then
    begin
      FHoveredComponent := HoverComp;
      if FHoveredComponent <> nil then
        Hint := Format('%s: %s', [FHoveredComponent.Name, FHoveredComponent.ClassName])
      else
        Hint := '';
      Invalidate;
    end;
  end;
end;

procedure TFormDesignerMiniMapControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDraggingWin then
  begin
    FDraggingWin := False;
    MouseCapture := False;
  end;
end;

procedure TFormDesignerMiniMapControl.MouseLeave;
begin
  inherited MouseLeave;
  if FHoveredComponent <> nil then
  begin
    FHoveredComponent := nil;
    Invalidate;
  end;
end;

{ TMiniMapFloatingWindow }

constructor TMiniMapFloatingWindow.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Caption := '';
  BorderStyle := bsNone;
  ShowInTaskBar := stNever;
  KeyPreview := False;
  Width := 204;
  Height := 136;
end;

procedure TMiniMapFloatingWindow.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.Style := Params.Style or WS_POPUP;
  {$IFDEF WINDOWS}
  Params.ExStyle := Params.ExStyle or WS_EX_TOOLWINDOW;
  Params.ExStyle := Params.ExStyle or DWORD($08000000); // WS_EX_NOACTIVATE: não rouba o foco do editor
  {$ENDIF}
end;

{ TFormDesignerMiniMapManager }

constructor TFormDesignerMiniMapManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FWin := TMiniMapFloatingWindow.CreateNew(nil);

  FMiniMap := TFormDesignerMiniMapControl.Create(FWin);
  FMiniMap.Parent := FWin;
  FMiniMap.Align := alClient;

  FLastBounds := Rect(0, 0, 0, 0);
  FLastSignature := -1;

  if GlobalDesignHook <> nil then
  begin
    GlobalDesignHook.AddHandlerChangeLookupRoot(@OnChangeLookupRoot);
    GlobalDesignHook.AddHandlerSetSelection(@OnSetSelection);
    GlobalDesignHook.AddHandlerModified(@OnModified);
  end;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 35;
  FTimer.OnTimer := @OnTimer;
  FTimer.Enabled := True;
end;

destructor TFormDesignerMiniMapManager.Destroy;
begin
  FTimer.Free;

  if GlobalDesignHook <> nil then
  begin
    GlobalDesignHook.RemoveHandlerChangeLookupRoot(@OnChangeLookupRoot);
    GlobalDesignHook.RemoveHandlerSetSelection(@OnSetSelection);
    GlobalDesignHook.RemoveHandlerModified(@OnModified);
  end;

  FMiniMap.Free;
  FWin.Free;

  inherited Destroy;
end;

function TFormDesignerMiniMapManager.IsFormDesignerActiveAndVisible(AForm: TCustomForm; out ADesignArea: TWinControl): Boolean;
var
  ParentCtrl: TControl;
  TabSh: TTabSheet;
  Pgc: TPageControl;
begin
  Result := False;
  ADesignArea := nil;
  if (AForm = nil) or not AForm.HandleAllocated then Exit;

  {$IFDEF WINDOWS}
  if not LCLIntf.IsWindowVisible(AForm.Handle) then
    Exit(False);
  {$ENDIF}

  ADesignArea := AForm;

  ParentCtrl := AForm.Parent;
  while ParentCtrl <> nil do
  begin
    if not ParentCtrl.Visible then
      Exit(False);

    if ParentCtrl is TTabSheet then
    begin
      TabSh := TTabSheet(ParentCtrl);
      Pgc := TabSh.PageControl;
      if (Pgc <> nil) and (Pgc.ActivePage <> TabSh) then
        Exit(False); // Usuário está no editor de código!

      ADesignArea := TabSh;
    end
    else if (ADesignArea = AForm) and (ParentCtrl is TWinControl) then
    begin
      ADesignArea := TWinControl(ParentCtrl);
    end;

    ParentCtrl := ParentCtrl.Parent;
  end;

  Result := True;
end;

function TFormDesignerMiniMapManager.FindActiveDesignedForm(out ADesignArea: TWinControl): TCustomForm;
var
  I: Integer;
  F: TCustomForm;
begin
  Result := nil;
  ADesignArea := nil;

  if (GlobalDesignHook <> nil) and (GlobalDesignHook.LookupRoot is TCustomForm) then
  begin
    F := TCustomForm(GlobalDesignHook.LookupRoot);
    if (csDesigning in F.ComponentState) and IsFormDesignerActiveAndVisible(F, ADesignArea) then
      Exit(F);
  end;

  for I := 0 to Screen.CustomFormCount - 1 do
  begin
    F := Screen.CustomForms[I];
    if (F <> nil) and (F <> FWin) and (csDesigning in F.ComponentState) then
    begin
      if IsFormDesignerActiveAndVisible(F, ADesignArea) then
        Exit(F);
    end;
  end;
end;

function TFormDesignerMiniMapManager.ComputeSignature(AForm: TCustomForm): Int64;
begin
  Result := 19;
  if AForm <> nil then
  begin
    Result := (Result * 31 + AForm.Left) mod 1000000007;
    Result := (Result * 31 + AForm.Top) mod 1000000007;
    Result := (Result * 31 + AForm.Width) mod 1000000007;
    Result := (Result * 31 + AForm.Height) mod 1000000007;
    Result := (Result * 31 + AForm.ControlCount) mod 1000000007;
    Result := (Result * 31 + AForm.ComponentCount) mod 1000000007;
  end;
end;

procedure TFormDesignerMiniMapManager.OnChangeLookupRoot;
begin
  UpdatePositionAndState;
end;

procedure TFormDesignerMiniMapManager.OnSetSelection(const ASelection: TPersistentSelectionList);
begin
  if (ASelection <> nil) and (ASelection.Count > 0) and (ASelection[0] is TComponent) then
    FMiniMap.SelectedComponent := TComponent(ASelection[0])
  else
    FMiniMap.SelectedComponent := nil;
  FMiniMap.Invalidate;
end;

procedure TFormDesignerMiniMapManager.OnModified(Sender: TObject);
begin
  FMiniMap.Invalidate;
end;

procedure TFormDesignerMiniMapManager.OnTimer(Sender: TObject);
begin
  UpdatePositionAndState;
end;

procedure TFormDesignerMiniMapManager.UpdatePositionAndState;
var
  DesignedForm: TCustomForm;
  DesignArea: TWinControl;
  ParentFm: TCustomForm;
  TargetBounds: TRect;
  Sig: Int64;
  Margin: Integer;
  P_TL, P_BR: TPoint;
begin
  if FUpdating then Exit;
  FUpdating := True;
  try
    DesignedForm := FindActiveDesignedForm(DesignArea);

    // Se não estiver no Form Designer ou se o formulário não estiver visível: ESCONDE!
    if (DesignedForm = nil) or (DesignArea = nil) or not DesignArea.HandleAllocated or not DesignArea.Visible then
    begin
      if FWin.Visible then FWin.Hide;
      Exit;
    end;

    ParentFm := GetParentForm(DesignArea);
    if (ParentFm <> nil) and ((ParentFm.WindowState = wsMinimized) or not ParentFm.Visible) then
    begin
      if FWin.Visible then FWin.Hide;
      Exit;
    end;

    if FMiniMap.TargetForm <> DesignedForm then
      FMiniMap.TargetForm := DesignedForm;

    // Atualiza assinatura e redesenho imediatamente
    Sig := ComputeSignature(DesignedForm);
    if Sig <> FLastSignature then
    begin
      FLastSignature := Sig;
      FMiniMap.Invalidate;
    end;

    // Se o usuário estiver no meio do arraste/redimensionamento ativo do mouse, não altera bounds da janela
    {$IFDEF WINDOWS}
    if (GetKeyState(VK_LBUTTON) < 0) and (FMiniMap.Corner <> mmcFloating) then
      Exit;
    {$ENDIF}

    Margin := 4; // Rente ao canto para melhor aproveitamento de espaço
    P_TL := DesignArea.ClientToScreen(Point(0, 0));
    P_BR := DesignArea.ClientToScreen(Point(DesignArea.ClientWidth, DesignArea.ClientHeight));

    // Posicionamento dinâmico baseado no canto configurado (ou destacado)
    case FMiniMap.Corner of
      mmcBottomLeft:
      begin
        TargetBounds.Left := P_TL.X + Margin;
        TargetBounds.Bottom := P_BR.Y - Margin;
        TargetBounds.Right := TargetBounds.Left + FWin.Width;
        TargetBounds.Top := TargetBounds.Bottom - FWin.Height;
      end;

      mmcBottomRight:
      begin
        TargetBounds.Right := P_BR.X - Margin;
        TargetBounds.Bottom := P_BR.Y - Margin;
        TargetBounds.Left := TargetBounds.Right - FWin.Width;
        TargetBounds.Top := TargetBounds.Bottom - FWin.Height;
      end;

      mmcTopLeft:
      begin
        TargetBounds.Left := P_TL.X + Margin;
        TargetBounds.Top := P_TL.Y + Margin;
        TargetBounds.Right := TargetBounds.Left + FWin.Width;
        TargetBounds.Bottom := TargetBounds.Top + FWin.Height;
      end;

      mmcTopRight:
      begin
        TargetBounds.Right := P_BR.X - Margin;
        TargetBounds.Top := P_TL.Y + Margin;
        TargetBounds.Left := TargetBounds.Right - FWin.Width;
        TargetBounds.Bottom := TargetBounds.Top + FWin.Height;
      end;

      mmcFloating:
      begin
        // Modo destacado: o usuário moveu a janela livremente
        TargetBounds := Rect(FWin.Left, FWin.Top, FWin.Left + FWin.Width, FWin.Top + FWin.Height);
      end;
    end;

    if FMiniMap.Corner <> mmcFloating then
    begin
      if (FLastBounds.Left <> TargetBounds.Left) or (FLastBounds.Top <> TargetBounds.Top) or
         (FLastBounds.Right <> TargetBounds.Right) or (FLastBounds.Bottom <> TargetBounds.Bottom) then
      begin
        FLastBounds := TargetBounds;
        FWin.SetBounds(TargetBounds.Left, TargetBounds.Top, FWin.Width, FWin.Height);
      end;
    end;

    if not FWin.Visible then
      FWin.Show;
  finally
    FUpdating := False;
  end;
end;

procedure Register;
begin
  if DesignerMiniMapGlobal = nil then
    DesignerMiniMapGlobal := TFormDesignerMiniMapManager.Create(nil);
end;

initialization

finalization
  FreeAndNil(DesignerMiniMapGlobal);

end.
