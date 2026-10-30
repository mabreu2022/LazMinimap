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

  { TMiniMapCorner: Cantos de ancoragem no editor de formulários e modo livre }
  TMiniMapCorner = (
    mmcBottomLeft,   // Canto Inferior Esquerdo (Padrão Delphi)
    mmcBottomRight,  // Canto Inferior Direito
    mmcTopLeft,      // Canto Superior Esquerdo
    mmcTopRight,     // Canto Superior Direito
    mmcFloating      // Mover livremente
  );

  { TFormDesignerMiniMapControl: Controle nativo de miniatura do formulário no Form Designer }
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

    // Gestão de cantos, recolhimento e arraste livre
    FCorner: TMiniMapCorner;
    FCollapsed: Boolean;
    FNormalHeight: Integer;
    FDragging: Boolean;
    FDragMouseStart: TPoint;
    FDragCtrlStart: TPoint;

    // Arraste interativo do formulário dentro da tela 1080p
    FDraggingForm: Boolean;
    FFormDragStartMouse: TPoint;
    FFormDragStartLeft: Integer;
    FFormDragStartTop: Integer;
    FHasMovedForm: Boolean;
    FSnappedCenterH: Boolean;
    FSnappedCenterV: Boolean;

    // Menu de contexto
    FPopupMenu: TPopupMenu;
    procedure SetTargetForm(AValue: TCustomForm);
    procedure SetSelectedComponent(AValue: TComponent);
    procedure SetCorner(AValue: TMiniMapCorner);
    procedure SetCollapsed(AValue: Boolean);
    function GetControlBoundsInForm(ACtrl: TControl): TRect;
    function FindComponentAtMiniPos(AX, AY: Integer): TComponent;
    function GetFormVirtualScreenLeft: Integer;
    function GetFormVirtualScreenTop: Integer;
    procedure NotifyFormChanged;
    procedure CalculateMetrics;
    procedure DrawControlRecursive(ACtrl: TControl; AFormOrigin: TPoint; ADepth: Integer = 0);
    procedure DrawNonVisualComponents(AFormOrigin: TPoint);
    procedure BuildPopupMenu;
    procedure OnMenuCornerClick(Sender: TObject);
    procedure OnMenuCollapseClick(Sender: TObject);
    procedure OnMenuCenterFormClick(Sender: TObject);
    procedure OnMenuTopLeftFormClick(Sender: TObject);
    procedure OnMenuSetScreenCenterClick(Sender: TObject);
    procedure OnMenuSetDesignedClick(Sender: TObject);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure UpdateDockPosition;
    property TargetForm: TCustomForm read FTargetForm write SetTargetForm;
    property SelectedComponent: TComponent read FSelectedComponent write SetSelectedComponent;
    property Corner: TMiniMapCorner read FCorner write SetCorner;
    property Collapsed: Boolean read FCollapsed write SetCollapsed;
    property DraggingForm: Boolean read FDraggingForm;
  end;

  { TFormDesignerMiniMapManager: Gerencia posicionamento e visibilidade sem criar janelas popup }
  TFormDesignerMiniMapManager = class(TComponent)
  private
    FMiniMap: TFormDesignerMiniMapControl;
    FTimer: TTimer;
    FLastSignature: Int64;
    FUpdating: Boolean;
    function ComputeSignature(AForm: TCustomForm): Int64;
    function IsFormDesignerActiveAndVisible(AForm: TCustomForm; out ADesignArea: TWinControl): Boolean;
    function FindActiveDesignedForm(out ADesignArea: TWinControl): TCustomForm;
    procedure OnTimer(Sender: TObject);
    procedure OnChangeLookupRoot;
    procedure OnSetSelection(const ASelection: TPersistentSelectionList);
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

  // Cores do tema escuro moderno
  FBackColor := TColor($1E1E1E);
  FHeaderColor := TColor($2A2A2A);
  FBorderColor := TColor($3E3E3E);
  FScreenColor := TColor($121214); // Monitor 1080p
  FSelectionColor := TColor($00A2E8);

  DoubleBuffered := True;
  Cursor := crDefault;
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
  Item.Caption := 'Mover Livremente (Destacar Mini-mapa)';
  Item.Tag := Ord(mmcFloating);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Recolher / Expandir Mini-mapa';
  Item.OnClick := @OnMenuCollapseClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '-';
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Posicionar Formulário no Centro da Tela';
  Item.OnClick := @OnMenuCenterFormClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Posicionar no Canto Superior Esquerdo (0, 0)';
  Item.OnClick := @OnMenuTopLeftFormClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Modo de Execução: poScreenCenter (Centralizar ao Rodar)';
  Item.OnClick := @OnMenuSetScreenCenterClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Modo de Execução: poDesigned (Usar Coordenadas do Mini-mapa)';
  Item.OnClick := @OnMenuSetDesignedClick;
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

