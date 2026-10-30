{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit lazarus_minimap_ide;

{$warn 5023 off : no warning about unused units}
interface

uses
  LazarusDesignerMiniMap, LazarusCodeMiniMap, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('LazarusDesignerMiniMap', @LazarusDesignerMiniMap.Register);
  RegisterUnit('LazarusCodeMiniMap', @LazarusCodeMiniMap.Register);
end;

initialization
  RegisterPackage('lazarus_minimap_ide', @Register);
end.
