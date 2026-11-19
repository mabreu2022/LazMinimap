unit LazarusDesignerMiniMap;

{$mode objfpc}{$H+}
{$warn 5024 off : no warning about unused parameters}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, ExtCtrls, StdCtrls,
  ComCtrls, Menus, LCLType, LCLIntf, PropEdits, FormEditingIntf, IDEIntf,
  SrcEditorIntf, SynEdit, LazIDEIntf, Laz2_XMLCfg, MenuIntf;

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

  { TFormDesignerMiniMapControl: Native miniature control for Form Designer }
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
    FTextColor: TColor;
    FHeaderColor: TColor;
    FBorderColor: TColor;
    FScreenColor: TColor;
    FSelectionColor: TColor;
    FLastSchemeBg: TColor;
    FLastSchemeFg: TColor;

    // Corner docking, collapsing, and free dragging
    FCorner: TMiniMapCorner;
    FCollapsed: Boolean;
    FNormalHeight: Integer;
    FFloatingLeft: Integer;
    FFloatingTop: Integer;
    FDragging: Boolean;
    FDragMouseStart: TPoint;
    FDragCtrlStart: TPoint;

    // Interactive dragging of form inside 1080p screen
    FDraggingForm: Boolean;
    FFormDragStartMouse: TPoint;
    FFormDragStartLeft: Integer;
    FFormDragStartTop: Integer;
    FHasMovedForm: Boolean;
    FSnappedCenterH: Boolean;
    FSnappedCenterV: Boolean;
    FVirtualFormLeft: Integer;
    FVirtualFormTop: Integer;
    FVirtualFormValid: Boolean;

    // Context menu
    FPopupMenu: TPopupMenu;
    procedure UpdateColors;
    procedure SetTargetForm(AValue: TCustomForm);
    procedure SetSelectedComponent(AValue: TComponent);
    procedure SetCorner(AValue: TMiniMapCorner);
    procedure SetCollapsed(AValue: Boolean);
    function GetControlBoundsInForm(ACtrl: TControl): TRect;
    function FindComponentAtMiniPos(AX, AY: Integer): TComponent;
    procedure SyncVirtualFormPosition;
    procedure CommitFormPosition;
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
    procedure OnMenuToggleVisible(Sender: TObject);
    procedure LoadSettings;
    procedure SaveSettings;
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
    property FloatingLeft: Integer read FFloatingLeft write FFloatingLeft;
    property FloatingTop: Integer read FFloatingTop write FFloatingTop;
    property DraggingForm: Boolean read FDraggingForm;
    property BackColor: TColor read FBackColor;
    property TextColor: TColor read FTextColor;
  end;

  { TFormDesignerMiniMapManager: Gerencia posicionamento e visibilidade sem criar janelas popup }
  TFormDesignerMiniMapManager = class(TComponent)
  private
    FMiniMap: TFormDesignerMiniMapControl;
    FTimer: TTimer;
    FLastSignature: Int64;
    FUpdating: Boolean;
    FEnabled: Boolean;
    procedure SetMiniMapEnabled(AValue: Boolean);
    procedure LoadSettings;
    procedure SaveSettings;
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
    procedure ToggleMiniMap(Sender: TObject);
    property MiniMap: TFormDesignerMiniMapControl read FMiniMap;
    property MiniMapEnabled: Boolean read FEnabled write SetMiniMapEnabled;
  end;

procedure Register;

implementation

var
  DesignerMiniMapGlobal: TFormDesignerMiniMapManager = nil;

function GetMiniMapConfigFile: string;
var
  Dir: string;
begin
  if LazarusIDE <> nil then
    Dir := LazarusIDE.GetPrimaryConfigPath
  else
    Dir := GetAppConfigDir(False);
  if Dir = '' then
    Dir := '.';
  Result := IncludeTrailingPathDelimiter(Dir) + 'lazminimap.xml';
end;

function ResolveColor(AColor, ADefault: TColor): TColor;
begin
  if (AColor = clNone) or (AColor = clDefault) then
    Result := ColorToRGB(ADefault)
  else
    Result := ColorToRGB(AColor);
end;