procedure TFormDesignerMiniMapControl.OnMenuCenterFormClick(Sender: TObject);
var
  CL, CT: Integer;
begin
  if FTargetForm = nil then Exit;
  CL := Max(0, (REF_SCREEN_WIDTH - FTargetForm.Width) div 2);
  CT := Max(0, (REF_SCREEN_HEIGHT - FTargetForm.Height) div 2);
  SetComponentLeftTopOrDesignInfo(FTargetForm, CL, CT);
  FTargetForm.Position := poDesigned;
  NotifyFormChanged;
  Invalidate;
end;

procedure TFormDesignerMiniMapControl.OnMenuTopLeftFormClick(Sender: TObject);
begin
  if FTargetForm = nil then Exit;
  SetComponentLeftTopOrDesignInfo(FTargetForm, 0, 0);
  FTargetForm.Position := poDesigned;
  NotifyFormChanged;
  Invalidate;
end;

procedure TFormDesignerMiniMapControl.OnMenuSetScreenCenterClick(Sender: TObject);
begin
  if FTargetForm = nil then Exit;
  FTargetForm.Position := poScreenCenter;
  NotifyFormChanged;
  Invalidate;
end;

procedure TFormDesignerMiniMapControl.OnMenuSetDesignedClick(Sender: TObject);
begin
  if FTargetForm = nil then Exit;
  FTargetForm.Position := poDesigned;
  NotifyFormChanged;
  Invalidate;
end;

procedure TFormDesignerMiniMapControl.NotifyFormChanged;
begin
  if (FTargetForm <> nil) and (GlobalDesignHook <> nil) then
  begin
    GlobalDesignHook.Modified(FTargetForm, 'Position');
    GlobalDesignHook.Modified(FTargetForm, 'Left');
    GlobalDesignHook.Modified(FTargetForm, 'Top');
    GlobalDesignHook.RefreshPropertyValues;
  end;
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
    UpdateDockPosition;
    Invalidate;
  end;
end;

procedure TFormDesignerMiniMapControl.SetCollapsed(AValue: Boolean);
begin
  if FCollapsed <> AValue then
  begin
    FCollapsed := AValue;
    if FCollapsed then
      Height := FHeaderHeight + 2
    else
      Height := FNormalHeight;
    UpdateDockPosition;
    Invalidate;
  end;
end;

procedure TFormDesignerMiniMapControl.UpdateDockPosition;
var
  ParentW, ParentH: Integer;
  P: TWinControl;
  Margin: Integer;
  NewL, NewT: Integer;
