{
    This file was taken from the Free Pascal Classes Library as noted in the
    original copyright notices included below.  All changes made by
    Kurt Fitzner <kurt@va1der.ca> (previously kurt.fitzner@gmail.com) are
    released into the public domain.

    This is a duplicate implementation of TSQLite3Connection that: 1) exposes
    FHandle so that you can derrive classes that override and modify the
    parent's behaviour rather than just add to it, and 2) adds a ClientLibrary
    property so you can explicitely set the copy of the SQLite3 DLL to load.
    It is noted here that it would not have been required to make a clunky
    duplicate implementation to accomplish #2 if #1 had been done in the FCL.

    NOTES:

    15 Mar 2013 Kurt Fitzner <Kurt.Fitzner@gmail.com>
    The component has been reworked to a) add in a ClientLibrary property so
    the developer can specify the location of the sqlite library and B) the
    poor decision to use private definitions has been corrected so that in the
    future, anyone can simply just derive a new class off this one to make the
    same sort of change I made without duplicating the entire class.

    20 Nov 2016 Kurt Fitzner <kurt@va1der.ca>
    Changes to the FCL require a new version, which was to be expected when
    tinkering with the way a component works.  What I've done for ease of
    maintenance is encapsulated the entirety of each different supported
    version of this component (including comments) inside its own conditional
    compilation test.  The assumption is that the compiler version will be
    diagnostic of the correct component version to use.  And let me reiterate,
    for anyone that might read this, my intensely strong objection to the use
    of private definitions in any base class.
}