function IsDarkColor(AColor: TColor): Boolean;
var
  C: LongWord;
  R, G, B: Integer;
begin
  C := ColorToRGB(AColor);
  R := C and $FF;
  G := (C shr 8) and $FF;
  B := (C shr 16) and $FF;
  Result := ((R * 77 + G * 150 + B * 29) shr 8) < 128;
end;

function BlendColors(Col1, Col2: TColor; Factor: Double): TColor;
var
  C1, C2: LongWord;
  R1, G1, B1, R2, G2, B2: Integer;
  R, G, B: Integer;
begin
  C1 := ColorToRGB(Col1);
  C2 := ColorToRGB(Col2);
  Factor := Max(0.0, Min(1.0, Factor));
  R1 := C1 and $FF;
  G1 := (C1 shr 8) and $FF;
  B1 := (C1 shr 16) and $FF;
  R2 := C2 and $FF;
  G2 := (C2 shr 8) and $FF;
  B2 := (C2 shr 16) and $FF;
  R := Round(R1 * (1.0 - Factor) + R2 * Factor);
  G := Round(G1 * (1.0 - Factor) + G2 * Factor);
  B := Round(B1 * (1.0 - Factor) + B2 * Factor);
  Result := RGB(Byte(R), Byte(G), Byte(B));
end;

{ TFormDesignerMiniMapControl }

procedure TFormDesignerMiniMapControl.UpdateColors;
var
  CurEditor: TSourceEditorInterface;
  SynEdit: TCustomSynEdit;
  SchemeBg, SchemeFg: TColor;
  IsDark: Boolean;
begin
  SchemeBg := clNone;
  SchemeFg := clNone;

  if (SourceEditorManagerIntf <> nil) and (SourceEditorManagerIntf.ActiveEditor <> nil) then
  begin
    CurEditor := SourceEditorManagerIntf.ActiveEditor;
    if (CurEditor.EditorControl <> nil) and (CurEditor.EditorControl is TCustomSynEdit) then
    begin
      SynEdit := TCustomSynEdit(CurEditor.EditorControl);
      SchemeBg := ResolveColor(SynEdit.Color, clWhite);
      SchemeFg := ResolveColor(SynEdit.Font.Color, clBlack);
    end;
  end;

  if SchemeBg = clNone then
  begin
    SchemeBg := ResolveColor(clWindow, clWhite);
    SchemeFg := ResolveColor(clWindowText, clBlack);
  end;

  if (SchemeBg = FLastSchemeBg) and (SchemeFg = FLastSchemeFg) then
    Exit;

  FLastSchemeBg := SchemeBg;
  FLastSchemeFg := SchemeFg;

  IsDark := IsDarkColor(SchemeBg);
  FTextColor := SchemeFg;

  if FTextColor = SchemeBg then
  begin
    if IsDark then
      FTextColor := clWhite
    else
      FTextColor := clBlack;
  end;

  if IsDark then
  begin
    FBackColor      := BlendColors(SchemeBg, clWhite, 0.05);
    FHeaderColor    := BlendColors(SchemeBg, clWhite, 0.12);
    FBorderColor    := BlendColors(SchemeBg, clWhite, 0.22);
    FScreenColor    := BlendColors(SchemeBg, clBlack, 0.25);
    FSelectionColor := TColor($00A2E8);
  end
  else
  begin
    FBackColor      := BlendColors(SchemeBg, clBlack, 0.03);
    FHeaderColor    := BlendColors(SchemeBg, clBlack, 0.08);
    FBorderColor    := BlendColors(SchemeBg, clBlack, 0.20);
    FScreenColor    := BlendColors(SchemeBg, clBlack, 0.04);
    FSelectionColor := TColor($D05000);
  end;
end;

constructor TFormDesignerMiniMapControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 204;
  Height := 136;
  FNormalHeight := 136;
  FMargin := 6;
  FHeaderHeight := 20;

  // Default corner: Bottom-Left
  FCorner := mmcBottomLeft;
  FCollapsed := False;
  FFloatingLeft := -1;
  FFloatingTop := -1;

  FLastSchemeBg := clNone;
  FLastSchemeFg := clNone;

  // Synchronize colors with current Lazarus color scheme
  UpdateColors;

  DoubleBuffered := True;
  Cursor := crDefault;
  ShowHint := True;

  BuildPopupMenu;
  LoadSettings;

  if FCollapsed then
    Height := FHeaderHeight + 2;