begin
  P := Parent;
  if P = nil then Exit;
  ParentW := P.ClientWidth;
  ParentH := P.ClientHeight;
  Margin := 6;

  case FCorner of
    mmcBottomLeft:
    begin
      NewL := Margin;
      NewT := ParentH - Height - Margin;
    end;

    mmcBottomRight:
    begin
      NewL := ParentW - Width - Margin;
      NewT := ParentH - Height - Margin;
    end;

    mmcTopLeft:
    begin
      NewL := Margin;
      NewT := Margin;
    end;

    mmcTopRight:
    begin
      NewL := ParentW - Width - Margin;
      NewT := Margin;
    end;

    mmcFloating:
    begin
      Anchors := [akLeft, akTop];
      Exit;
    end;
  end;

  Anchors := [akLeft, akTop];
  if (Left <> NewL) or (Top <> NewT) then
    SetBounds(NewL, NewT, Width, Height);
  BringToFront;
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

function TFormDesignerMiniMapControl.GetFormVirtualScreenLeft: Integer;
var
  MaxL: Integer;
  FL, FT: Integer;
begin
  if FTargetForm = nil then Exit(0);
  if FTargetForm.Position in [poScreenCenter, poDesktopCenter, poMainFormCenter, poOwnerFormCenter] then
    Result := (REF_SCREEN_WIDTH - FTargetForm.Width) div 2
  else
  begin
    GetComponentLeftTopOrDesignInfo(FTargetForm, FL, FT);
    Result := FL;
  end;

  MaxL := Max(0, REF_SCREEN_WIDTH - FTargetForm.Width);
  Result := Max(0, Min(MaxL, Result));
end;

function TFormDesignerMiniMapControl.GetFormVirtualScreenTop: Integer;
var
  MaxT: Integer;
  FL, FT: Integer;
begin
  if FTargetForm = nil then Exit(0);
  if FTargetForm.Position in [poScreenCenter, poDesktopCenter, poMainFormCenter, poOwnerFormCenter] then
    Result := (REF_SCREEN_HEIGHT - FTargetForm.Height) div 2
  else
  begin
    GetComponentLeftTopOrDesignInfo(FTargetForm, FL, FT);
    Result := FT;
  end;

  MaxT := Max(0, REF_SCREEN_HEIGHT - FTargetForm.Height);
  Result := Max(0, Min(MaxT, Result));
end;

