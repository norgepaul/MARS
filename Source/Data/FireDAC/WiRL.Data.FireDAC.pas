{******************************************************************************}
{                                                                              }
{       WiRL: RESTful Library for Delphi                                       }
{                                                                              }
{       Copyright (c) 2015-2017 WiRL Team                                      }
{                                                                              }
{       https://github.com/delphi-blocks/WiRL                                  }
{                                                                              }
{******************************************************************************}
unit WiRL.Data.FireDAC;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,

  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf,
  FireDAC.Phys.Intf, FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Stan.Async,
  FireDAC.Phys, Data.DB, FireDAC.Comp.Client, FireDAC.FMXUI.Wait,
  FireDAC.Stan.StorageXML, FireDAC.Stan.StorageJSON, FireDAC.Stan.StorageBin,
  FireDAC.Comp.UI, FireDAC.DApt, FireDACJSONReflect,

  WiRL.Core.JSON,
  WiRL.Core.Registry,
  WiRL.Core.Classes,
  WiRL.Core.Request,
  WiRL.Core.Response,
  WiRL.Core.Application,
  WiRL.Core.Declarations,
  WiRL.Core.Attributes,
  WiRL.http.Accept.MediaType,
  WiRL.Core.Auth.Context,
  WiRL.Core.URL;

type
  ConnectionAttribute = class(TCustomAttribute)
  private
    FConnectionDefName: string;
  public
    constructor Create(AConnectionDefName: string);
    property ConnectionDefName: string read FConnectionDefName;
  end;

  SQLStatementAttribute = class(TCustomAttribute)
  private
    FName: string;
    FSQLStatement: string;
  public
    constructor Create(const AName, ASQLStatement: string);
    property Name: string read FName;
    property SQLStatement: string read FSQLStatement;
  end;

  TWiRLFDDatasetResource = class
  private
    FConnection: TFDConnection;
    FStatements: TDictionary<string, string>;
    FOwnsConnection: Boolean;
  protected
    [Context] Request: TWiRLRequest;

    procedure SetupConnection; virtual;
    procedure TeardownConnection; virtual;
    procedure CheckConnection; virtual;

    procedure SetupStatements; virtual;

    procedure AfterOpenDataSet(ADataSet: TFDCustomQuery); virtual;
    procedure BeforeOpenDataSet(ADataSet: TFDCustomQuery); virtual;
    function ReadDataSet(const ADataSetName, ASQLStatement: string; const AAutoOpen: Boolean = True): TFDCustomQuery; virtual;

    procedure ApplyUpdates(ADeltas: TFDJSONDeltas;
      AOnApplyUpdates: TProc<string, Integer, IFDJSONDeltasApplyUpdates> = nil); virtual;

    property Connection: TFDConnection read FConnection write FConnection;
    property OwnsConnection: Boolean read FOwnsConnection write FOwnsConnection;
    property Statements: TDictionary<string, string> read FStatements;
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;

    [GET][Produces(TMediaType.APPLICATION_JSON)]
    function Retrieve: TArray<TFDCustomQuery>; virtual;

    [POST][Produces(TMediaType.APPLICATION_JSON)]
    [Consumes(TMediaType.APPLICATION_JSON)]
    function Update: string; virtual;
  end;

  function CreateConnectionByDefName(const AConnectionDefName: string): TFDConnection;

implementation

uses
  System.Rtti,
  WiRL.Core.Exceptions,
  WiRL.Core.Utils,
  WiRL.Data.Utils,
  WiRL.Rtti.Utils;

function CreateConnectionByDefName(const AConnectionDefName: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.ConnectionDefName := AConnectionDefName;
  except
    Result.Free;
    raise;
  end;
end;

{ TDataResource }

procedure TWiRLFDDatasetResource.AfterConstruction;
begin
  inherited;
  FStatements := TDictionary<string, string>.Create;
  FOwnsConnection := False;

  SetupConnection;
end;

procedure TWiRLFDDatasetResource.AfterOpenDataSet(ADataSet: TFDCustomQuery);
begin

end;

procedure TWiRLFDDatasetResource.ApplyUpdates(
  ADeltas: TFDJSONDeltas;
  AOnApplyUpdates: TProc<string, Integer, IFDJSONDeltasApplyUpdates>);
var
  LApplyUpdates: IFDJSONDeltasApplyUpdates;
  LIndex: Integer;
  LDelta: TPair<string, TFDMemTable>;
  LStatement: string;
  LDataSet: TFDCustomQuery;
  LApplyResult: Integer;
begin
  LApplyUpdates := TFDJSONDeltasApplyUpdates.Create(ADeltas);
  try
    for LIndex := 0 to TFDJSONDeltasReader.GetListCount(ADeltas) - 1 do
    begin
      LDelta := TFDJSONDeltasReader.GetListItem(ADeltas, LIndex);

      if Statements.TryGetValue(LDelta.Key, LStatement) then
      begin
        LDataSet := ReadDataSet(LDelta.Key, LStatement, False);
        try
          LApplyResult := LApplyUpdates.ApplyUpdates(LDelta.Key, LDataSet.Command);
          if Assigned(AOnApplyUpdates) then
            AOnApplyUpdates(LDelta.Key, LApplyResult, LApplyUpdates);
        finally
          LDataSet.Free;
        end;
      end
      else
        raise EWiRLServerException.Create(
          Format('Unable to build update command for delta: %s', [LDelta.Key]),
          Self.ClassName, 'ApplyUpdates'
        );
    end;
  finally
    LApplyUpdates := nil; // it's an interface
  end;
end;

procedure TWiRLFDDatasetResource.BeforeOpenDataSet(ADataSet: TFDCustomQuery);
begin

end;

procedure TWiRLFDDatasetResource.CheckConnection;
begin
  if not Assigned(Connection) then
    raise EWiRLServerException.Create(
      'No data connection available', Self.ClassName, 'CheckConnection');
end;

destructor TWiRLFDDatasetResource.Destroy;
begin
  TeardownConnection;
  FStatements.Free;
  inherited;
end;

function TWiRLFDDatasetResource.ReadDataSet(const ADataSetName, ASQLStatement: string; const AAutoOpen: Boolean = True): TFDCustomQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := Connection;
    Result.SQL.Text := ASQLStatement;
    Result.Name := ADataSetName;
    BeforeOpenDataSet(Result);
    if AAutoOpen then
    begin
      Result.Open;
      AfterOpenDataSet(Result);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TWiRLFDDatasetResource.Retrieve: TArray<TFDCustomQuery>;
var
  LStatement: TPair<string, string>;
  LData: TArray<TFDCustomQuery>;
  LCurrent: TFDCustomQuery;
begin
  CheckConnection;

  SetLength(LData, 0);
  //LData := [];
  try
    // load dataset(s)
    SetupStatements;
    for LStatement in Statements do
    begin
      SetLength(LData, Length(LData) + 1);
      LData[Length(LData) - 1] := ReadDataSet(LStatement.Key, LStatement.Value);
    end;

    Result := LData;
  except
    // clean up
    for LCurrent in LData do
      LCurrent.Free;
    SetLength(LData, 0);
    raise;
  end;
end;

procedure TWiRLFDDatasetResource.SetupConnection;
begin
  TRTTIHelper.IfHasAttribute<ConnectionAttribute>(
    Self,
    procedure (AAttrib: ConnectionAttribute)
    begin
      Connection := CreateConnectionByDefName(AAttrib.ConnectionDefName);
      OwnsConnection := True;
    end
  );
end;

procedure TWiRLFDDatasetResource.SetupStatements;
begin
  TRTTIHelper.ForEachAttribute<SQLStatementAttribute>(Self,
    procedure (AAttrib: SQLStatementAttribute)
    begin
      Statements.Add(AAttrib.Name, AAttrib.SQLStatement);
    end
  );

end;

procedure TWiRLFDDatasetResource.TeardownConnection;
begin
  if OwnsConnection and Assigned(Connection) then
  begin
    Connection.Free;
    Connection := nil;
  end;
end;

function TWiRLFDDatasetResource.Update: string;
var
  LJSONDeltas: TJSONObject;
  LDeltas: TFDJSONDeltas;
  LResult: TJSONArray;
begin
  SetupConnection;
  try
    CheckConnection;

    // setup
    SetupStatements;

    // parse JSON content
    LJSONDeltas := TJSONObject.ParseJSONValue(Request.Content) as TJSONObject;

    LDeltas := TFDJSONDeltas.Create;
    try
      // build FireDAC delta objects
      if not TFDJSONInterceptor.JSONObjectToDataSets(LJSONDeltas, LDeltas) then
        raise EWiRLServerException.Create(
          'Error de-serializing deltas', Self.ClassName, 'Update');

      // apply updates
      LResult := TJSONArray.Create;
      try
        ApplyUpdates(LDeltas,
          procedure(ADatasetName: string; AApplyResult: Integer; AApplyUpdates: IFDJSONDeltasApplyUpdates)
          var
            LResultObj: TJSONObject;
          begin
            LResultObj := TJSONObject.Create;
            try
              LResultObj.AddPair('dataset', ADatasetName);
              LResultObj.AddPair('result', TJSONNumber.Create(AApplyResult));
              LResultObj.AddPair('errors', TJSONNumber.Create(AApplyUpdates.Errors.Count));
              LResultObj.AddPair('errorText', AApplyUpdates.Errors.Strings.Text);
              LResult.AddElement(LResultObj);
            except
              LResultObj.Free;
              raise;
            end;
          end
        );

        Result := TJSONHelper.ToJSON(LResult);
      finally
        LResult.Free;
      end;
    finally
      LDeltas.Free;
    end;

  finally
    TeardownConnection;
  end;
end;

{ ConnectionAttribute }

constructor ConnectionAttribute.Create(AConnectionDefName: string);
begin
  inherited Create;
  FConnectionDefName := AConnectionDefName;
end;

{ SQLStatementAttribute }

constructor SQLStatementAttribute.Create(const AName, ASQLStatement: string);
begin
  inherited Create;
  FName := AName;
  FSQLStatement := ASQLStatement;
end;

end.
