unit CatMsgCromis;

{
  Catarinka TCatMsgCromis - More reliable alternative to WM_COPYDATA messages
  Copyright (c) 2016 Felipe Daragon
  License: 3-clause BSD
  See https://github.com/felipedaragon/catarinka/ for details
}

interface

{$I Catarinka.inc}

uses
{$IFDEF DXE2_OR_UP}
  System.Classes, Winapi.Windows, Winapi.Messages, System.SysUtils,
  Cromis.Comm.Custom, Cromis.Comm.IPC, Cromis.Threading, Cromis.AnyValue;
{$ELSE}
  Classes, Windows, Messages, SysUtils;
{$ENDIF}

type
  TCatMsgCromisOnDataMessage = procedure(const msgid: integer;
    const str: string) of object;

type
  TCatMsgCromis = class
  private
    fIPCServer: TIPCServer;
    fMessageQueue: TThreadSafeQueue;
    fMsgHandle: HWND;
    fOnDataMessage: TCatMsgCromisOnDataMessage;
    fRequestCount: integer;
    function GetServerName: string;
    procedure crmMessage(var AMsg: TMessage);
    procedure OnExecuteRequest(const Context: ICommContext;
      const Request, Response: IMessageData);
    procedure HandleMessage(const AMessage: string);
  public
    constructor Create;
    destructor Destroy; override;
    property OnDataMessage: TCatMsgCromisOnDataMessage read fOnDataMessage
      write fOnDataMessage;
    property MsgHandle: HWND read fMsgHandle;
    property ServerName: string read GetServerName;
  end;

procedure SendCromisMessage(desthandle, msgid: integer; l: string);

implementation

uses
  CatJSON;

const
  WM_OnListBoxMessage = WM_USER + 1;
  WM_OnRequestFinished = WM_USER + 2;

procedure SendCromisMessage(desthandle, msgid: integer; l: string);
var
  Result: IIPCData;
  Request: IIPCData;
  IPCClient: TIPCClient;
begin
  IPCClient := TIPCClient.Create;
  try
    IPCClient.ComputerName := EmptyStr;
    IPCClient.ServerName := 'CATMSGSERVER' + inttostr(desthandle);
    IPCClient.ConnectClient(cDefaultTimeout);
    try
      if IPCClient.IsConnected then
      begin
        Request := AcquireIPCData;
        Request.ID := DateTimeToStr(Now);
        Request.Data.WriteInteger('CmdID', msgid);
        Request.Data.WriteUTF8String('Command', AnsiString(l));
        Result := IPCClient.ExecuteConnectedRequest(Request);
      end;
    finally
      IPCClient.DisconnectClient;
    end;
  finally
    IPCClient.Free;
  end;
end;

function TCatMsgCromis.GetServerName: string;
begin
  Result := fIPCServer.ServerName;
end;

procedure TCatMsgCromis.crmMessage(var AMsg: TMessage);
var
  LocalCount: integer;
  MessageValue: TAnyValue;
  j: TCatJSON;
begin
  try
    case AMsg.msg of
      WM_OnListBoxMessage:
        begin
          while fMessageQueue.Dequeue(MessageValue) do
          begin
            if Assigned(OnDataMessage) then
            begin
              j := TCatJSON.Create;
              j.Text := MessageValue.AsString;
              OnDataMessage(j.sObject.I['cmd'], j.sObject.S['s']);
              j.Free;
            end;
          end;
        end;
      WM_OnRequestFinished:
        begin
          InterlockedExchange(LocalCount, fRequestCount);
        end;
    end;
  except
    // Workaround for CEF windows focus related issue, when closing tab while loading
  end;
end;

procedure TCatMsgCromis.HandleMessage(const AMessage: string);
begin
  fMessageQueue.Enqueue(AMessage);
  PostMessage(fMsgHandle, WM_OnListBoxMessage, 0, 0);
end;

procedure TCatMsgCromis.OnExecuteRequest(const Context: ICommContext;
  const Request, Response: IMessageData);
var
  Command: AnsiString;
  CmdId: integer;
  // LocalCount: Integer;
  j: TCatJSON;
begin
  Command := Request.Data.ReadUTF8String('Command');
  CmdId := Request.Data.ReadInteger('CmdID');
  j := TCatJSON.Create;
  j['cmd'] := CmdId;
  j['s'] := Command;
  HandleMessage(j.Text);
  j.Free;
  // HandleMessage(Format('%s %s request recieved from client %s (Sent at: %s)',
  // [IntToStr(CmdId), Command,Context.Client.ID,Request.ID]));
  // increase the request count thread safe way
  // LocalCount :=
  InterlockedIncrement(fRequestCount);
  PostMessage(fMsgHandle, WM_OnRequestFinished, 0, 0);
end;

constructor TCatMsgCromis.Create;
begin
  fMsgHandle :=
{$IFDEF DXE2_OR_UP}System.{$ENDIF}Classes.AllocateHWnd(crmMessage);
  fMessageQueue := TThreadSafeQueue.Create;
  fIPCServer := TIPCServer.Create;
  fIPCServer.ServerName := 'CATMSGSERVER' + inttostr(fMsgHandle);
  fIPCServer.OnExecuteRequest := OnExecuteRequest;
  fIPCServer.Start;
end;

destructor TCatMsgCromis.Destroy;
begin
{$IFDEF DXE2_OR_UP}System.{$ENDIF}Classes.DeallocateHWnd(fMsgHandle);
  FreeAndNil(fIPCServer);
  FreeAndNil(fMessageQueue);
  inherited;
end;

end.