procedure TFormDesignerMiniMapControl.CalculateMetrics;
var
  AvailW, AvailH: Integer;
  FormW, FormH: Integer;
  FormL, FormT: Integer;
  FW, FH: Integer;
  ScreenFormLeft, ScreenFormTop: Integer;
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

  // Posição proporcional do Form na tela de 1080p
  ScreenFormLeft := GetFormVirtualScreenLeft;
  ScreenFormTop := GetFormVirtualScreenTop;

  FormL := FScreenRect.Left + Round(ScreenFormLeft * FScale);
  FormT := FScreenRect.Top + Round(ScreenFormTop * FScale);

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
  if FDraggingForm and (FTargetForm <> nil) then
  begin
    if FSnappedCenterH and FSnappedCenterV then
      HeaderStr := Format('%s: [Centro 1080p]', [FTargetForm.Name])
    else
      HeaderStr := Format('%s: X=%d, Y=%d', [FTargetForm.Name, FTargetForm.Left, FTargetForm.Top]);
  end
  else if FTargetForm <> nil then
  begin
    if FTargetForm.Position in [poScreenCenter, poDesktopCenter] then
      HeaderStr := Format('%s [%dx%d] (Centro)', [FTargetForm.Name, FTargetForm.Width, FTargetForm.Height])
    else
      HeaderStr := Format('%s [%dx%d] (%d,%d)', [FTargetForm.Name, FTargetForm.Width, FTargetForm.Height, FTargetForm.Left, FTargetForm.Top]);
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

  if FDraggingForm and FSnappedCenterH then
  begin
    Canvas.Pen.Color := TColor($00D7FF); // Guia de centro vertical destacada
    Canvas.Line(CenterX, FScreenRect.Top + 1, CenterX, FScreenRect.Bottom - 1);
  end
  else
  begin
    Canvas.Pen.Color := TColor($202226);
    Canvas.Line(CenterX, FScreenRect.Top + 1, CenterX, FScreenRect.Bottom - 1);
  end;

  if FDraggingForm and FSnappedCenterV then
  begin
    Canvas.Pen.Color := TColor($00D7FF); // Guia de centro horizontal destacada
    Canvas.Line(FScreenRect.Left + 1, CenterY, FScreenRect.Right - 1, CenterY);
  end
  else
  begin
    Canvas.Pen.Color := TColor($202226);
    Canvas.Line(FScreenRect.Left + 1, CenterY, FScreenRect.Right - 1, CenterY);
  end;

  // Legenda 1080p
  Canvas.Font.Size := 6;
  Canvas.Font.Color := TColor($555A66);
  ResStr := '1080p';
  Canvas.TextOut(FScreenRect.Right - Canvas.TextWidth(ResStr) - 3, FScreenRect.Bottom - Canvas.TextHeight(ResStr) - 1, ResStr);

  // Se estiver arrastando, mostra coordenadas no canto inferior esquerdo do monitor
  if FDraggingForm and (FTargetForm <> nil) then
  begin
    Canvas.Font.Color := TColor($00D7FF);
    Canvas.TextOut(FScreenRect.Left + 3, FScreenRect.Bottom - Canvas.TextHeight('X') - 1, Format('(%d, %d)', [FTargetForm.Left, FTargetForm.Top]));
  end;

  if FTargetForm = nil then Exit;

  // 2. Desenha o Formulário proporcional na tela de 1080p
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor($2E3036);
  if FDraggingForm then
  begin
    Canvas.Pen.Color := TColor($00D7FF); // Realce ciano durante o arraste
    Canvas.Pen.Width := 2;
  end
  else
  begin
    Canvas.Pen.Color := TColor($585C66);
    Canvas.Pen.Width := 1;
  end;
  Canvas.Rectangle(FFormRect);
  Canvas.Pen.Width := 1;

  // Barra de título do formulário
  if (FFormRect.Bottom - FFormRect.Top) > 6 then
  begin
    if FDraggingForm then
      Canvas.Brush.Color := TColor($007ACC)
    else
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
begin
  inherited MouseDown(Button, Shift, X, Y);

  CalculateMetrics;

  // 1. Clique na barra de cabeçalho
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

    // Inicia o arraste livre do controle do mini-mapa
    if Button = mbLeft then
    begin
      FDragging := True;
      MouseCapture := True;
      FDragMouseStart := ClientToScreen(Point(X, Y));
      FDragCtrlStart := Point(Left, Top);
      Exit;
    end;
  end;

  // 2. Clique no corpo do mini-mapa (tela 1080p e formulário)
  if (Button = mbLeft) and (FTargetForm <> nil) and not FCollapsed then
  begin
    // Se clicou sobre o desenho do formulário: inicia o arraste do Form!
    if PtInRect(FFormRect, Point(X, Y)) then
    begin
      FDraggingForm := True;
      MouseCapture := True;
      FFormDragStartMouse := Point(X, Y);
      FFormDragStartLeft := GetFormVirtualScreenLeft;
      FFormDragStartTop := GetFormVirtualScreenTop;
      FHasMovedForm := False;
      FSnappedCenterH := False;
      FSnappedCenterV := False;
      Invalidate;
      Exit;
    end
    else if PtInRect(FScreenRect, Point(X, Y)) then
    begin
      // Clicou na tela 1080p fora do form: seleciona o formulário no Object Inspector
      if GlobalDesignHook <> nil then
      begin
        GlobalDesignHook.SelectOnlyThis(FTargetForm);
        FSelectedComponent := FTargetForm;
        Invalidate;
      end;
      Exit;
    end;
  end;
end;

procedure TFormDesignerMiniMapControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  CurScreen: TPoint;
  NewLeft, NewTop: Integer;
  HoverComp: TComponent;
  DeltaX, DeltaY: Integer;
  ScreenDeltaX, ScreenDeltaY: Integer;
  MaxL, MaxT: Integer;
  CenterL, CenterT: Integer;
  SnapThreshold: Integer;