end;

destructor TFormDesignerMiniMapControl.Destroy;
begin
  FPopupMenu.Free;
  inherited Destroy;
end;

procedure TFormDesignerMiniMapControl.LoadSettings;
var
  Cfg: TXMLConfig;
  FileName: string;
begin
  try
    FileName := GetMiniMapConfigFile;
    if not FileExists(FileName) then Exit;
    Cfg := TXMLConfig.Create(FileName);
    try
      FCorner := TMiniMapCorner(Cfg.GetValue('DesignerMiniMap/Corner/Value', Ord(mmcBottomLeft)));
      FCollapsed := Cfg.GetValue('DesignerMiniMap/Collapsed/Value', False);
      FFloatingLeft := Cfg.GetValue('DesignerMiniMap/FloatingLeft/Value', -1);
      FFloatingTop := Cfg.GetValue('DesignerMiniMap/FloatingTop/Value', -1);
    finally
      Cfg.Free;
    end;
  except
  end;
end;

procedure TFormDesignerMiniMapControl.SaveSettings;
var
  Cfg: TXMLConfig;
  FileName: string;
begin
  try
    FileName := GetMiniMapConfigFile;
    ForceDirectories(ExtractFilePath(FileName));
    Cfg := TXMLConfig.Create(FileName);
    try
      Cfg.SetValue('DesignerMiniMap/Corner/Value', Ord(FCorner));
      Cfg.SetValue('DesignerMiniMap/Collapsed/Value', FCollapsed);
      if (FFloatingLeft >= 0) and (FFloatingTop >= 0) then
      begin
        Cfg.SetValue('DesignerMiniMap/FloatingLeft/Value', FFloatingLeft);
        Cfg.SetValue('DesignerMiniMap/FloatingTop/Value', FFloatingTop);
      end;
      Cfg.Flush;
    finally
      Cfg.Free;
    end;
  except
  end;
end;

procedure TFormDesignerMiniMapControl.BuildPopupMenu;
var
  Item: TMenuItem;
begin
  FPopupMenu := TPopupMenu.Create(Self);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Dock to Bottom-Left (Default)';
  Item.Tag := Ord(mmcBottomLeft);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Dock to Bottom-Right';
  Item.Tag := Ord(mmcBottomRight);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Dock to Top-Left';
  Item.Tag := Ord(mmcTopLeft);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Dock to Top-Right';
  Item.Tag := Ord(mmcTopRight);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '-';
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Float Freely (Undock Minimap)';
  Item.Tag := Ord(mmcFloating);
  Item.OnClick := @OnMenuCornerClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Collapse / Expand Minimap';
  Item.OnClick := @OnMenuCollapseClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '-';
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Position Form in Center of Screen';
  Item.OnClick := @OnMenuCenterFormClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Position at Top-Left (0, 0)';
  Item.OnClick := @OnMenuTopLeftFormClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Startup Position: poScreenCenter (Center on Run)';
  Item.OnClick := @OnMenuSetScreenCenterClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Startup Position: poDesigned (Use Minimap Coordinates)';
  Item.OnClick := @OnMenuSetDesignedClick;
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '-';
  FPopupMenu.Items.Add(Item);

  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Hide Designer Minimap';
  Item.OnClick := @OnMenuToggleVisible;
  FPopupMenu.Items.Add(Item);

  PopupMenu := FPopupMenu;
end;

procedure TFormDesignerMiniMapControl.OnMenuToggleVisible(Sender: TObject);
begin
  if DesignerMiniMapGlobal <> nil then
    DesignerMiniMapGlobal.MiniMapEnabled := False
  else
    Visible := False;
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
begin
  if FTargetForm = nil then Exit;
  FVirtualFormLeft := Max(0, (REF_SCREEN_WIDTH - FTargetForm.Width) div 2);
  FVirtualFormTop := Max(0, (REF_SCREEN_HEIGHT - FTargetForm.Height) div 2);
  CommitFormPosition;
  Invalidate;
