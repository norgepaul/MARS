{******************************************************************************}
{                                                                              }
{       WiRL: RESTful Library for Delphi                                       }
{                                                                              }
{       Copyright (c) 2015-2017 WiRL Team                                      }
{                                                                              }
{       https://github.com/delphi-blocks/WiRL                                  }
{                                                                              }
{******************************************************************************}
unit Forms.Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, WiRL.Client.CustomResource,
  WiRL.Client.Resource, WiRL.Client.FireDAC, WiRL.Client.Application,
  WiRL.Client.Client, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf,
  FireDAC.DApt.Intf, Data.DB, Vcl.Grids, Vcl.DBGrids, FireDAC.Comp.DataSet,
  FireDAC.Comp.Client, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.DBCtrls;

type
  TMainForm = class(TForm)
    WiRLClient: TWiRLClient;
    WiRLTodoApplication: TWiRLClientApplication;
    WiRLAccountsResource: TWiRLFDResource;
    DBGrid1: TDBGrid;
    DBNavigator1: TDBNavigator;
    SendAccountsToServerButton: TButton;
    DBGrid2: TDBGrid;
    QueryAccounts1: TFDMemTable;
    QueryItems1: TFDMemTable;
    ItemsDataSource: TDataSource;
    AccountsDataSource: TDataSource;
    WiRLItemsResource: TWiRLFDResource;
    GetItemsButton: TButton;
    DBNavigator2: TDBNavigator;
    SendItemsToServerButton: TButton;
    procedure FormCreate(Sender: TObject);
    procedure SendAccountsToServerButtonClick(Sender: TObject);
    procedure SendItemsToServerButtonClick(Sender: TObject);
    procedure GetItemsButtonClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.GetItemsButtonClick(Sender: TObject);
begin
  WiRLItemsResource.QueryParams.Values['username'] := QueryAccounts1.FieldByName('USERNAME').AsString;
  WiRLItemsResource.GET();
end;

procedure TMainForm.SendAccountsToServerButtonClick(Sender: TObject);
begin
  WiRLAccountsResource.POST();
end;

procedure TMainForm.SendItemsToServerButtonClick(Sender: TObject);
begin
  WiRLItemsResource.POST();
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  WiRLAccountsResource.GET();
end;

end.