begin
  inherited MouseMove(Shift, X, Y);

  // 1. Se estiver arrastando o controle do mini-mapa pela barra de título
  if FDragging then
  begin
    CurScreen := ClientToScreen(Point(X, Y));
    NewLeft := FDragCtrlStart.X + (CurScreen.X - FDragMouseStart.X);
    NewTop := FDragCtrlStart.Y + (CurScreen.Y - FDragMouseStart.Y);
    if Parent <> nil then
    begin
      NewLeft := Max(0, Min(Parent.ClientWidth - Width, NewLeft));
      NewTop := Max(0, Min(Parent.ClientHeight - Height, NewTop));
    end;
    FCorner := mmcFloating;
    Anchors := [akLeft, akTop];
    SetBounds(NewLeft, NewTop, Width, Height);
    BringToFront;
    Exit;
  end;

  // 2. Se estiver arrastando o formulário dentro da tela 1080p!
  if FDraggingForm and (FTargetForm <> nil) and (FScale > 0) then
  begin
    DeltaX := X - FFormDragStartMouse.X;
    DeltaY := Y - FFormDragStartMouse.Y;

    if not FHasMovedForm and ((Abs(DeltaX) > 2) or (Abs(DeltaY) > 2)) then
      FHasMovedForm := True;

    if FHasMovedForm then
    begin
      ScreenDeltaX := Round(DeltaX / FScale);
      ScreenDeltaY := Round(DeltaY / FScale);

      NewLeft := FFormDragStartLeft + ScreenDeltaX;
      NewTop := FFormDragStartTop + ScreenDeltaY;

      MaxL := Max(0, REF_SCREEN_WIDTH - FTargetForm.Width);
      MaxT := Max(0, REF_SCREEN_HEIGHT - FTargetForm.Height);

      SnapThreshold := Max(15, Round(10 / FScale));

      CenterL := MaxL div 2;
      CenterT := MaxT div 2;

      // Snap magnético aos cantos e bordas da tela
      if Abs(NewLeft) < SnapThreshold then NewLeft := 0;
      if Abs(NewTop) < SnapThreshold then NewTop := 0;
      if Abs(NewLeft - MaxL) < SnapThreshold then NewLeft := MaxL;
      if Abs(NewTop - MaxT) < SnapThreshold then NewTop := MaxT;

      // Snap magnético ao centro da tela
      FSnappedCenterH := (Abs(NewLeft - CenterL) < SnapThreshold);
      if FSnappedCenterH then NewLeft := CenterL;

      FSnappedCenterV := (Abs(NewTop - CenterT) < SnapThreshold);
      if FSnappedCenterV then NewTop := CenterT;

      // Limita dentro da tela 1080p
      NewLeft := Max(0, Min(MaxL, NewLeft));
      NewTop := Max(0, Min(MaxT, NewTop));

      SetComponentLeftTopOrDesignInfo(FTargetForm, NewLeft, NewTop);
      FTargetForm.Position := poDesigned;
      Invalidate;
    end;
    Exit;
  end;

  // 3. Hover, Cursores e Dicas
  if (FTargetForm <> nil) and not FCollapsed then
  begin
    CalculateMetrics;

    if PtInRect(FFormRect, Point(X, Y)) then
      Cursor := crSizeAll
    else
      Cursor := crDefault;

    HoverComp := FindComponentAtMiniPos(X, Y);
    if HoverComp <> FHoveredComponent then
    begin
      FHoveredComponent := HoverComp;
      if FHoveredComponent <> nil then
        Hint := Format('%s: %s', [FHoveredComponent.Name, FHoveredComponent.ClassName])
      else if PtInRect(FFormRect, Point(X, Y)) then
        Hint := Format('%s [Left: %d, Top: %d] - Arraste para mover na tela 1080p', [FTargetForm.Name, GetFormVirtualScreenLeft, GetFormVirtualScreenTop])
      else
        Hint := '';
      Invalidate;
    end;
  end;
