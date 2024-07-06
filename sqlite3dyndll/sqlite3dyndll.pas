{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit sqlite3dyndll;

interface

uses
  SQLite3DynConnection, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('SQLite3DynConnection', @SQLite3DynConnection.Register);
end;

initialization
  RegisterPackage('sqlite3dyndll', @Register);
end.
