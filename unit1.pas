unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Buttons, IniFiles;

type

  { TForm1 }

  TForm1 = class(TForm)
    edit_room_button: TButton;
    map_image: TImage;
    room_name_label: TLabel;
    start_stop_button: TSpeedButton;
    Timer1: TTimer;
    procedure edit_room_buttonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure map_imagePaint(Sender: TObject);
    procedure start_stop_buttonClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private

  public

  end;

var
  Form1: TForm1;

implementation


uses Windows, JwaTlHelp32;

function FindProcessID(const ExeFileName: string): DWORD;
var
  ContinueLoop: BOOL;
  FSnapshotHandle: THandle;
  FProcessEntry32: TProcessEntry32;
begin
  Result := 0;

  FSnapshotHandle := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  FProcessEntry32.dwSize := SizeOf(FProcessEntry32);
  ContinueLoop := Process32First(FSnapshotHandle, FProcessEntry32);

  while integer(ContinueLoop) <> 0 do
  begin
    if ((UpperCase(ExtractFileName(FProcessEntry32.szExeFile)) =
      UpperCase(ExeFileName)) or (UpperCase(FProcessEntry32.szExeFile) =
      UpperCase(ExeFileName))) then
    begin
      Result := FProcessEntry32.th32ProcessID;
      Break;
    end;
    ContinueLoop := Process32Next(FSnapshotHandle, FProcessEntry32);
  end;

  CloseHandle(FSnapshotHandle);
end;



function ReadMemory(hProcess: THandle; Address: Pointer; var Buffer;
  Size: DWORD): boolean;
var
  NumberOfBytesRead: SIZE_T;
begin
  Result := ReadProcessMemory(hProcess, Address, @Buffer, Size, NumberOfBytesRead) and
    (NumberOfBytesRead = Size);
end;

procedure ListRunningProcesses(ProcList: TStrings);
var
  pProc: TProcessEntry32;
  pSnap: THandle;
  pBool: BOOL;
begin
  ProcList.Clear;
  pProc.dwSize := SizeOf(pProc);
  pSnap := CreateToolhelp32Snapshot(TH32CS_SNAPALL, 0);
  pBool := Process32First(pSnap, pProc);
  while integer(pBool) <> 0 do
  begin
    ProcList.Add(pProc.szExeFile);
    pBool := Process32Next(pSnap, pProc);
  end;
  CloseHandle(pSnap);
end;



var
  hProcess: THandle;
  ROOMS: TIniFile; // contains room labels
  process_list: TStrings;
  room: smallint = -1; // contains current room 16-bit value
  last_room: smallint = -1;

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  // open ini file and create a list to hold processes
  ROOMS := TIniFile.Create('rooms.ini');
  process_list := TStringList.Create();
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  //  close the process on exit if it's been opened
  if start_stop_button.Down = True then
  begin
    Timer1.Enabled := False;
    CloseHandle(hProcess);
  end;
  // free additionally created objects
  ROOMS.Free;
  process_list.Free;
end;

procedure TForm1.map_imagePaint(Sender: TObject);
begin
  map_image.Canvas.Brush.Style := bsClear;
  map_image.Canvas.Rectangle(0, 0, 400, 400);
end;

procedure TForm1.start_stop_buttonClick(Sender: TObject);
var
  i: integer;
  ProcID: DWORD;

begin
  if start_stop_button.Down = False then
  begin
    start_stop_button.Caption := 'Start';
    Timer1.Enabled := False;
    CloseHandle(hProcess);
  end
  else
  begin
    start_stop_button.Caption := 'Stop';
    ListRunningProcesses(process_list);
    for i := 0 to process_list.Count - 1 do
    begin
      if (process_list[i] = 'MMBN_LC2.exe') then
      begin
        ProcID := FindProcessID(process_list[i]);
        hProcess := OpenProcess(PROCESS_VM_READ, False, ProcID);
        Caption := 'MMBN5M: Reading from process ID ' + IntToStr(ProcID);
        Timer1.Enabled := True;
        break;
      end;
    end;
  end;

end;

procedure TForm1.Timer1Timer(Sender: TObject);
var
  room_name: string;
begin

  if hProcess <> 0 then
  begin
    try
      if ReadMemory(hProcess, Pointer($80205FF4), room, SizeOf(room)) then
      begin
        if last_room <> room then
        begin
          last_room := room;
          room_name := ROOMS.ReadString('Rooms', IntToStr(room), 'Unknown');
          room_name_label.Caption := 'Room #' + IntToStr(room) + ': ' + room_name;
          if FileExists('images/' + room_name + '.png') then
          begin
            map_image.Picture.LoadFromFile('images/' + room_name + '.png');
          end
          else
          begin
            map_image.Picture.Clear;
          end;
        end;
      end
      else
      begin
        room_name_label.Caption := 'error';
      end;
    except
      on edit_room_button: Exception do
        room_name_label.Caption := 'error';
    end;
  end;

end;

procedure TForm1.edit_room_buttonClick(Sender: TObject);
var
  new_room_name: string;
begin
  if InputQuery('Editing Room # ' + IntToStr(room), 'Enter this Room''s name',
    new_room_name) then
  begin
    ROOMS.WriteString('Rooms', IntToStr(room), new_room_name);
  end;
end;

end.