end;

procedure TFormDesignerMiniMapControl.OnMenuTopLeftFormClick(Sender: TObject);
begin
  if FTargetForm = nil then Exit;
  FVirtualFormLeft := 0;
  FVirtualFormTop := 0;
  CommitFormPosition;
  Invalidate;
end;

procedure TFormDesignerMiniMapControl.OnMenuSetScreenCenterClick(Sender: TObject);
begin
  if FTargetForm = nil then Exit;
  FTargetForm.Position := poScreenCenter;
  FVirtualFormLeft := Max(0, (REF_SCREEN_WIDTH - FTargetForm.Width) div 2);
  FVirtualFormTop := Max(0, (REF_SCREEN_HEIGHT - FTargetForm.Height) div 2);
  NotifyFormChanged;
  Invalidate;
end;

procedure TFormDesignerMiniMapControl.OnMenuSetDesignedClick(Sender: TObject);
begin
  if FTargetForm = nil then Exit;
  FTargetForm.Position := poDesigned;
  CommitFormPosition;
  Invalidate;
end;

procedure TFormDesignerMiniMapControl.CommitFormPosition;
begin
  if FTargetForm = nil then Exit;

  // 1. Armazena a informação de design no componente (DesignInfo)
  FTargetForm.DesignInfo := LeftTopToDesignInfo(FVirtualFormLeft, FVirtualFormTop);
  SetDesignInfoLeft(FTargetForm, FVirtualFormLeft);
  SetDesignInfoTop(FTargetForm, FVirtualFormTop);

  // 2. Define as propriedades Left, Top e Position via RTTI
  TrySetOrdProp(FTargetForm, 'Left', FVirtualFormLeft);
  TrySetOrdProp(FTargetForm, 'Top', FVirtualFormTop);
  if FSnappedCenterH and FSnappedCenterV then
    FTargetForm.Position := poScreenCenter
  else
    FTargetForm.Position := poDesigned;

  // 3. Notifica o Lazarus IDE Designer e Object Inspector
  NotifyFormChanged;
end;

procedure TFormDesignerMiniMapControl.SyncVirtualFormPosition;
var
  FL, FT: Integer;