end;

procedure TFormDesignerMiniMapControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  TargetComp: TComponent;
begin
  inherited MouseUp(Button, Shift, X, Y);

  if FDragging then
  begin
    FDragging := False;
    MouseCapture := False;
  end;

  if FDraggingForm then
  begin
    FDraggingForm := False;
    MouseCapture := False;
    FSnappedCenterH := False;
    FSnappedCenterV := False;

    if FHasMovedForm and (FTargetForm <> nil) then
    begin
      // Aplica e notifica o Object Inspector / Designer do Lazarus
      NotifyFormChanged;
      Invalidate;
    end
    else
    begin
      // Foi apenas um clique (sem arrastar): seleciona o componente no IDE
      TargetComp := FindComponentAtMiniPos(X, Y);
      if (TargetComp <> nil) and (GlobalDesignHook <> nil) then
      begin
        GlobalDesignHook.SelectOnlyThis(TargetComp);
        FSelectedComponent := TargetComp;
        Invalidate;
      end;
    end;
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
  if not FDraggingForm then
    Cursor := crDefault;
end;

{ TFormDesignerMiniMapManager }

constructor TFormDesignerMiniMapManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FMiniMap := TFormDesignerMiniMapControl.Create(Self);
  FMiniMap.Visible := False;

  FLastSignature := -1;

  if GlobalDesignHook <> nil then
  begin
    GlobalDesignHook.AddHandlerChangeLookupRoot(@OnChangeLookupRoot);
    GlobalDesignHook.AddHandlerSetSelection(@OnSetSelection);
  end;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 50; // 20 FPS para verificação de mudanças
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
  end;

  FMiniMap.Free;

  inherited Destroy;
end;

function TFormDesignerMiniMapManager.IsFormDesignerActiveAndVisible(AForm: TCustomForm; out ADesignArea: TWinControl): Boolean;
var
  ParentCtrl: TControl;
  Candidate: TWinControl;
  LoopGuard: Integer;
begin
  Result := False;
  ADesignArea := nil;
  if (AForm = nil) or not AForm.HandleAllocated then Exit;

  {$IFDEF WINDOWS}
  if not LCLIntf.IsWindowVisible(AForm.Handle) then
    Exit(False);
  {$ENDIF}

  // Se AForm não tem parent (janela flutuante separada), não acopla
  if AForm.Parent = nil then
    Exit(False);

  Candidate := nil;
  ParentCtrl := AForm.Parent;
  LoopGuard := 0;
  while (ParentCtrl <> nil) and (LoopGuard < 30) do
  begin
    Inc(LoopGuard);
    // Se algum container pai estiver oculto (ex: o usuário trocou para a aba Código), o minimap deve sumir
    if not ParentCtrl.Visible then
      Exit(False);

    // Procura por TCustomPage (TTabSheet, TAnchorDockPage, etc.) ou classe de aba/página
    if (ParentCtrl is TCustomPage) or (Pos('Page', ParentCtrl.ClassName) > 0) or (Pos('TabSheet', ParentCtrl.ClassName) > 0) then
    begin
      Candidate := TWinControl(ParentCtrl);
      Break;
    end;

    // Se encontrar qualquer container que não seja AForm, guarda como candidato
    if (Candidate = nil) and (ParentCtrl is TWinControl) and (ParentCtrl <> AForm) then
      Candidate := TWinControl(ParentCtrl);

    ParentCtrl := ParentCtrl.Parent;
  end;

  if Candidate <> nil then
    ADesignArea := Candidate
  else
    ADesignArea := AForm.Parent;

  // REGRA DE OURO: O Mini-mapa NUNCA, SOB NENHUMA HIPÓTESE, PODE TER AForm COMO PAI!
  // Se for AForm, causa recursão e Stack Overflow ao esticar o form!
  if (ADesignArea = nil) or (ADesignArea = AForm) then
  begin
    ADesignArea := nil;
    Exit(False);
  end;

  Result := ADesignArea.HandleAllocated and ADesignArea.Visible;
