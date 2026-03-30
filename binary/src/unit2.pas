unit Unit2;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, FileUtil;

implementation

procedure CopyDirectory(const SourceDir, TargetDir: string);
begin
  CopyDirTree(SourceDir, TargetDir, [cffOverwriteFile, cffCreateDestDirectory]);
end;


end.