begin
  if FTargetForm = nil then
  begin
    FVirtualFormLeft := 0;
    FVirtualFormTop := 0;
    FVirtualFormValid := False;
    Exit;
  end;

  if FTargetForm.Position in [poScreenCenter, poDesktopCenter, poMainFormCenter, poOwnerFormCenter] then
  begin
    FVirtualFormLeft := Max(0, (REF_SCREEN_WIDTH - FTargetForm.Width) div 2);
    FVirtualFormTop := Max(0, (REF_SCREEN_HEIGHT - FTargetForm.Height) div 2);
  end
  else
  begin
    FL := LeftFromDesignInfo(FTargetForm.DesignInfo);
    FT := TopFromDesignInfo(FTargetForm.DesignInfo);
    if (FL <= 0) and (FT <= 0) and (FTargetForm.Left > 0) then
    begin
      FL := FTargetForm.Left;
      FT := FTargetForm.Top;
    end;
    FVirtualFormLeft := Max(0, Min(Max(0, REF_SCREEN_WIDTH - FTargetForm.Width), FL));
    FVirtualFormTop := Max(0, Min(Max(0, REF_SCREEN_HEIGHT - FTargetForm.Height), FT));
  end;
  FVirtualFormValid := True;
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
    FVirtualFormValid := False;
    SyncVirtualFormPosition;
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
    SaveSettings;
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
    SaveSettings;
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
      Anchors := [akLeft, akBottom];
    end;

    mmcBottomRight:
    begin
      NewL := ParentW - Width - Margin;
      NewT := ParentH - Height - Margin;
      Anchors := [akRight, akBottom];
    end;

    mmcTopLeft:
    begin
      NewL := Margin;
      NewT := Margin;
      Anchors := [akLeft, akTop];
    end;

    mmcTopRight:
    begin
      NewL := ParentW - Width - Margin;
      NewT := Margin;
      Anchors := [akRight, akTop];
    end;

    mmcFloating:
    begin
      if (FFloatingLeft >= 0) and (FFloatingTop >= 0) then
      begin
        NewL := Min(FFloatingLeft, ParentW - Width);
        NewT := Min(FFloatingTop, ParentH - Height);
        NewL := Max(0, NewL);
        NewT := Max(0, NewT);
        if (Left <> NewL) or (Top <> NewT) then
          SetBounds(NewL, NewT, Width, Height);
      end;
      Anchors := [akLeft, akTop];
      Exit;
    end;
  end;

  if (Left <> NewL) or (Top <> NewT) then
    SetBounds(NewL, NewT, Width, Height);
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
  MaxL, MaxT: Integer;
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

  if not FVirtualFormValid and not FDraggingForm then
    SyncVirtualFormPosition;

  FormW := Max(10, FTargetForm.Width);
  FormH := Max(10, FTargetForm.Height);
  FW := Max(4, Round(FormW * FScale));
  FH := Max(4, Round(FormH * FScale));

  MaxL := Max(0, REF_SCREEN_WIDTH - FormW);
  MaxT := Max(0, REF_SCREEN_HEIGHT - FormH);
  FVirtualFormLeft := Max(0, Min(MaxL, FVirtualFormLeft));
  FVirtualFormTop := Max(0, Min(MaxT, FVirtualFormTop));

  // Posição proporcional do Form na tela de 1080p
  FormL := FScreenRect.Left + Round(FVirtualFormLeft * FScale);
  FormT := FScreenRect.Top + Round(FVirtualFormTop * FScale);

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
  if (ACtrl = nil) or not ACtrl.Visible or (ADepth > 10) or (ACtrl = Self) then Exit;

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

  if IsDarkColor(FBackColor) then
  begin
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
  end
  else
  begin
    if (ACtrl is TCustomPanel) or (Pos('Panel', ClassNm) > 0) or (Pos('GroupBox', ClassNm) > 0) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TColor($FFF2E4);
      Canvas.Pen.Color := TColor($C89868);
      Canvas.Rectangle(CRect);
    end
    else if (ACtrl is TCustomButton) or (Pos('Button', ClassNm) > 0) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TColor($F8D8B8);
      Canvas.Pen.Color := TColor($B07840);
      Canvas.RoundRect(CRect.Left, CRect.Top, CRect.Right, CRect.Bottom, 2, 2);
    end
    else if (ACtrl is TCustomEdit) or (Pos('Edit', ClassNm) > 0) or (Pos('Memo', ClassNm) > 0) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TColor($FFFFFF);
      Canvas.Pen.Color := TColor($B89068);
      Canvas.Rectangle(CRect);
    end
    else if (ACtrl is TCustomLabel) or (Pos('Label', ClassNm) > 0) then
    begin
      Canvas.Pen.Color := TColor($704820);
      Canvas.Line(CRect.Left, CRect.Top + (MH div 2), Min(CRect.Right, CRect.Left + Max(3, MW - 1)), CRect.Top + (MH div 2));
    end
    else if (Pos('Grid', ClassNm) > 0) or (Pos('List', ClassNm) > 0) or (Pos('Tree', ClassNm) > 0) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TColor($FFFDF9);
      Canvas.Pen.Color := TColor($C09870);
      Canvas.Rectangle(CRect);
    end
    else
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TColor($FCEADB);
      Canvas.Pen.Color := TColor($B88858);
      Canvas.Rectangle(CRect);
    end;
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
  UpdateColors;

  // Outer background of the Minimap window
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FBackColor;
  Canvas.Pen.Color := FBorderColor;
  Canvas.Pen.Width := 1;
  Canvas.RoundRect(0, 0, ClientWidth, ClientHeight, 4, 4);

  // Header bar
  Canvas.Brush.Color := FHeaderColor;
  Canvas.FillRect(Rect(1, 1, ClientWidth - 1, FHeaderHeight));
  Canvas.Pen.Color := FBorderColor;
  Canvas.Line(1, FHeaderHeight, ClientWidth - 1, FHeaderHeight);

  // Current corner tag
  case FCorner of
    mmcBottomLeft:  CornerTag := '[↙]';
    mmcBottomRight: CornerTag := '[↘]';
    mmcTopLeft:     CornerTag := '[↖]';
    mmcTopRight:    CornerTag := '[↗]';
    mmcFloating:    CornerTag := '[⚓]';
  end;

  // Collapse / expand button on right side of title bar
  Canvas.Font.Size := 7;
  Canvas.Font.Color := FTextColor;
  Canvas.Brush.Style := bsClear;
  if FCollapsed then
    Canvas.TextOut(ClientWidth - 16, 3, '+')
  else
    Canvas.TextOut(ClientWidth - 16, 3, '-');

  // Docking icon
  Canvas.TextOut(ClientWidth - 36, 3, CornerTag);

  // Form title and dimensions
  if FDraggingForm and (FTargetForm <> nil) then
  begin
    if FSnappedCenterH and FSnappedCenterV then
      HeaderStr := Format('%s: [Center 1080p]', [FTargetForm.Name])
    else
      HeaderStr := Format('%s: X=%d, Y=%d', [FTargetForm.Name, FVirtualFormLeft, FVirtualFormTop]);
  end
  else if FTargetForm <> nil then
  begin
    if FTargetForm.Position in [poScreenCenter, poDesktopCenter] then
      HeaderStr := Format('%s [%dx%d] (Center)', [FTargetForm.Name, FTargetForm.Width, FTargetForm.Height])
    else
      HeaderStr := Format('%s [%dx%d] (%d,%d)', [FTargetForm.Name, FTargetForm.Width, FTargetForm.Height, FVirtualFormLeft, FVirtualFormTop]);
  end
  else
    HeaderStr := 'Form Designer (1080p)';

  Canvas.Font.Color := FTextColor;
  Canvas.TextOut(6, 4, HeaderStr);

  // If collapsed, do not draw body
  if FCollapsed then Exit;

  CalculateMetrics;

  // 1. Draw 1080p Screen (Full HD Monitor)
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := FScreenColor;
  if IsDarkColor(FBackColor) then
    Canvas.Pen.Color := BlendColors(FScreenColor, clWhite, 0.20)
  else
    Canvas.Pen.Color := TColor($D8B898);
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(FScreenRect);

  // Center guideline lines
  CenterX := FScreenRect.Left + ((FScreenRect.Right - FScreenRect.Left) div 2);
  CenterY := FScreenRect.Top + ((FScreenRect.Bottom - FScreenRect.Top) div 2);

  if FDraggingForm and FSnappedCenterH then
  begin
    Canvas.Pen.Color := TColor($00D7FF); // Highlighted center vertical guide
    Canvas.Line(CenterX, FScreenRect.Top + 1, CenterX, FScreenRect.Bottom - 1);
  end
  else
  begin
    if IsDarkColor(FBackColor) then
      Canvas.Pen.Color := BlendColors(FScreenColor, clWhite, 0.15)
    else
      Canvas.Pen.Color := TColor($F0DEC8);
    Canvas.Line(CenterX, FScreenRect.Top + 1, CenterX, FScreenRect.Bottom - 1);
  end;

  if FDraggingForm and FSnappedCenterV then
  begin
    Canvas.Pen.Color := TColor($00D7FF); // Highlighted center horizontal guide
    Canvas.Line(FScreenRect.Left + 1, CenterY, FScreenRect.Right - 1, CenterY);
  end
  else
  begin
    if IsDarkColor(FBackColor) then
      Canvas.Pen.Color := BlendColors(FScreenColor, clWhite, 0.15)
    else
      Canvas.Pen.Color := TColor($F0DEC8);
    Canvas.Line(FScreenRect.Left + 1, CenterY, FScreenRect.Right - 1, CenterY);
  end;

  // 1080p resolution legend
  Canvas.Font.Size := 6;
  if IsDarkColor(FBackColor) then
    Canvas.Font.Color := BlendColors(FScreenColor, clWhite, 0.40)
  else
    Canvas.Font.Color := TColor($A07850);
  ResStr := '1080p';
  Canvas.TextOut(FScreenRect.Right - Canvas.TextWidth(ResStr) - 3, FScreenRect.Bottom - Canvas.TextHeight(ResStr) - 1, ResStr);

  // If dragging, show coordinates in bottom-left of monitor
  if FDraggingForm and (FTargetForm <> nil) then
  begin
    Canvas.Font.Color := TColor($00D7FF);
    Canvas.TextOut(FScreenRect.Left + 3, FScreenRect.Bottom - Canvas.TextHeight('X') - 1, Format('(%d, %d)', [FVirtualFormLeft, FVirtualFormTop]));
  end;

  if FTargetForm = nil then Exit;

  // 2. Draw proportional Form on 1080p screen
  Canvas.Brush.Style := bsSolid;
  if IsDarkColor(FBackColor) then
  begin
    Canvas.Brush.Color := BlendColors(FScreenColor, clWhite, 0.15);
    if FDraggingForm then
    begin
      Canvas.Pen.Color := TColor($00D7FF);
      Canvas.Pen.Width := 2;
    end
    else
    begin
      Canvas.Pen.Color := BlendColors(FScreenColor, clWhite, 0.35);
      Canvas.Pen.Width := 1;
    end;
  end
  else
  begin
    Canvas.Brush.Color := TColor($FFE8D0);
    if FDraggingForm then
    begin
      Canvas.Pen.Color := TColor($00D7FF);
      Canvas.Pen.Width := 2;
    end
    else
    begin
      Canvas.Pen.Color := TColor($B88048);
      Canvas.Pen.Width := 1;
    end;
  end;
  Canvas.Rectangle(FFormRect);
  Canvas.Pen.Width := 1;

  // Form title bar
  if (FFormRect.Bottom - FFormRect.Top) > 6 then
  begin
    if FDraggingForm then
      Canvas.Brush.Color := TColor($007ACC)
    else if IsDarkColor(FBackColor) then
      Canvas.Brush.Color := BlendColors(FScreenColor, clWhite, 0.28)
    else
      Canvas.Brush.Color := TColor($D88838);
    Canvas.FillRect(Rect(FFormRect.Left + 1, FFormRect.Top + 1, FFormRect.Right - 1, FFormRect.Top + 3));
  end;

  // 3. Draw controls of the form
  for I := 0 to FTargetForm.ControlCount - 1 do
    DrawControlRecursive(FTargetForm.Controls[I], Point(FFormRect.Left, FFormRect.Top));

  // 4. Draw non-visual components
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
      FFormDragStartLeft := FVirtualFormLeft;
      FFormDragStartTop := FVirtualFormTop;
      FHasMovedForm := False;
      FSnappedCenterH := False;
      FSnappedCenterV := False;
      Invalidate;
      Exit;
    end
    else if PtInRect(FScreenRect, Point(X, Y)) then
    begin
      // Clicou na tela 1080p fora do form: reposiciona o form para onde clicou e permite arrastar!
      FVirtualFormLeft := Max(0, Min(REF_SCREEN_WIDTH - FTargetForm.Width,
        Round((X - FScreenRect.Left) / FScale) - (FTargetForm.Width div 2)));
      FVirtualFormTop := Max(0, Min(REF_SCREEN_HEIGHT - FTargetForm.Height,
        Round((Y - FScreenRect.Top) / FScale) - (FTargetForm.Height div 2)));
      CalculateMetrics;
      FDraggingForm := True;
      MouseCapture := True;
      FFormDragStartMouse := Point(X, Y);
      FFormDragStartLeft := FVirtualFormLeft;
      FFormDragStartTop := FVirtualFormTop;
      FHasMovedForm := True;
      Invalidate;
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

    if (NewLeft <> FFormDragStartLeft) or (NewTop <> FFormDragStartTop) then
      FHasMovedForm := True;

    if (NewLeft <> FVirtualFormLeft) or (NewTop <> FVirtualFormTop) then
    begin
      FVirtualFormLeft := NewLeft;
      FVirtualFormTop := NewTop;
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
        Hint := Format('%s [Left: %d, Top: %d] - Drag to move on 1080p screen', [FTargetForm.Name, FVirtualFormLeft, FVirtualFormTop])
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
    if FCorner = mmcFloating then
    begin
      FFloatingLeft := Left;
      FFloatingTop := Top;
      SaveSettings;
    end;
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
      CommitFormPosition;
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

  FEnabled := True;
  FMiniMap := TFormDesignerMiniMapControl.Create(Self);
  LoadSettings;
  if not FEnabled then
    FMiniMap.Visible := False;

  FLastSignature := -1;

  if GlobalDesignHook <> nil then
  begin
    GlobalDesignHook.AddHandlerChangeLookupRoot(@OnChangeLookupRoot);
    GlobalDesignHook.AddHandlerSetSelection(@OnSetSelection);
  end;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 150; // Intervalo suave sem sobrecarga de CPU
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
  if FUpdating then Exit;
  if (FMiniMap <> nil) and (FMiniMap.DraggingForm or FMiniMap.FDragging) then Exit;

  // Se o usuário estiver arrastando/redimensionando com o mouse na IDE, não interfere
  {$IFDEF WINDOWS}
  if GetCapture <> 0 then Exit;
  {$ENDIF}
  if (Mouse <> nil) and (Mouse.Capture <> 0) then Exit;

  UpdatePositionAndState;