// XXX For FPC 2.6.0 (included with Lazarus 1.0.6, and perhaps others)
//  ^--- a bookmark to look for that will be on each version divider below
{$IF FPC_FULLVERSION = 20600}
{
    This file is part of the Free Pascal Classes Library (FCL).
    Copyright (c) 2006 by the Free Pascal development team

    SQLite3 connection for SQLDB

    See the File COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{
  Based on an implementation by Martin Schreiber, part of MSEIDE.
  Reworked all code so it conforms to FCL coding standards.
}

unit SQLite3DynConnection;
{$mode objfpc}
{$h+}

interface

uses
  classes, db, bufdataset, sqldb, sqlite3dyn, types, LResources;

const
  sqliteerrormax = 99;

type
  PDateTime = ^TDateTime;

  TSqliteOption = (sloTransactions,sloDesignTransactions);
  TSqliteOptions = set of TSqliteOption;

  TStringArray = Array of string;
  PStringArray = ^TStringArray;

  TArrayStringArray = Array of TStringArray;
  PArrayStringArray = ^TArrayStringArray;

  { TSQLite3DynConnection }

  TSQLite3DynConnection = class(TSQLConnection)
  protected
    fhandle: psqlite3;
    foptions: TSQLiteOptions;
    FClientLibrary: string;
    procedure setoptions(const avalue: tsqliteoptions);
    function stringsquery(const asql: string): TArrayStringArray;
    procedure checkerror(const aerror: integer);

    procedure DoInternalConnect; override;
    procedure DoInternalDisconnect; override;
    function GetHandle : pointer; override;

    Function AllocateCursorHandle : TSQLCursor; override;
                        //aowner used as blob cache
    Procedure DeAllocateCursorHandle(var cursor : TSQLCursor); override;
    Function AllocateTransactionHandle : TSQLHandle; override;

    procedure PrepareStatement(cursor: TSQLCursor; ATransaction : TSQLTransaction;
                          buf: string; AParams : TParams); override;
    procedure Execute(cursor: TSQLCursor;atransaction:tSQLtransaction; AParams : TParams); override;
    function Fetch(cursor : TSQLCursor) : boolean; override;
    procedure AddFieldDefs(cursor: TSQLCursor; FieldDefs : TfieldDefs); override;
    procedure UnPrepareStatement(cursor : TSQLCursor); override;

    procedure FreeFldBuffers(cursor : TSQLCursor); override;
    function LoadField(cursor : TSQLCursor;FieldDef : TfieldDef;buffer : pointer; out CreateBlob : boolean) : boolean; override;
           //if bufsize < 0 -> buffer was to small, should be -bufsize
    function GetTransactionHandle(trans : TSQLHandle): pointer; override;
    function Commit(trans : TSQLHandle) : boolean; override;
    function RollBack(trans : TSQLHandle) : boolean; override;
    function StartdbTransaction(trans : TSQLHandle; aParams : string) : boolean; override;
    procedure CommitRetaining(trans : TSQLHandle); override;
    procedure RollBackRetaining(trans : TSQLHandle); override;
    procedure LoadBlobIntoBuffer(FieldDef: TFieldDef;ABlobBuf: PBufBlobField; cursor: TSQLCursor; ATransaction : TSQLTransaction); override;
    // New methods
    procedure execsql(const asql: string);
    procedure UpdateIndexDefs(IndexDefs : TIndexDefs;TableName : string); override; // Differs from SQLDB.
    function RowsAffected(cursor: TSQLCursor): TRowsCount; override;
    function GetSchemaInfoSQL(SchemaType : TSchemaType; SchemaObjectName, SchemaPattern : string) : string; override;
    function StrToStatementType(s : string) : TStatementType; override;
  public
    constructor Create(AOwner : TComponent); override;
    function GetInsertID: int64;
    procedure GetFieldNames(const TableName : string; List :  TStrings); override;
  published
   property ClientLibrary: string read FClientLibrary write FClientLibrary;
   property Options: TSqliteOptions read FOptions write SetOptions;
  end;

procedure Register;

Var
  SQLiteLibraryName : String = sqlite3lib;

implementation

uses
  dbconst, sysutils, dateutils, FmtBCD;

const
  JulianDateShift = 2415018.5; //distance from "julian day 0" (January 1, 4713 BC 12:00AM) to "1899-12-30 00:00AM"

type

 TStorageType = (stNone,stInteger,stFloat,stText,stBlob,stNull);

 TSQLite3Cursor = class(tsqlcursor)
  private
   fhandle : psqlite3;
   fconnection: TSQLite3DynConnection;
   fstatement: psqlite3_stmt;
   ftail: pchar;
   fstate: integer;
   fparambinding: array of Integer;
   procedure checkerror(const aerror: integer);
   procedure bindparams(AParams : TParams);
   Procedure Prepare(Buf : String; APArams : TParams);
   Procedure UnPrepare;
   Procedure Execute;
   Function Fetch : Boolean;
 public
   RowsAffected : Largeint;
 end;

procedure freebindstring(astring: pointer); cdecl;
begin
  StrDispose(AString);
end;

procedure TSQLite3Cursor.checkerror(const aerror: integer);

Var
  S : String;

begin
 if (aerror<>sqlite_ok) then
   begin
   S:=strpas(sqlite3_errmsg(fhandle));
   DatabaseError(S);
   end;
end;

Procedure TSQLite3Cursor.bindparams(AParams : TParams);

  Function PCharStr(Const S : String) : PChar;

  begin
    Result:=StrAlloc(Length(S)+1);
    If (Result<>Nil) then
      StrPCopy(Result,S);
  end;

Var
  I : Integer;
  P : TParam;
  //pc : pchar;
  str1: string;
  //cu1: currency;
  do1: double;
  //parms : array of Integer;
  wstr1: widestring;

begin
  for I:=1  to high(fparambinding)+1 do
    begin
    P:=aparams[fparambinding[I-1]];
    if P.isnull then
      checkerror(sqlite3_bind_null(fstatement,I))
    else
      case P.datatype of
        ftinteger,
        ftboolean,
        ftsmallint: checkerror(sqlite3_bind_int(fstatement,I,p.asinteger));
        ftword:     checkerror(sqlite3_bind_int(fstatement,I,P.asword));
        ftlargeint: checkerror(sqlite3_bind_int64(fstatement,I,P.aslargeint));
        ftbcd,
        ftfloat,
        ftcurrency:
                begin
                do1:= P.AsFloat;
                checkerror(sqlite3_bind_double(fstatement,I,do1));
                end;
        ftdatetime,
        ftdate,
        fttime: begin
                do1:= P.AsFloat + JulianDateShift;
                checkerror(sqlite3_bind_double(fstatement,I,do1));
                end;
        ftFMTBcd:
                begin
                str1:=BCDToStr(P.AsFMTBCD, Fconnection.FSQLFormatSettings);
                checkerror(sqlite3_bind_text(fstatement, I, PChar(str1), length(str1), sqlite3_destructor_type(SQLITE_TRANSIENT)));
                end;
        ftstring,
        ftFixedChar,
        ftmemo: begin // According to SQLite documentation, CLOB's (ftMemo) have the Text affinity
                str1:= p.asstring;
                checkerror(sqlite3_bind_text(fstatement,I,pcharstr(str1), length(str1),@freebindstring));
                end;
        ftblob: begin
                str1:= P.asstring;
                checkerror(sqlite3_bind_blob(fstatement,I,pcharstr(str1), length(str1),@freebindstring));
                end;
        ftWideString, ftFixedWideChar, ftWideMemo:
        begin
          wstr1:=P.AsWideString;
          checkerror(sqlite3_bind_text16(fstatement,I, PWideChar(wstr1), length(wstr1)*sizeof(WideChar), sqlite3_destructor_type(SQLITE_TRANSIENT)));
        end
      else
        DatabaseErrorFmt(SUnsupportedParameter, [Fieldtypenames[P.DataType], Self]);
      end; { Case }
    end;
end;

Procedure TSQLite3Cursor.Prepare(Buf : String; APArams : TParams);

begin
  if assigned(aparams) and (aparams.count > 0) then
    buf := aparams.parsesql(buf,false,false,false,psinterbase,fparambinding);
  checkerror(sqlite3_prepare(fhandle,pchar(buf),length(buf),@fstatement,@ftail));
  FPrepared:=True;
end;

Procedure TSQLite3Cursor.UnPrepare;

begin
  sqlite3_finalize(fstatement); // No check.
  FPrepared:=False;
end;

Procedure TSQLite3Cursor.Execute;

var
 wo1: word;

begin
{$ifdef i386}
  wo1:= get8087cw;
  set8087cw(wo1 or $1f);             //mask exceptions, Sqlite3 has overflow
  Try  // Why do people always forget this ??
{$endif}
    fstate:= sqlite3_step(fstatement);
{$ifdef i386}
  finally
    set8087cw(wo1);                    //restore
  end;
{$endif}
  if (fstate<=sqliteerrormax) then
    checkerror(sqlite3_reset(fstatement));
  RowsAffected:=sqlite3_changes(fhandle);
  if (fstate=sqlite_row) then
    fstate:= sqliteerrormax; //first row
end;

Function TSQLite3Cursor.Fetch : Boolean;

begin
  if (fstate=sqliteerrormax) then
    fstate:=sqlite_row //first row;
  else if (fstate=sqlite_row) then
    begin
    fstate:=sqlite3_step(fstatement);
    if (fstate<=sqliteerrormax) then
      checkerror(sqlite3_reset(fstatement));  //right error returned??
    end;
  result:=(fstate=sqlite_row);
end;

{ TSQLite3DynConnection }

procedure TSQLite3DynConnection.LoadBlobIntoBuffer(FieldDef: TFieldDef;ABlobBuf: PBufBlobField; cursor: TSQLCursor; ATransaction : TSQLTransaction);

var
 int1: integer;
 st: psqlite3_stmt;
 fnum: integer;
 p1: Pointer;

begin
  st:=TSQLite3Cursor(cursor).fstatement;
  fnum:= FieldDef.fieldno - 1;

  case FieldDef.DataType of
    ftWideMemo:
      begin
      p1 := sqlite3_column_text16(st,fnum);
      int1 := sqlite3_column_bytes16(st,fnum);
      end;
    ftMemo:
      begin
      p1 := sqlite3_column_text(st,fnum);
      int1 := sqlite3_column_bytes(st,fnum);
      end;
    else //ftBlob
      begin
      p1 := sqlite3_column_blob(st,fnum);
      int1 := sqlite3_column_bytes(st,fnum);
      end;
  end;

  ReAllocMem(ABlobBuf^.BlobBuffer^.Buffer, int1);
  if int1 > 0 then
    move(p1^, ABlobBuf^.BlobBuffer^.Buffer^, int1);
  ABlobBuf^.BlobBuffer^.Size := int1;
end;

function TSQLite3DynConnection.AllocateTransactionHandle: TSQLHandle;
begin
 result:= tsqlhandle.create;
end;

function TSQLite3DynConnection.AllocateCursorHandle: TSQLCursor;

Var
  Res : TSQLite3Cursor;

begin
  Res:= TSQLite3Cursor.create;
  Res.fconnection:=Self;
  Result:=Res;
end;

procedure TSQLite3DynConnection.DeAllocateCursorHandle(var cursor: TSQLCursor);
begin
  freeandnil(cursor);
end;

procedure TSQLite3DynConnection.PrepareStatement(cursor: TSQLCursor;
               ATransaction: TSQLTransaction; buf: string; AParams: TParams);
begin
  TSQLite3Cursor(cursor).fhandle:=self.fhandle;
  TSQLite3Cursor(cursor).Prepare(Buf,AParams);
end;

procedure TSQLite3DynConnection.UnPrepareStatement(cursor: TSQLCursor);

begin
  TSQLite3Cursor(cursor).UnPrepare;
  TSQLite3Cursor(cursor).fhandle:=nil;
end;


Type
  TFieldMap = Record
    N : String;
    T : TFieldType;
  end;

Const
  FieldMapCount = 24;
  FieldMap : Array [1..FieldMapCount] of TFieldMap = (
   (n:'INT'; t: ftInteger),
   (n:'LARGEINT'; t:ftlargeInt),
   (n:'BIGINT'; t:ftlargeInt),
   (n:'WORD'; t: ftWord),
   (n:'SMALLINT'; t: ftSmallint),
   (n:'BOOLEAN'; t: ftBoolean),
   (n:'REAL'; t: ftFloat),
   (n:'FLOAT'; t: ftFloat),
   (n:'DOUBLE'; t: ftFloat),
   (n:'TIMESTAMP'; t: ftDateTime),
   (n:'DATETIME'; t: ftDateTime), // MUST be before date
   (n:'DATE'; t: ftDate),
   (n:'TIME'; t: ftTime),
   (n:'CURRENCY'; t: ftCurrency),
   (n:'VARCHAR'; t: ftString),
   (n:'CHAR'; t: ftString),
   (n:'NUMERIC'; t: ftBCD),
   (n:'DECIMAL'; t: ftBCD),
   (n:'TEXT'; t: ftmemo),
   (n:'CLOB'; t: ftmemo),
   (n:'BLOB'; t: ftBlob),
   (n:'NCHAR'; t: ftFixedWideChar),
   (n:'NVARCHAR'; t: ftWideString),
   (n:'NCLOB'; t: ftWideMemo)
{ Template:
  (n:''; t: ft)
}
  );

procedure TSQLite3DynConnection.AddFieldDefs(cursor: TSQLCursor;
               FieldDefs: TfieldDefs);
var
 i     : integer;
 FN,FD : string;
 ft1   : tfieldtype;
 size1, size2 : integer;
 ar1   : TStringArray;
 fi    : integer;
 st    : psqlite3_stmt;

 function ExtractPrecisionAndScale(decltype: string; var precision, scale: integer): boolean;
 var p: integer;
 begin
   p:=pos('(', decltype);
   Result:=p>0;
   if not Result then Exit;
   System.Delete(decltype,1,p);
   p:=pos(')', decltype);
   Result:=p>0;
   if not Result then Exit;
   decltype:=copy(decltype,1,p-1);
   p:=pos(',', decltype);
   if p=0 then
   begin
     precision:=StrToIntDef(decltype, precision);
     scale:=0;
   end
   else
   begin
     precision:=StrToIntDef(copy(decltype,1,p-1), precision);
     scale:=StrToIntDef(copy(decltype,p+1,length(decltype)-p), scale);
   end;
 end;

begin
  st:=TSQLite3Cursor(cursor).fstatement;
  for i:= 0 to sqlite3_column_count(st) - 1 do
    begin
    FN:=sqlite3_column_name(st,i);
    FD:=uppercase(sqlite3_column_decltype(st,i));
    ft1:= ftUnknown;
    size1:= 0;
    for fi := 1 to FieldMapCount do if pos(FieldMap[fi].N,FD)=1 then
      begin
      ft1:=FieldMap[fi].t;
      break;
      end;
    // In case of an empty fieldtype (FD='', which is allowed and used in calculated
    // columns (aggregates) and by pragma-statements) or an unknown fieldtype,
    // use the field's affinity:
    if ft1=ftUnknown then
      case TStorageType(sqlite3_column_type(st,i)) of
        stInteger: ft1:=ftLargeInt;
        stFloat:   ft1:=ftFloat;
        stBlob:    ft1:=ftBlob;
        else       ft1:=ftString;
      end;
    // handle some specials.
    size1:=0;
    case ft1 of
      ftString,
      ftFixedChar,
      ftFixedWideChar,
      ftWideString:
               begin
                 size1 := 255; //sql: if length is omitted then length is 1
                 size2 := 0;
                 ExtractPrecisionAndScale(FD, size1, size2);
                 if size1 > dsMaxStringSize then size1 := dsMaxStringSize;
               end;
      ftBCD:   begin
                 size2 := MaxBCDPrecision; //sql: if a precision is omitted, then use implementation-defined
                 size1 := 0;               //sql: if a scale is omitted then scale is 0
                 ExtractPrecisionAndScale(FD, size2, size1);
                 if (size2<=18) and (size1=0) then
                   ft1:=ftLargeInt
                 else if (size2-size1>MaxBCDPrecision-MaxBCDScale) or (size1>MaxBCDScale) then
                   ft1:=ftFmtBCD;
               end;
      ftUnknown : DatabaseError('Unknown record type: '+FN);
    end; // Case
    tfielddef.create(fielddefs,FieldDefs.MakeNameUnique(FN),ft1,size1,false,i+1);
    end;
end;

procedure TSQLite3DynConnection.Execute(cursor: TSQLCursor; atransaction: tsqltransaction; AParams: TParams);
var
 SC : TSQLite3Cursor;

begin
  SC:=TSQLite3Cursor(cursor);
  checkerror(sqlite3_reset(sc.fstatement));
  If (AParams<>Nil) and (AParams.count > 0) then
    SC.BindParams(AParams);
  SC.Execute;
end;

Function NextWord(Var S : ShortString; Sep : Char) : String;

Var
  P : Integer;

begin
  P:=Pos(Sep,S);
  If (P=0) then
    P:=Length(S)+1;
  Result:=Copy(S,1,P-1);
  Delete(S,1,P);
end;

Function ParseSQLiteDate(S : ShortString) : TDateTime;

Var
  Year, Month, Day : Integer;

begin
 Result:=0;
 If TryStrToInt(NextWord(S,'-'),Year) then
   if TryStrToInt(NextWord(S,'-'),Month) then
     if TryStrToInt(NextWord(S,'-'),Day) then
        Result:=EncodeDate(Year,Month,Day);
end;

Function ParseSQLiteTime(S : ShortString; Interval: boolean) : TDateTime;

Var
  Hour, Min, Sec, MSec : Integer;

begin
  Result:=0;
  If TryStrToInt(NextWord(S,':'),Hour) then
    if TryStrToInt(NextWord(S,':'),Min) then
      if TryStrToInt(NextWord(S,'.'),Sec) then
        begin
        MSec:=StrToIntDef(S,0);
        if Interval then
          Result:=EncodeTimeInterval(Hour,Min,Sec,MSec)
        else
          Result:=EncodeTime(Hour,Min,Sec,MSec);
        end;
end;

Function ParseSQLiteDateTime(S : String) : TDateTime;

var
  P : Integer;
  DS,TS : ShortString;

begin
  DS:='';
  TS:='';
  P:=Pos(' ',S);
  If (P<>0) then
    begin
    DS:=Copy(S,1,P-1);
    TS:=S;
    Delete(TS,1,P);
    end
  else
    begin
    If (Pos('-',S)<>0) then
      DS:=S
    else if (Pos(':',S)<>0) then
      TS:=S;
    end;
  Result:=ComposeDateTime(ParseSQLiteDate(DS),ParseSQLiteTime(TS,False));
end;

function TSQLite3DynConnection.LoadField(cursor : TSQLCursor;FieldDef : TfieldDef;buffer : pointer; out CreateBlob : boolean) : boolean;

var
 st1: TStorageType;
 fnum: integer;
 str1: string;
 int1 : integer;
 bcd: tBCD;
 bcdstr: FmtBCDStringtype;
 st    : psqlite3_stmt;

begin
  st:=TSQLite3Cursor(cursor).fstatement;
  fnum:= FieldDef.fieldno - 1;
  st1:= TStorageType(sqlite3_column_type(st,fnum));
  CreateBlob:=false;
  result:= st1 <> stnull;
  if Not result then
    Exit;
  case FieldDef.datatype of
    ftInteger  : pinteger(buffer)^  := sqlite3_column_int(st,fnum);
    ftSmallInt : psmallint(buffer)^ := sqlite3_column_int(st,fnum);
    ftWord     : pword(buffer)^     := sqlite3_column_int(st,fnum);
    ftBoolean  : pwordbool(buffer)^ := sqlite3_column_int(st,fnum)<>0;
    ftLargeInt : PInt64(buffer)^:= sqlite3_column_int64(st,fnum);
    ftBCD      : PCurrency(buffer)^:= FloattoCurr(sqlite3_column_double(st,fnum));
    ftFloat,
    ftCurrency : pdouble(buffer)^:= sqlite3_column_double(st,fnum);
    ftDateTime,
    ftDate,
    ftTime:  if st1 = sttext then
               begin
               setlength(str1,sqlite3_column_bytes(st,fnum));
               move(sqlite3_column_text(st,fnum)^,str1[1],length(str1));
               case FieldDef.datatype of
                 ftDateTime: PDateTime(Buffer)^:=ParseSqliteDateTime(str1);
                 ftDate    : PDateTime(Buffer)^:=ParseSqliteDate(str1);
                 ftTime    : PDateTime(Buffer)^:=ParseSQLiteTime(str1,true);
               end; {case}
               end
             else
               begin
               PDateTime(buffer)^ := sqlite3_column_double(st,fnum);
               if PDateTime(buffer)^ > 1721059.5 {Julian 01/01/0000} then
                  PDateTime(buffer)^ := PDateTime(buffer)^ - JulianDateShift; //backward compatibility hack
               end;
    ftFixedChar,
    ftString: begin
              int1:= sqlite3_column_bytes(st,fnum);
              if int1>FieldDef.Size then
                int1:=FieldDef.Size;
              if int1 > 0 then
                 move(sqlite3_column_text(st,fnum)^,buffer^,int1);
              end;
    ftFmtBCD: begin
              int1:= sqlite3_column_bytes(st,fnum);
              if (int1 > 0) and (int1 <= MAXFMTBcdFractionSize) then
                begin
                SetLength(bcdstr,int1);
                move(sqlite3_column_text(st,fnum)^,bcdstr[1],int1);
                // sqlite always uses the point as decimal-point
                if not TryStrToBCD(bcdstr,bcd,FSQLFormatSettings) then
                  // sqlite does the same, if the value can't be interpreted as a
                  // number in sqlite3_column_int, return 0
                  bcd := 0;
                end
              else
                bcd := 0;
              pBCD(buffer)^:= bcd;
              end;
    ftFixedWideChar,
    ftWideString:
      begin
      int1 := sqlite3_column_bytes16(st,fnum)+2; //The value returned does not include the zero terminator at the end of the string
      if int1>(FieldDef.Size+1)*2 then
        int1:=(FieldDef.Size+1)*2;
      if int1 > 0 then
        move(sqlite3_column_text16(st,fnum)^, buffer^, int1); //Strings returned by sqlite3_column_text() and sqlite3_column_text16(), even empty strings, are always zero terminated.
      end;
    ftWideMemo,
    ftMemo,
    ftBlob: CreateBlob:=True;
  else { Case }
   result:= false; // unknown
  end; { Case }
end;

function TSQLite3DynConnection.Fetch(cursor: TSQLCursor): boolean;

begin
  Result:=TSQLite3Cursor(cursor).Fetch;
end;

procedure TSQLite3DynConnection.FreeFldBuffers(cursor: TSQLCursor);
begin
 //dummy
end;

function TSQLite3DynConnection.GetTransactionHandle(trans: TSQLHandle): pointer;
begin
 result:= nil;
end;

function TSQLite3DynConnection.Commit(trans: TSQLHandle): boolean;
begin
  execsql('COMMIT');
  result:= true;
end;

function TSQLite3DynConnection.RollBack(trans: TSQLHandle): boolean;
begin
  execsql('ROLLBACK');
  result:= true;
end;

function TSQLite3DynConnection.StartdbTransaction(trans: TSQLHandle;
               aParams: string): boolean;
begin
  execsql('BEGIN');
  result:= true;
end;

procedure TSQLite3DynConnection.CommitRetaining(trans: TSQLHandle);
begin
  commit(trans);
  execsql('BEGIN');
end;

procedure TSQLite3DynConnection.RollBackRetaining(trans: TSQLHandle);
begin
  rollback(trans);
  execsql('BEGIN');
end;

procedure TSQLite3DynConnection.DoInternalConnect;
var
  str1: string;
begin
  if Length(databasename)=0 then
    DatabaseError(SErrNoDatabaseName,self);
  if (FClientLibrary = '') then FClientLibrary := SQLiteLibraryName;
  InitializeSqlite(FClientLibrary);
  str1:= databasename;
  checkerror(sqlite3_open(pchar(str1),@fhandle));
end;

procedure TSQLite3DynConnection.DoInternalDisconnect;

begin
  if fhandle <> nil then
    begin
    checkerror(sqlite3_close(fhandle));
    fhandle:= nil;
    releasesqlite;
    end;
end;

function TSQLite3DynConnection.GetHandle: pointer;
begin
  result:= fhandle;
end;

procedure TSQLite3DynConnection.checkerror(const aerror: integer);

Var
  S : String;

begin
 if (aerror<>sqlite_ok) then
   begin
   S:=strpas(sqlite3_errmsg(fhandle));
   DatabaseError(S,Self);
   end;
end;

procedure TSQLite3DynConnection.execsql(const asql: string);
var
 err  : pchar;
 str1 : string;
 res  : integer;
begin
 err:= nil;
 Res := sqlite3_exec(fhandle,pchar(asql),nil,nil,@err);
 if err <> nil then
   begin
   str1:= strpas(err);
   sqlite3_free(err);
   end;
 if (res<>sqlite_ok) then
   databaseerror(str1);
end;

function execcallback(adata: pointer; ncols: longint; //adata = PStringArray
                avalues: PPchar; anames: PPchar):longint; cdecl;
var
  P : PStringArray;
  i : integer;

begin
  P:=PStringArray(adata);
  SetLength(P^,ncols);
  for i:= 0 to ncols - 1 do
    P^[i]:= strPas(avalues[i]);
  result:= 0;
end;

function execscallback(adata: pointer; ncols: longint; //adata = PArrayStringArray
                avalues: PPchar; anames: PPchar):longint; cdecl;
var
 I,N : integer;
 PP : PArrayStringArray;
 p  : PStringArray;

begin
 PP:=PArrayStringArray(adata);
 N:=high(PP^); // Length-1;
 setlength(PP^,N+2); // increase with 1;
 p:= @(PP^[N+1]); // newly added array, fill with data.
 setlength(p^,ncols);
 for i:= 0 to ncols - 1 do
   p^[i]:= strPas(avalues[i]);
 result:= 0;
end;

function TSQLite3DynConnection.stringsquery(const asql: string): TArrayStringArray;
begin
  SetLength(result,0);
  checkerror(sqlite3_exec(fhandle,pchar(asql),@execscallback,@result,nil));
end;

function TSQLite3DynConnection.RowsAffected(cursor: TSQLCursor): TRowsCount;
begin
  if assigned(cursor) then
    Result := (cursor as TSQLite3Cursor).RowsAffected
  else
    Result := -1;
end;

function TSQLite3DynConnection.GetSchemaInfoSQL(SchemaType: TSchemaType;
  SchemaObjectName, SchemaPattern: string): string;

begin
  case SchemaType of
    stTables     : result := 'select name as table_name from sqlite_master where type = ''table'' order by 1';
    stColumns    : result := 'pragma table_info(''' + (SchemaObjectName) + ''')';
  else
    DatabaseError(SMetadataUnavailable)
  end; {case}
end;

function TSQLite3DynConnection.StrToStatementType(s: string): TStatementType;
begin
  S:=Lowercase(s);
  if s = 'pragma' then exit(stSelect);
  result := inherited StrToStatementType(s);
end;

constructor TSQLite3DynConnection.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FConnOptions := FConnOptions + [sqEscapeRepeat] + [sqEscapeSlash];
  FieldNameQuoteChars:=DoubleQuotes;
  FClientLibrary := '';
end;

procedure TSQLite3DynConnection.UpdateIndexDefs(IndexDefs: TIndexDefs; TableName: string);
var
  artableinfo, arindexlist, arindexinfo: TArrayStringArray;
  il,ii: integer;
  IndexName: string;
  IndexOptions: TIndexOptions;
  PKFields, IXFields: TStrings;

  function CheckPKFields:boolean;
  var i: integer;
  begin
    Result:=false;
    if IXFields.Count<>PKFields.Count then Exit;
    for i:=0 to IXFields.Count-1 do
      if PKFields.IndexOf(IXFields[i])<0 then Exit;
    Result:=true;
    PKFields.Clear;
  end;

begin
  PKFields:=TStringList.Create;
  PKFields.Delimiter:=';';
  IXFields:=TStringList.Create;
  IXFields.Delimiter:=';';

  //primary key fields
  artableinfo := stringsquery('PRAGMA table_info('+TableName+');');
  for ii:=low(artableinfo) to high(artableinfo) do
    if (high(artableinfo[ii]) >= 5) and (artableinfo[ii][5] = '1') then
      PKFields.Add(artableinfo[ii][1]);

  //list of all table indexes
  arindexlist:=stringsquery('PRAGMA index_list('+TableName+');');
  for il:=low(arindexlist) to high(arindexlist) do
    begin
    IndexName:=arindexlist[il][1];
    if arindexlist[il][2]='1' then
      IndexOptions:=[ixUnique]
    else
      IndexOptions:=[];
    //list of columns in given index
    arindexinfo:=stringsquery('PRAGMA index_info('+IndexName+');');
    IXFields.Clear;
    for ii:=low(arindexinfo) to high(arindexinfo) do
      IXFields.Add(arindexinfo[ii][2]);

    if CheckPKFields then IndexOptions:=IndexOptions+[ixPrimary];

    IndexDefs.Add(IndexName, IXFields.DelimitedText, IndexOptions);
    end;

  if PKFields.Count > 0 then //in special case for INTEGER PRIMARY KEY column, unique index is not created
    IndexDefs.Add('$PRIMARY_KEY$', PKFields.DelimitedText, [ixPrimary,ixUnique]);

  PKFields.Free;
  IXFields.Free;
end;

function TSQLite3DynConnection.getinsertid: int64;
begin
 result:= sqlite3_last_insert_rowid(fhandle);
end;

procedure TSQLite3DynConnection.GetFieldNames(const TableName: string;
  List: TStrings);
begin
  GetDBInfo(stColumns,TableName,'name',List);
end;

procedure TSQLite3DynConnection.setoptions(const avalue: tsqliteoptions);
begin
 if avalue <> foptions then
   begin
   checkdisconnected;
   foptions:= avalue;
   end;
end;

procedure Register;
begin
  {$I sqlite3dynconnection_icon.lrs}
  RegisterComponents('SQLdb',[TSQLite3DynConnection]);
end;


end.

// End of FPC version 2.6.0 component

// XXX For FPC 3.0.0 (included with Lazarus 1.6.2, and perhaps others)
{$ELSEIF FPC_FULLVERSION = 30000}
{
    This file is part of the Free Pascal Classes Library (FCL).
    Copyright (c) 2006-2014 by the Free Pascal development team

    SQLite3 connection for SQLDB

    See the File COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{
  Based on an implementation by Martin Schreiber, part of MSEIDE.
  Reworked all code so it conforms to FCL coding standards.

  TSQLite3Connection properties
      Params - "foreign_keys=ON" - enable foreign key support for this connection:
                                   http://www.sqlite.org/foreignkeys.html#fk_enable

}

unit SQLite3DynConnection;
{$mode objfpc}
{$h+}

interface

uses
  classes, db, bufdataset, sqldb, sqlite3dyn, types, LResources;

const
  sqliteerrormax = 99;

type
  PDateTime = ^TDateTime;

  TStringArray = Array of string;
  PStringArray = ^TStringArray;

  TArrayStringArray = Array of TStringArray;
  PArrayStringArray = ^TArrayStringArray;

  { TSQLite3DynConnection }

  TSQLite3DynConnection = class(TSQLConnection)
  protected
    fhandle: psqlite3;
    FClientLibrary: string;

    procedure DoInternalConnect; override;
    procedure DoInternalDisconnect; override;
    function GetHandle : pointer; override;

    Function AllocateCursorHandle : TSQLCursor; override;
    Procedure DeAllocateCursorHandle(var cursor : TSQLCursor); override;
    Function AllocateTransactionHandle : TSQLHandle; override;

    function StrToStatementType(s : string) : TStatementType; override;
    procedure PrepareStatement(cursor: TSQLCursor; ATransaction : TSQLTransaction; buf: string; AParams : TParams); override;
    procedure Execute(cursor: TSQLCursor;ATransaction:tSQLtransaction; AParams : TParams); override;
    function Fetch(cursor : TSQLCursor) : boolean; override;
    procedure AddFieldDefs(cursor: TSQLCursor; FieldDefs : TFieldDefs); override;
    procedure UnPrepareStatement(cursor : TSQLCursor); override;

    procedure FreeFldBuffers(cursor : TSQLCursor); override;
    function LoadField(cursor : TSQLCursor; FieldDef : TFieldDef; buffer : pointer; out CreateBlob : boolean) : boolean; override;
    procedure LoadBlobIntoBuffer(FieldDef: TFieldDef; ABlobBuf: PBufBlobField; cursor: TSQLCursor; ATransaction : TSQLTransaction); override;

    function GetTransactionHandle(trans : TSQLHandle): pointer; override;
    function Commit(trans : TSQLHandle) : boolean; override;
    function RollBack(trans : TSQLHandle) : boolean; override;
    function StartDBTransaction(trans : TSQLHandle; aParams : string) : boolean; override;
    procedure CommitRetaining(trans : TSQLHandle); override;
    procedure RollBackRetaining(trans : TSQLHandle); override;

    procedure UpdateIndexDefs(IndexDefs : TIndexDefs; TableName : string); override;
    function GetSchemaInfoSQL(SchemaType : TSchemaType; SchemaObjectName, SchemaPattern : string) : string; override;
    function RowsAffected(cursor: TSQLCursor): TRowsCount; override;
    function RefreshLastInsertID(Query : TCustomSQLQuery; Field : TField): Boolean; override;
    // New methods
    procedure checkerror(const aerror: integer);
    function stringsquery(const asql: string): TArrayStringArray;
    procedure execsql(const asql: string);
  public
    constructor Create(AOwner : TComponent); override;
    procedure GetFieldNames(const TableName : string; List :  TStrings); override;
    function GetConnectionInfo(InfoType:TConnInfoType): string; override;
    procedure CreateDB; override;
    procedure DropDB; override;
    function GetInsertID: int64;
    // See http://www.sqlite.org/c3ref/create_collation.html for detailed information
    // If eTextRep=0 a default UTF-8 compare function is used (UTF8CompareCallback)
    // Warning: UTF8CompareCallback needs a wide string manager on Linux such as cwstring
    // Warning: CollationName has to be a UTF-8 string
    procedure CreateCollation(const CollationName: string; eTextRep: integer; Arg: Pointer=nil; Compare: xCompare=nil);
    procedure LoadExtension(LibraryFile: string);
  published
    property ClientLibrary: string read FClientLibrary write FClientLibrary;
  end;

  { TSQLite3DynConnectionDef }

  TSQLite3DynConnectionDef = class(TConnectionDef)
    class function TypeName: string; override;
    class function ConnectionClass: TSQLConnectionClass; override;
    class function Description: string; override;
    class Function DefaultLibraryName : String; override;
    class Function LoadFunction : TLibraryLoadFunction; override;
    class Function UnLoadFunction : TLibraryUnLoadFunction; override;
    class function LoadedLibraryName: string; override;
  end;

procedure Register;

Var
  SQLiteLibraryName : String absolute sqlite3dyn.SQLiteDefaultLibrary deprecated 'use sqlite3dyn.SQLiteDefaultLibrary instead';

implementation

uses
  dbconst, sysutils, dateutils, FmtBCD;

{$IF NOT DECLARED(JulianEpoch)} // sysutils/datih.inc
const
  JulianEpoch = TDateTime(-2415018.5); // "julian day 0" is January 1, 4713 BC 12:00AM
{$ENDIF}

type

 TStorageType = (stNone,stInteger,stFloat,stText,stBlob,stNull);

 TSQLite3Cursor = class(tsqlcursor)
  private
   fhandle : psqlite3;
   fconnection: TSQLite3DynConnection;
   fstatement: psqlite3_stmt;
   ftail: pchar;
   fstate: integer;
   fparambinding: array of Integer;
   procedure checkerror(const aerror: integer);
   procedure bindparams(AParams : TParams);
   Procedure Prepare(Buf : String; AParams : TParams);
   Procedure UnPrepare;
   Procedure Execute;
   Function Fetch : Boolean;
 public
   RowsAffected : Largeint;
 end;

procedure freebindstring(astring: pointer); cdecl;
begin
  StrDispose(AString);
end;

procedure TSQLite3Cursor.checkerror(const aerror: integer);

Var
  S : String;

begin
 if (aerror<>sqlite_ok) then
   begin
   S:=strpas(sqlite3_errmsg(fhandle));
   DatabaseError(S);
   end;
end;

Procedure TSQLite3Cursor.bindparams(AParams : TParams);

  Function PCharStr(Const S : String) : PChar;

  begin
    Result:=StrAlloc(Length(S)+1);
    If (Result<>Nil) then
      StrPCopy(Result,S);
  end;

Var
  I : Integer;
  P : TParam;
  str1: string;
  wstr1: widestring;

begin
  for I:=1 to high(fparambinding)+1 do
    begin
    P:=AParams[fparambinding[I-1]];
    if P.IsNull then
      checkerror(sqlite3_bind_null(fstatement,I))
    else
      case P.DataType of
        ftInteger,
        ftAutoInc,
        ftSmallint: checkerror(sqlite3_bind_int(fstatement,I,P.AsInteger));
        ftWord:     checkerror(sqlite3_bind_int(fstatement,I,P.AsWord));
        ftBoolean:  checkerror(sqlite3_bind_int(fstatement,I,ord(P.AsBoolean)));
        ftLargeint: checkerror(sqlite3_bind_int64(fstatement,I,P.AsLargeint));
        ftBcd,
        ftFloat,
        ftCurrency: checkerror(sqlite3_bind_double(fstatement, I, P.AsFloat));
        ftDateTime,
        ftDate,
        ftTime:     checkerror(sqlite3_bind_double(fstatement, I, P.AsFloat - JulianEpoch));
        ftFMTBcd:
                begin
                str1:=BCDToStr(P.AsFMTBCD, Fconnection.FSQLFormatSettings);
                checkerror(sqlite3_bind_text(fstatement, I, PChar(str1), length(str1), sqlite3_destructor_type(SQLITE_TRANSIENT)));
                end;
        ftString,
        ftFixedChar,
        ftMemo: begin // According to SQLite documentation, CLOB's (ftMemo) have the Text affinity
                str1:= p.asstring;
                checkerror(sqlite3_bind_text(fstatement,I,pcharstr(str1), length(str1),@freebindstring));
                end;
        ftBytes,
        ftVarBytes,
        ftBlob: begin
                str1:= P.asstring;
                checkerror(sqlite3_bind_blob(fstatement,I,pcharstr(str1), length(str1),@freebindstring));
                end;
        ftWideString, ftFixedWideChar, ftWideMemo:
        begin
          wstr1:=P.AsWideString;
          checkerror(sqlite3_bind_text16(fstatement,I, PWideChar(wstr1), length(wstr1)*sizeof(WideChar), sqlite3_destructor_type(SQLITE_TRANSIENT)));
        end
      else
        DatabaseErrorFmt(SUnsupportedParameter, [Fieldtypenames[P.DataType], Self]);
      end; { Case }
    end;
end;

Procedure TSQLite3Cursor.Prepare(Buf : String; AParams : TParams);

begin
  if assigned(AParams) and (AParams.Count > 0) then
    Buf := AParams.ParseSQL(Buf,false,false,false,psInterbase,fparambinding);
  if (detActualSQL in fconnection.LogEvents) then
    fconnection.Log(detActualSQL,Buf);
  checkerror(sqlite3_prepare(fhandle,pchar(Buf),length(Buf),@fstatement,@ftail));
  FPrepared:=True;
end;

Procedure TSQLite3Cursor.UnPrepare;

begin
  sqlite3_finalize(fstatement); // No check.
  FPrepared:=False;
end;

Procedure TSQLite3Cursor.Execute;

//var
// wo1: word;

begin
{$ifdef i386}
  wo1:= get8087cw;
  set8087cw(wo1 or $1f);             //mask exceptions, Sqlite3 has overflow
  Try  // Why do people always forget this ??
{$endif}
    fstate:= sqlite3_step(fstatement);
{$ifdef i386}
  finally
    set8087cw(wo1);                    //restore
  end;
{$endif}
  if (fstate<=sqliteerrormax) then
    checkerror(sqlite3_reset(fstatement));
  FSelectable :=sqlite3_column_count(fstatement)>0;
  RowsAffected:=sqlite3_changes(fhandle);
  if (fstate=sqlite_row) then
    fstate:= sqliteerrormax; //first row
end;

Function TSQLite3Cursor.Fetch : Boolean;

begin
  if (fstate=sqliteerrormax) then
    fstate:=sqlite_row //first row;
  else if (fstate=sqlite_row) then
    begin
    fstate:=sqlite3_step(fstatement);
    if (fstate<=sqliteerrormax) then
      checkerror(sqlite3_reset(fstatement));  //right error returned??
    end;
  result:=(fstate=sqlite_row);
end;

{ TSQLite3DynConnection }

constructor TSQLite3DynConnection.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FConnOptions := [sqEscapeRepeat, sqEscapeSlash, sqImplicitTransaction, sqLastInsertID];
  FieldNameQuoteChars:=DoubleQuotes;
  FClientLibrary := '';
end;

procedure TSQLite3DynConnection.LoadBlobIntoBuffer(FieldDef: TFieldDef; ABlobBuf: PBufBlobField; cursor: TSQLCursor; ATransaction : TSQLTransaction);

var
 int1: integer;
 st: psqlite3_stmt;
 fnum: integer;
 p1: Pointer;

begin
  st:=TSQLite3Cursor(cursor).fstatement;
  fnum:= FieldDef.fieldno - 1;

  case FieldDef.DataType of
    ftWideMemo:
      begin
      p1 := sqlite3_column_text16(st,fnum);
      int1 := sqlite3_column_bytes16(st,fnum);
      end;
    ftMemo:
      begin
      p1 := sqlite3_column_text(st,fnum);
      int1 := sqlite3_column_bytes(st,fnum);
      end;
    else //ftBlob
      begin
      p1 := sqlite3_column_blob(st,fnum);
      int1 := sqlite3_column_bytes(st,fnum);
      end;
  end;

  ReAllocMem(ABlobBuf^.BlobBuffer^.Buffer, int1);
  if int1 > 0 then
    move(p1^, ABlobBuf^.BlobBuffer^.Buffer^, int1);
  ABlobBuf^.BlobBuffer^.Size := int1;
end;

function TSQLite3DynConnection.AllocateTransactionHandle: TSQLHandle;
begin
 result:= tsqlhandle.create;
end;

function TSQLite3DynConnection.AllocateCursorHandle: TSQLCursor;

Var
  Res : TSQLite3Cursor;

begin
  Res:= TSQLite3Cursor.create;
  Res.fconnection:=Self;
  Result:=Res;
end;

procedure TSQLite3DynConnection.DeAllocateCursorHandle(var cursor: TSQLCursor);
begin
  freeandnil(cursor);
end;

function TSQLite3DynConnection.StrToStatementType(s: string): TStatementType;
begin
  S:=Lowercase(s);
  if s = 'pragma' then exit(stSelect);
  result := inherited StrToStatementType(s);
end;

procedure TSQLite3DynConnection.PrepareStatement(cursor: TSQLCursor;
               ATransaction: TSQLTransaction; buf: string; AParams: TParams);
begin
  TSQLite3Cursor(cursor).fhandle:=self.fhandle;
  TSQLite3Cursor(cursor).Prepare(Buf,AParams);
end;

procedure TSQLite3DynConnection.UnPrepareStatement(cursor: TSQLCursor);

begin
  TSQLite3Cursor(cursor).UnPrepare;
  TSQLite3Cursor(cursor).fhandle:=nil;
end;


Type
  TFieldMap = Record
    N : String;
    T : TFieldType;
  end;

Const
  FieldMapCount = 28;
  FieldMap : Array [1..FieldMapCount] of TFieldMap = (
   (n:'INT'; t: ftInteger),
   (n:'LARGEINT'; t:ftLargeInt),
   (n:'BIGINT'; t:ftLargeInt),
   (n:'SMALLINT'; t: ftSmallint),
   (n:'TINYINT'; t: ftSmallint),
   (n:'WORD'; t: ftWord),
   (n:'BOOLEAN'; t: ftBoolean),
   (n:'REAL'; t: ftFloat),
   (n:'FLOAT'; t: ftFloat),
   (n:'DOUBLE'; t: ftFloat),
   (n:'TIMESTAMP'; t: ftDateTime),
   (n:'DATETIME'; t: ftDateTime), // MUST be before date
   (n:'DATE'; t: ftDate),
   (n:'TIME'; t: ftTime),
   (n:'CURRENCY'; t: ftCurrency),
   (n:'MONEY'; t: ftCurrency),
   (n:'VARCHAR'; t: ftString),
   (n:'CHAR'; t: ftFixedChar),
   (n:'NUMERIC'; t: ftBCD),
   (n:'DECIMAL'; t: ftBCD),
   (n:'TEXT'; t: ftMemo),
   (n:'CLOB'; t: ftMemo),
   (n:'BLOB'; t: ftBlob),
   (n:'NCHAR'; t: ftFixedWideChar),
   (n:'NVARCHAR'; t: ftWideString),
   (n:'NCLOB'; t: ftWideMemo),
   (n:'VARBINARY'; t: ftVarBytes),
   (n:'BINARY'; t: ftBytes)
{ Template:
  (n:''; t: ft)
}
  );

procedure TSQLite3DynConnection.AddFieldDefs(cursor: TSQLCursor; FieldDefs: TFieldDefs);
var
 i, fi : integer;
 FN, FD, PrimaryKeyFields : string;
 ft1   : TFieldType;
 size1, size2 : integer;
 st    : psqlite3_stmt;

 function GetPrimaryKeyFields: string;
 var IndexDefs: TServerIndexDefs;
     i: integer;
 begin
   if FieldDefs.Dataset is TSQLQuery then
   begin
     IndexDefs := (FieldDefs.DataSet as TSQLQuery).ServerIndexDefs;
     for i:=IndexDefs.Count-1 downto 0 do
       if ixPrimary in IndexDefs[i].Options then
       begin
         Result := IndexDefs[i].Fields;
         Exit;
       end;
   end;
   Result := '';
 end;

 function ExtractPrecisionAndScale(decltype: string; var precision, scale: integer): boolean;
 var p: integer;
 begin
   p:=pos('(', decltype);
   Result:=p>0;
   if not Result then Exit;
   System.Delete(decltype,1,p);
   p:=pos(')', decltype);
   Result:=p>0;
   if not Result then Exit;
   decltype:=copy(decltype,1,p-1);
   p:=pos(',', decltype);
   if p=0 then
   begin
     precision:=StrToIntDef(decltype, precision);
     scale:=0;
   end
   else
   begin
     precision:=StrToIntDef(copy(decltype,1,p-1), precision);
     scale:=StrToIntDef(copy(decltype,p+1,length(decltype)-p), scale);
   end;
 end;

begin
  PrimaryKeyFields := GetPrimaryKeyFields;
  st:=TSQLite3Cursor(cursor).fstatement;
  for i:= 0 to sqlite3_column_count(st) - 1 do
    begin
    FN:=sqlite3_column_name(st,i);
    FD:=uppercase(sqlite3_column_decltype(st,i));
    ft1:= ftUnknown;
    size1:= 0;
    for fi := 1 to FieldMapCount do if pos(FieldMap[fi].N,FD)=1 then
      begin
      ft1:=FieldMap[fi].t;
      break;
      end;
    // Column declared as INTEGER PRIMARY KEY [AUTOINCREMENT] becomes ROWID for given table
    // declared data type must be INTEGER (not INT, BIGINT, NUMERIC etc.)
    if (FD='INTEGER') and SameText(FN, PrimaryKeyFields) then
      ft1:=ftAutoInc;
    // In case of an empty fieldtype (FD='', which is allowed and used in calculated
    // columns (aggregates) and by pragma-statements) or an unknown fieldtype,
    // use the field's affinity:
    if ft1=ftUnknown then
      case TStorageType(sqlite3_column_type(st,i)) of
        stInteger: ft1:=ftLargeInt;
        stFloat:   ft1:=ftFloat;
        stBlob:    ft1:=ftBlob;
        else       ft1:=ftString;
      end;
    // handle some specials.
    size1:=0;
    case ft1 of
      ftString,
      ftFixedChar,
      ftFixedWideChar,
      ftWideString,
      ftBytes,
      ftVarBytes:
               begin
                 size1 := 255; //sql: if length is omitted then length is 1
                 size2 := 0;
                 ExtractPrecisionAndScale(FD, size1, size2);
                 if size1 > MaxSmallint then size1 := MaxSmallint;
               end;
      ftBCD:   begin
                 size2 := MaxBCDPrecision; //sql: if a precision is omitted, then use implementation-defined
                 size1 := 0;               //sql: if a scale is omitted then scale is 0
                 ExtractPrecisionAndScale(FD, size2, size1);
                 if (size2<=18) and (size1=0) then
                   ft1:=ftLargeInt
                 else if (size2-size1>MaxBCDPrecision-MaxBCDScale) or (size1>MaxBCDScale) then
                   ft1:=ftFmtBCD;
               end;
      ftUnknown : DatabaseErrorFmt('Unknown or unsupported data type %s of column %s', [FD, FN]);
    end; // Case
    FieldDefs.Add(FieldDefs.MakeNameUnique(FN),ft1,size1,false,i+1);
    end;
end;

procedure TSQLite3DynConnection.Execute(cursor: TSQLCursor;
  atransaction: tSQLtransaction; AParams: TParams);
var
 SC : TSQLite3Cursor;

begin
  SC:=TSQLite3Cursor(cursor);
  checkerror(sqlite3_reset(sc.fstatement));
  If (AParams<>Nil) and (AParams.count > 0) then
    SC.BindParams(AParams);
  If LogEvent(detParamValue) then
    LogParams(AParams);
  SC.Execute;
end;

Function NextWord(Var S : ShortString; Sep : Char) : String;

Var
  P : Integer;

begin
  P:=Pos(Sep,S);
  If (P=0) then
    P:=Length(S)+1;
  Result:=Copy(S,1,P-1);
  Delete(S,1,P);
end;

// Parses string-formatted date into TDateTime value
// Expected format: '2013-12-31 ' (without ')
Function ParseSQLiteDate(S : ShortString) : TDateTime;

Var
  Year, Month, Day : Integer;

begin
  Result:=0;
  If TryStrToInt(NextWord(S,'-'),Year) then
    if TryStrToInt(NextWord(S,'-'),Month) then
      if TryStrToInt(NextWord(S,' '),Day) then
        Result:=EncodeDate(Year,Month,Day);
end;

// Parses string-formatted time into TDateTime value
// Expected formats
// 23:59
// 23:59:59
// 23:59:59.999
Function ParseSQLiteTime(S : ShortString; Interval: boolean) : TDateTime;

Var
  Hour, Min, Sec, MSec : Integer;

begin
  Result:=0;
  If TryStrToInt(NextWord(S,':'),Hour) then
    if TryStrToInt(NextWord(S,':'),Min) then
    begin
      if TryStrToInt(NextWord(S,'.'),Sec) then
        // 23:59:59 or 23:59:59.999
        MSec:=StrToIntDef(S,0)
      else // 23:59
      begin
        Sec:=0;
        MSec:=0;
      end;
      if Interval then
        Result:=EncodeTimeInterval(Hour,Min,Sec,MSec)
      else
        Result:=EncodeTime(Hour,Min,Sec,MSec);
    end;
end;

// Parses string-formatted date/time into TDateTime value
Function ParseSQLiteDateTime(S : String) : TDateTime;

var
  P : Integer;
  DS,TS : ShortString;

begin
  DS:='';
  TS:='';
  P:=Pos('T',S); //allow e.g. YYYY-MM-DDTHH:MM
  if P=0 then
    P:=Pos(' ',S); //allow e.g. YYYY-MM-DD HH:MM
  If (P<>0) then
    begin
    DS:=Copy(S,1,P-1);
    TS:=S;
    Delete(TS,1,P);
    end
  else
    begin
    If (Pos('-',S)<>0) then
      DS:=S
    else if (Pos(':',S)<>0) then
      TS:=S;
    end;
  Result:=ComposeDateTime(ParseSQLiteDate(DS),ParseSQLiteTime(TS,False));
end;

function TSQLite3DynConnection.LoadField(cursor : TSQLCursor; FieldDef : TFieldDef; buffer : pointer; out CreateBlob : boolean) : boolean;

var
 st1: TStorageType;
 fnum: integer;
 str1: string;
 int1 : integer;
 bcd: tBCD;
 bcdstr: FmtBCDStringtype;
 st    : psqlite3_stmt;

begin
  st:=TSQLite3Cursor(cursor).fstatement;
  fnum:= FieldDef.fieldno - 1;
  st1:= TStorageType(sqlite3_column_type(st,fnum));
  CreateBlob:=false;
  result:= st1 <> stnull;
  if Not result then
    Exit;
  case FieldDef.DataType of
    ftAutoInc,
    ftInteger  : pinteger(buffer)^  := sqlite3_column_int(st,fnum);
    ftSmallInt : psmallint(buffer)^ := sqlite3_column_int(st,fnum);
    ftWord     : pword(buffer)^     := sqlite3_column_int(st,fnum);
    ftBoolean  : pwordbool(buffer)^ := sqlite3_column_int(st,fnum)<>0;
    ftLargeInt : PInt64(buffer)^:= sqlite3_column_int64(st,fnum);
    ftBCD      : PCurrency(buffer)^:= FloattoCurr(sqlite3_column_double(st,fnum));
    ftFloat,
    ftCurrency : pdouble(buffer)^:= sqlite3_column_double(st,fnum);
    ftDateTime,
    ftDate,
    ftTime:  if st1 = sttext then
               begin { Stored as string }
               setlength(str1,sqlite3_column_bytes(st,fnum));
               move(sqlite3_column_text(st,fnum)^,str1[1],length(str1));
               case FieldDef.datatype of
                 ftDateTime: PDateTime(Buffer)^:=ParseSqliteDateTime(str1);
                 ftDate    : PDateTime(Buffer)^:=ParseSqliteDate(str1);
                 ftTime    : PDateTime(Buffer)^:=ParseSqliteTime(str1,true);
               end; {case}
               end
             else
               begin { Assume stored as double }
               PDateTime(buffer)^ := sqlite3_column_double(st,fnum);
               if PDateTime(buffer)^ > 1721059.5 {Julian 01/01/0000} then
                  PDateTime(buffer)^ := PDateTime(buffer)^ + JulianEpoch; //backward compatibility hack
               end;
    ftFixedChar,
    ftString: begin
              int1:= sqlite3_column_bytes(st,fnum);
              if int1>FieldDef.Size then
                int1:=FieldDef.Size;
              if int1 > 0 then
                 move(sqlite3_column_text(st,fnum)^,buffer^,int1);
              PAnsiChar(buffer + int1)^ := #0;
              end;
    ftFmtBCD: begin
              int1:= sqlite3_column_bytes(st,fnum);
              if (int1 > 0) and (int1 <= MAXFMTBcdFractionSize) then
                begin
                SetLength(bcdstr,int1);
                move(sqlite3_column_text(st,fnum)^,bcdstr[1],int1);
                // sqlite always uses the point as decimal-point
                if not TryStrToBCD(bcdstr,bcd,FSQLFormatSettings) then
                  // sqlite does the same, if the value can't be interpreted as a
                  // number in sqlite3_column_int, return 0
                  bcd := 0;
                end
              else
                bcd := 0;
              pBCD(buffer)^:= bcd;
              end;
    ftFixedWideChar,
    ftWideString:
      begin
      int1 := sqlite3_column_bytes16(st,fnum); //The value returned does not include the zero terminator at the end of the string
      if int1>FieldDef.Size*2 then
        int1:=FieldDef.Size*2;
      if int1 > 0 then
        move(sqlite3_column_text16(st,fnum)^, buffer^, int1); //Strings returned by sqlite3_column_text() and sqlite3_column_text16(), even empty strings, are always zero terminated.
      PWideChar(buffer + int1)^ := #0;
      end;
    ftVarBytes,
    ftBytes:
      begin
      int1 := sqlite3_column_bytes(st,fnum);
      if int1 > FieldDef.Size then
        int1 := FieldDef.Size;
      if FieldDef.DataType = ftVarBytes then
      begin
        PWord(buffer)^ := int1;
        inc(buffer, sizeof(Word));
      end;
      if int1 > 0 then
        move(sqlite3_column_blob(st,fnum)^, buffer^, int1);
      end;
    ftWideMemo,
    ftMemo,
    ftBlob: CreateBlob:=True;
  else { Case }
   result:= false; // unknown
  end; { Case }
end;

function TSQLite3DynConnection.Fetch(cursor: TSQLCursor): boolean;

begin
  Result:=TSQLite3Cursor(cursor).Fetch;
end;

procedure TSQLite3DynConnection.FreeFldBuffers(cursor: TSQLCursor);
begin
 //dummy
end;

function TSQLite3DynConnection.GetTransactionHandle(trans: TSQLHandle): pointer;
begin
 result:= nil;
end;

function TSQLite3DynConnection.Commit(trans: TSQLHandle): boolean;
begin
  execsql('COMMIT');
  result:= true;
end;

function TSQLite3DynConnection.RollBack(trans: TSQLHandle): boolean;
begin
  execsql('ROLLBACK');
  result:= true;
end;

function TSQLite3DynConnection.StartDBTransaction(trans: TSQLHandle; aParams: string): boolean;
begin
  execsql('BEGIN');
  result:= true;
end;

procedure TSQLite3DynConnection.CommitRetaining(trans: TSQLHandle);
begin
  commit(trans);
  execsql('BEGIN');
end;

procedure TSQLite3DynConnection.RollBackRetaining(trans: TSQLHandle);
begin
  rollback(trans);
  execsql('BEGIN');
end;

procedure TSQLite3DynConnection.DoInternalConnect;
var
  filename: ansistring;
begin
  Inherited;
  if DatabaseName = '' then
    DatabaseError(SErrNoDatabaseName,self);
  InitializeSQLite(FClientLibrary);
  filename := DatabaseName;
  checkerror(sqlite3_open(PAnsiChar(filename),@fhandle));
  if (Length(Password)>0) and assigned(sqlite3_key) then
    checkerror(sqlite3_key(fhandle,PChar(Password),StrLen(PChar(Password))));
  if Params.IndexOfName('foreign_keys') <> -1 then
    execsql('PRAGMA foreign_keys =  '+Params.Values['foreign_keys']);
end;

procedure TSQLite3DynConnection.DoInternalDisconnect;

begin
  Inherited;
  if fhandle <> nil then
    begin
    checkerror(sqlite3_close(fhandle));
    fhandle:= nil;
    ReleaseSQLite;
    end;
end;

function TSQLite3DynConnection.GetHandle: pointer;
begin
  result:= fhandle;
end;

procedure TSQLite3DynConnection.checkerror(const aerror: integer);

Var
  S : String;

begin
 if (aerror<>sqlite_ok) then
   begin
   S:=strpas(sqlite3_errmsg(fhandle));
   DatabaseError(S,Self);
   end;
end;

procedure TSQLite3DynConnection.execsql(const asql: string);
var
 err  : pchar;
 str1 : string;
 res  : integer;
begin
 err:= nil;
 Res := sqlite3_exec(fhandle,pchar(asql),nil,nil,@err);
 if err <> nil then
   begin
   str1:= strpas(err);
   sqlite3_free(err);
   end;
 if (res<>sqlite_ok) then
   databaseerror(str1);
end;

function execcallback(adata: pointer; ncols: longint; //adata = PStringArray
                avalues: PPchar; anames: PPchar):longint; cdecl;
var
  P : PStringArray;
  i : integer;

begin
  P:=PStringArray(adata);
  SetLength(P^,ncols);
  for i:= 0 to ncols - 1 do
    P^[i]:= strPas(avalues[i]);
  result:= 0;
end;

function execscallback(adata: pointer; ncols: longint; //adata = PArrayStringArray
                avalues: PPchar; anames: PPchar):longint; cdecl;
var
 I,N : integer;
 PP : PArrayStringArray;
 p  : PStringArray;

begin
 PP:=PArrayStringArray(adata);
 N:=high(PP^); // Length-1;
 setlength(PP^,N+2); // increase with 1;
 p:= @(PP^[N+1]); // newly added array, fill with data.
 setlength(p^,ncols);
 for i:= 0 to ncols - 1 do
   p^[i]:= strPas(avalues[i]);
 result:= 0;
end;

function TSQLite3DynConnection.stringsquery(const asql: string): TArrayStringArray;
begin
  SetLength(result,0);
  checkerror(sqlite3_exec(fhandle,pchar(asql),@execscallback,@result,nil));
end;

function TSQLite3DynConnection.GetSchemaInfoSQL(SchemaType: TSchemaType;
  SchemaObjectName, SchemaPattern: string): string;

begin
  case SchemaType of
    stTables     : result := 'select name as table_name from sqlite_master where type = ''table'' order by 1';
    stSysTables  : result := 'select ''sqlite_master'' as table_name';
    stColumns    : result := 'pragma table_info(''' + (SchemaObjectName) + ''')';
  else
    DatabaseError(SMetadataUnavailable)
  end; {case}
end;

procedure TSQLite3DynConnection.UpdateIndexDefs(IndexDefs: TIndexDefs; TableName: string);
var
  artableinfo, arindexlist, arindexinfo: TArrayStringArray;
  il,ii: integer;
  IndexName: string;
  IndexOptions: TIndexOptions;
  PKFields, IXFields: TStrings;

  function CheckPKFields:boolean;
  var i: integer;
  begin
    Result:=false;
    if IXFields.Count<>PKFields.Count then Exit;
    for i:=0 to IXFields.Count-1 do
      if PKFields.IndexOf(IXFields[i])<0 then Exit;
    Result:=true;
    PKFields.Clear;
  end;

begin
  PKFields:=TStringList.Create;
  PKFields.Delimiter:=';';
  IXFields:=TStringList.Create;
  IXFields.Delimiter:=';';

  //primary key fields; 5th column "pk" is zero for columns that are not part of PK
  artableinfo := stringsquery('PRAGMA table_info('+TableName+');');
  for ii:=low(artableinfo) to high(artableinfo) do
    if (high(artableinfo[ii]) >= 5) and (artableinfo[ii][5] >= '1') then
      PKFields.Add(artableinfo[ii][1]);

  //list of all table indexes
  arindexlist:=stringsquery('PRAGMA index_list('+TableName+');');
  for il:=low(arindexlist) to high(arindexlist) do
    begin
    IndexName:=arindexlist[il][1];
    if arindexlist[il][2]='1' then
      IndexOptions:=[ixUnique]
    else
      IndexOptions:=[];
    //list of columns in given index
    arindexinfo:=stringsquery('PRAGMA index_info('+IndexName+');');
    IXFields.Clear;
    for ii:=low(arindexinfo) to high(arindexinfo) do
      IXFields.Add(arindexinfo[ii][2]);

    if CheckPKFields then IndexOptions:=IndexOptions+[ixPrimary];

    IndexDefs.Add(IndexName, IXFields.DelimitedText, IndexOptions);
    end;

  if PKFields.Count > 0 then //in special case for INTEGER PRIMARY KEY column, unique index is not created
    IndexDefs.Add('$PRIMARY_KEY$', PKFields.DelimitedText, [ixPrimary,ixUnique]);

  PKFields.Free;
  IXFields.Free;
end;

function TSQLite3DynConnection.RowsAffected(cursor: TSQLCursor): TRowsCount;
begin
  if assigned(cursor) then
    Result := (cursor as TSQLite3Cursor).RowsAffected
  else
    Result := -1;
end;

function TSQLite3DynConnection.RefreshLastInsertID(Query: TCustomSQLQuery; Field: TField): Boolean;
begin
  Field.AsLargeInt:=GetInsertID;
  Result:=True;
end;

function TSQLite3DynConnection.GetInsertID: int64;
begin
 result:= sqlite3_last_insert_rowid(fhandle);
end;

procedure TSQLite3DynConnection.GetFieldNames(const TableName: string;
  List: TStrings);
begin
  GetDBInfo(stColumns,TableName,'name',List);
end;

function TSQLite3DynConnection.GetConnectionInfo(InfoType: TConnInfoType): string;
begin
  Result:='';
  try
    InitializeSQLite;
    case InfoType of
      citServerType:
        Result:=TSQLite3DynConnectionDef.TypeName;
      citServerVersion,
      citClientVersion:
        Result:=inttostr(sqlite3_libversion_number());
      citServerVersionString:
        Result:=sqlite3_libversion();
      citClientName:
        Result:=TSQLite3DynConnectionDef.LoadedLibraryName;
    else
      Result:=inherited GetConnectionInfo(InfoType);
    end;
  finally
    ReleaseSqlite;
  end;
end;

procedure TSQLite3DynConnection.CreateDB;
var filename: ansistring;
begin
  CheckDisConnected;
  try
    InitializeSQLite;
    try
      filename := DatabaseName;
      checkerror(sqlite3_open(PAnsiChar(filename),@fhandle));
    finally
      sqlite3_close(fhandle);
      fhandle := nil;
    end;
  finally
    ReleaseSqlite;
  end;
end;

procedure TSQLite3DynConnection.DropDB;
begin
  CheckDisConnected;
  DeleteFile(DatabaseName);
end;

function UTF8CompareCallback(user: pointer; len1: longint; data1: pointer; len2: longint; data2: pointer): longint; cdecl;
var S1, S2: AnsiString;
begin
  SetString(S1, data1, len1);
  SetString(S2, data2, len2);
  Result := UnicodeCompareStr(UTF8Decode(S1), UTF8Decode(S2));
end;

procedure TSQLite3DynConnection.CreateCollation(const CollationName: string;
  eTextRep: integer; Arg: Pointer; Compare: xCompare);
begin
  if eTextRep = 0 then
  begin
    eTextRep := SQLITE_UTF8;
    Compare := @UTF8CompareCallback;
  end;
  CheckConnected;
  CheckError(sqlite3_create_collation(fhandle, PChar(CollationName), eTextRep, Arg, Compare));
end;

procedure TSQLite3DynConnection.LoadExtension(LibraryFile: string);
var
  LoadResult: integer;
begin
  CheckConnected; //Apparently we need a connection before we can load extensions.
  LoadResult:=SQLITE_ERROR; //Default to failed
  try
    LoadResult:=sqlite3_enable_load_extension(fhandle, 1); //Make sure we are allowed to load
    if LoadResult=SQLITE_OK then
      begin
      LoadResult:=sqlite3_load_extension(fhandle, PChar(LibraryFile), nil, nil); //Actually load extension
      if LoadResult=SQLITE_ERROR then
        begin
        DatabaseError('LoadExtension: failed to load SQLite extension (SQLite returned an error while loading).',Self);
        end;
      end
      else
      begin
        DatabaseError('LoadExtension: failed to load SQLite extension (SQLite returned an error while enabling extensions).',Self);
      end;
  except
    DatabaseError('LoadExtension: failed to load SQLite extension.',Self)
  end;
end;


{ TSQLite3DynConnectionDef }

class function TSQLite3DynConnectionDef.TypeName: string;
begin
  Result := 'SQLite3';
end;

class function TSQLite3DynConnectionDef.ConnectionClass: TSQLConnectionClass;
begin
  Result := TSQLite3DynConnection;
end;

class function TSQLite3DynConnectionDef.Description: string;
begin
  Result := 'Connect to a SQLite3 database directly via the client library';
end;

class function TSQLite3DynConnectionDef.DefaultLibraryName: string;
begin
  Result := SQLiteDefaultLibrary;
end;

class function TSQLite3DynConnectionDef.LoadedLibraryName: string;
begin
  Result := SQLiteLoadedLibrary;
end;

class function TSQLite3DynConnectionDef.LoadFunction: TLibraryLoadFunction;
begin
  Result:=@InitializeSQLiteANSI; //the function taking the filename argument
end;

class function TSQLite3DynConnectionDef.UnLoadFunction: TLibraryUnLoadFunction;
begin
  Result:=@ReleaseSQLite;
end;

procedure Register;
begin
  {$I sqlite3dynconnection_icon.lrs}
  RegisterComponents('SQLdb',[TSQLite3DynConnection]);
end;


initialization
  RegisterConnection(TSQLite3DynConnectionDef);

finalization
  UnRegisterConnection(TSQLite3DynConnectionDef);

end.
{$ENDIF}