end;

function TFormDesignerMiniMapManager.FindActiveDesignedForm(out ADesignArea: TWinControl): TCustomForm;
var
  I: Integer;
  F: TCustomForm;
  Root: TPersistent;
begin
  Result := nil;
  ADesignArea := nil;

  if GlobalDesignHook <> nil then
  begin
    Root := GlobalDesignHook.LookupRoot;
    if Root is TCustomForm then
    begin
      F := TCustomForm(Root);
      if (csDesigning in F.ComponentState) and IsFormDesignerActiveAndVisible(F, ADesignArea) then
        Exit(F);
    end
    else if (Root is TControl) and (TControl(Root).Parent <> nil) then
    begin
      F := GetParentForm(TControl(Root));
      if (F <> nil) and (csDesigning in F.ComponentState) and IsFormDesignerActiveAndVisible(F, ADesignArea) then
        Exit(F);
    end;
  end;

  for I := 0 to Screen.CustomFormCount - 1 do
  begin
    F := Screen.CustomForms[I];
    if (F <> nil) and (csDesigning in F.ComponentState) then
    begin
      if IsFormDesignerActiveAndVisible(F, ADesignArea) then
        Exit(F);
    end;
  end;
end;

function TFormDesignerMiniMapManager.ComputeSignature(AForm: TCustomForm): Int64;
var
  FL, FT: Integer;
begin
  Result := 19;
  if AForm <> nil then
  begin
    GetComponentLeftTopOrDesignInfo(AForm, FL, FT);
    Result := (Result * 31 + FL) mod 1000000007;
    Result := (Result * 31 + FT) mod 1000000007;
    Result := (Result * 31 + AForm.Width) mod 1000000007;
    Result := (Result * 31 + AForm.Height) mod 1000000007;
    Result := (Result * 31 + Ord(AForm.Position)) mod 1000000007;
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

procedure TFormDesignerMiniMapManager.OnTimer(Sender: TObject);
begin
  if (FMiniMap <> nil) and FMiniMap.DraggingForm then Exit;
  UpdatePositionAndState;
end;

procedure TFormDesignerMiniMapManager.UpdatePositionAndState;
var
  DesignedForm: TCustomForm;
  DesignArea: TWinControl;
  Sig: Int64;
begin
  if FUpdating then Exit;
  FUpdating := True;
  try
    DesignedForm := FindActiveDesignedForm(DesignArea);

    // Se não estiver no Form Designer ou o formulário não estiver ativo/visível: oculta
    if (DesignedForm = nil) or (DesignArea = nil) or not DesignArea.HandleAllocated or not DesignArea.Visible then
    begin
      if FMiniMap.Visible then
        FMiniMap.Visible := False;
      Exit;
    end;

    // Acopla como filho da página do designer (nunca de AForm!)
    if FMiniMap.Parent <> DesignArea then
    begin
      FMiniMap.Parent := DesignArea;
      FMiniMap.BringToFront;
      FMiniMap.UpdateDockPosition;
    end
    else if FMiniMap.Corner <> mmcFloating then
      FMiniMap.UpdateDockPosition;

    if FMiniMap.TargetForm <> DesignedForm then
      FMiniMap.TargetForm := DesignedForm;

    if not FMiniMap.Visible then
    begin
      FMiniMap.Visible := True;
      FMiniMap.BringToFront;
    end;

    // Redesenha apenas quando as propriedades do Form mudarem
    Sig := ComputeSignature(DesignedForm);
    if Sig <> FLastSignature then
    begin
      FLastSignature := Sig;
      FMiniMap.Invalidate;
    end;
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