end;

procedure TFormDesignerMiniMapManager.LoadSettings;
var
  Cfg: TXMLConfig;
  FileName: string;
begin
  try
    FileName := GetMiniMapConfigFile;
    if not FileExists(FileName) then Exit;
    Cfg := TXMLConfig.Create(FileName);
    try
      FEnabled := Cfg.GetValue('DesignerMiniMap/Enabled/Value', True);
    finally
      Cfg.Free;
    end;
  except
  end;
end;

procedure TFormDesignerMiniMapManager.SaveSettings;
var
  Cfg: TXMLConfig;
  FileName: string;
begin
  try
    FileName := GetMiniMapConfigFile;
    ForceDirectories(ExtractFilePath(FileName));
    Cfg := TXMLConfig.Create(FileName);
    try
      Cfg.SetValue('DesignerMiniMap/Enabled/Value', FEnabled);
      Cfg.Flush;
    finally
      Cfg.Free;
    end;
  except
  end;
end;

procedure TFormDesignerMiniMapManager.SetMiniMapEnabled(AValue: Boolean);
begin
  if FEnabled <> AValue then
  begin
    FEnabled := AValue;
    SaveSettings;
    if not FEnabled then
    begin
      if (FMiniMap <> nil) and FMiniMap.Visible then
        FMiniMap.Visible := False;
    end
    else
      UpdatePositionAndState;
  end;
