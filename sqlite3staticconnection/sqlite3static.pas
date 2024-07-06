{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit sqlite3static;

interface

uses
  SQLite3StaticConnection, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('SQLite3StaticConnection', @SQLite3StaticConnection.Register);
end;

initialization
  RegisterPackage('sqlite3static', @Register);
end.