end;

procedure TFormDesignerMiniMapManager.ToggleMiniMap(Sender: TObject);
begin
  MiniMapEnabled := not MiniMapEnabled;
end;

procedure TFormDesignerMiniMapManager.UpdatePositionAndState;
var
  DesignedForm: TCustomForm;
  DesignArea: TWinControl;
  Sig: Int64;
begin
  if FUpdating then Exit;
  if not FEnabled then
  begin
    if (FMiniMap <> nil) and FMiniMap.Visible then
      FMiniMap.Visible := False;
    Exit;
  end;
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
    end;

    if FMiniMap.TargetForm <> DesignedForm then
      FMiniMap.TargetForm := DesignedForm;

    if not FMiniMap.Visible then
    begin
      FMiniMap.Visible := True;
      FMiniMap.BringToFront;
      FMiniMap.UpdateDockPosition;
    end;

    // Redesenha apenas quando as propriedades do Form mudarem
    Sig := ComputeSignature(DesignedForm);
    if Sig <> FLastSignature then
    begin
      FLastSignature := Sig;
      FMiniMap.FVirtualFormValid := False;
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

  RegisterIDEMenuCommand(itmViewMainWindows, 'ViewDesignerMiniMap', 'Designer Minimap', @DesignerMiniMapGlobal.ToggleMiniMap);
end;

initialization

finalization
  FreeAndNil(DesignerMiniMapGlobal);

end.
