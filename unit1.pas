unit Unit1;

{$mode objfpc}{$H+}

interface

uses
Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
Buttons, Grids, IniFiles, Windows;

type
TWMHotKey = packed record
	MSG  :CARDINAL;
	HotKey  :PtrInt;
	Unused  :PtrInt;
	Result  :PtrInt;
end;


type

{ TForm1 }

TForm1 = class ( TForm )
	gamebox  :TComboBox;
	map_stretch_checkbox  :TCheckBox;
	plus_spoil  :TButton;
	edit_room_button  :TButton;
	minus_spoil1  :TButton;
	spoils_label  :TLabel;
	spoils_listbox  :TListBox;
	map_image  :TImage;
	room_name_label  :TLabel;
	start_stop_button  :TSpeedButton;
	Timer1   :TTimer;
	procedure edit_room_buttonClick ( Sender  :TObject );
	procedure FormClose ( Sender  :TObject; var CloseAction  :TCloseAction );
	procedure FormCreate ( Sender  :TObject );
	procedure gameboxSelect ( Sender  :TObject );
	procedure map_imagePaint ( Sender  :TObject );
	procedure map_stretch_checkboxChange ( Sender  :TObject );
	procedure minus_spoil1Click ( Sender  :TObject );
	procedure plus_spoilClick ( Sender  :TObject );
	procedure spoils_listboxDblClick ( Sender  :TObject );
	procedure start_stop_buttonClick ( Sender  :TObject );
	procedure Timer1Timer ( Sender  :TObject );
PRIVATE

PUBLIC

PROTECTED
	procedure WMHotKey ( var MSG  :TWMHotKey ); MESSAGE WM_HOTKEY;

end;

var
Form1  :TForm1;

implementation


uses JwaTlHelp32;


function FindProcessID ( const ExeFileName  :STRING )  :DWORD;
var
	ContinueLoop  :BOOL;
	FSnapshotHandle  :THandle;
	FProcessEntry32  :TProcessEntry32;
begin
	Result := 0;

	FSnapshotHandle := CreateToolhelp32Snapshot ( TH32CS_SNAPPROCESS, 0 );
	FProcessEntry32.dwSize := SizeOf ( FProcessEntry32 );
	ContinueLoop := Process32First ( FSnapshotHandle, FProcessEntry32 );

	while INTEGER ( ContinueLoop ) <> 0 do
	begin
		if ( ( UpperCase ( ExtractFileName ( FProcessEntry32.szExeFile ) ) = UpperCase ( ExeFileName ) )
        OR( UpperCase ( FProcessEntry32.szExeFile ) = UpperCase ( ExeFileName ) ) ) then begin
			Result := FProcessEntry32.th32ProcessID;
			Break;
		end;
		ContinueLoop := Process32Next ( FSnapshotHandle, FProcessEntry32 );
	end;

	CloseHandle ( FSnapshotHandle );
end;


function ReadMemory ( hProcess  :THandle; Address  :Pointer; var Buffer; Size  :DWORD )  :BOOLEAN;
var
	NumberOfBytesRead  :SIZE_T;
begin
	Result := ReadProcessMemory ( hProcess, Address, @Buffer, Size, NumberOfBytesRead ) AND ( NumberOfBytesRead = Size );
end;


procedure ListRunningProcesses ( ProcList  :TStrings );
var
	pProc  :TProcessEntry32;
	pSnap  :THandle;
	pBool  :BOOL;
begin
	ProcList.Clear;
	pProc.dwSize := SizeOf ( pProc );
	pSnap := CreateToolhelp32Snapshot ( TH32CS_SNAPALL, 0 );
	pBool := Process32First ( pSnap, pProc );
	while INTEGER ( pBool ) <> 0 do begin
		ProcList.Add ( pProc.szExeFile );
		pBool := Process32Next ( pSnap, pProc );
	end;
	CloseHandle ( pSnap );
end;


var
hProcess  :THandle;
ROOMS  :TIniFile; // contains room labels
process_list  :TStrings;
room   :QWORD = -1; // contains current room 16-bit value
last_room  :QWORD = -1;
room_name  :STRING;
new_room  :bool;
spoils_list  :STRING;
spoils  :TStringArray;
fullscreen_map  :bool = False;
current_game  :STRING = 'MMBN 6';
mmbn5_pointer  :QWORD = $80205FF4;
//mmbn6 has a weird way to denote areas: there' main area code and subcodes. 0 = Central Town, 1 = Cyberspace in Central Town.
// So, Central Area 1 is 0-144, but Central Area 2 is somehow 144-256
// the pointer is : smallint = $7FFF1E9B (subarea) and smallint = $7FFF1E98 (general area);
// I don't want to dea with that, so I just read everything as ONE qword and it seems to work
mmbn6_pointer  :QWORD = $7FFF1E96;
current_game_pointer  :QWORD;
is_cyberworld  :BOOLEAN = False;

var
x, y, w, h  :INTEGER;
state  :TWindowState;

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate ( Sender  :TObject );
begin
	current_game_pointer := mmbn5_pointer;
	// open ini file and create a list to hold processes
	ROOMS := TIniFile.Create ( 'rooms.ini' );
	process_list := TStringList.Create ( );
	spoils_listbox.Height := 0;
	if NOT RegisterHotKey ( Handle, 111000, MOD_WIN, VK_Y ) then
		ShowMessage ( 'HotKey registration failed. You won''t be able to press Win+Y to temporarily view map in full screen.' );
end;


procedure TForm1.gameboxSelect ( Sender  :TObject );
begin
	current_game := gamebox.Items [gamebox.ItemIndex];
	if ( gamebox.ItemIndex = 0 ) then begin
		current_game_pointer := mmbn5_pointer;
	end else begin
		current_game_pointer := mmbn6_pointer;
	end;
	ROOMS.WriteString ( 'Pointers', current_game, IntToStr ( current_game_pointer ) );
end;


procedure TForm1.map_imagePaint ( Sender  :TObject );
begin
	//map_image.Canvas.Brush.Style := bsClear;
	//map_image.Canvas.Rectangle(0, 0, 400, 400);
end;


procedure TForm1.map_stretch_checkboxChange ( Sender  :TObject );
begin
	map_image.Proportional := NOT map_stretch_checkbox.Checked;
end;


procedure TForm1.minus_spoil1Click ( Sender  :TObject );
var
	Txt  :STRING;
	i  :INTEGER;
begin
	if ( spoils_listbox.ItemIndex > -1 ) then begin
		spoils_listbox.Items.Delete ( spoils_listbox.ItemIndex );
		for i := 0 to spoils_listbox.Items.Count - 1 do begin
			if i < spoils_listbox.Items.Count - 1 then
				Txt := Txt + spoils_listbox.Items [i] + ','
			else
				Txt := Txt + spoils_listbox.Items [i];
		end;
		if is_cyberworld = True then
			ROOMS.WriteString ( 'Spoils Cyberworld ' + current_game, IntToStr ( room ), Txt )
		else
			ROOMS.WriteString ( 'Spoils ' + current_game, IntToStr ( room ), Txt );

	end;
	spoils_listbox.ClearSelection;
end;


procedure TForm1.plus_spoilClick ( Sender  :TObject );
var
	new_spoil_name  :STRING;
	Txt  :STRING;
	i  :INTEGER;
begin
	if InputQuery ( 'Adding item to Room #' + IntToStr ( room ), 'Enter item''s name', new_spoil_name ) then begin
		spoils_listbox.Items.Add ( new_spoil_name );
		for i := 0 to spoils_listbox.Items.Count - 1 do begin
			if i < spoils_listbox.Items.Count - 1 then
				Txt := Txt + spoils_listbox.Items [i] + ','
			else
				Txt := Txt + spoils_listbox.Items [i];
		end;
		if is_cyberworld = True then
			ROOMS.WriteString ( 'Spoils Cyberworld ' + current_game, IntToStr ( room ), Txt )
		else
			ROOMS.WriteString ( 'Spoils ' + current_game, IntToStr ( room ), Txt );

	end;
	spoils_listbox.ClearSelection;
end;


procedure TForm1.spoils_listboxDblClick ( Sender  :TObject );
var
	new_spoil_name  :STRING;
var
	Txt  :STRING;
	i  :INTEGER;
begin
	if ( spoils_listbox.ItemIndex > -1 ) then begin
		new_spoil_name := spoils_listbox.Items [spoils_listbox.ItemIndex];
		if InputQuery ( 'Editing item in Room #' + IntToStr ( room ), 'Enter item''s name', new_spoil_name ) then begin
			spoils_listbox.Items[spoils_listbox.ItemIndex] := new_spoil_name;
			for i := 0 to spoils_listbox.Items.Count - 1 do begin
				if i < spoils_listbox.Items.Count - 1 then
					Txt := Txt + spoils_listbox.Items [i] + ','
				else
					Txt := Txt + spoils_listbox.Items [i];
			end;
			if is_cyberworld = True then
				ROOMS.WriteString ( 'Spoils Cyberworld ' + current_game, IntToStr ( room ), Txt )
			else
				ROOMS.WriteString ( 'Spoils ' + current_game, IntToStr ( room ), Txt );

		end;
	end;
	spoils_listbox.ClearSelection;
end;


procedure TForm1.start_stop_buttonClick ( Sender  :TObject );
var
	i  :INTEGER;
	ProcID  :DWORD;

begin
	if start_stop_button.Down = False then begin
		start_stop_button.Caption := 'Start';
		Timer1.Enabled := False;
		CloseHandle ( hProcess );
		room_name_label.Caption := 'Run the game, then press "Start"';
	end else begin
		start_stop_button.Caption := 'Stop';
		ListRunningProcesses ( process_list );
		for i := 0 to process_list.Count - 1 do begin
			if ( process_list [i] = 'MMBN_LC2.exe' ) then begin
				ProcID  := FindProcessID ( process_list [i] );
				hProcess := OpenProcess ( PROCESS_VM_READ, False, ProcID );
				Caption := 'MMBN5-6M: Reading from process ID ' + IntToStr ( ProcID );
				Timer1.Enabled := True;
				break;
			end else begin
				room_name_label.Caption := 'Error. Run the game.';
			end;
		end;
	end;
end;


procedure TForm1.Timer1Timer ( Sender  :TObject );
var
	room_number_size  :SMALLINT;
begin
	spoils_listbox.Height := spoils_listbox.Items.Count * spoils_listbox.ItemHeight;

	if hProcess <> 0 then begin
		try
			if current_game = 'MMBN 6' then
				room_number_size := SizeOf ( QWORD )
			else
				room_number_size := SizeOf ( SMALLINT );

			if ReadMemory ( hProcess, Pointer ( current_game_pointer ), room, room_number_size ) then begin
				if ( last_room <> room ) OR ( new_room ) then begin
					new_room  := False;
					last_room := room;
					if current_game = 'MMBN 6' then begin
						// Don't show room numbers for MMBN 6 until something smaller-looking can be figured out
						room_name := ROOMS.ReadString ( 'Rooms ' + current_game, IntToStr ( room ), 'Unknown' );
						room_name_label.Caption := room_name;
					end else begin
						room := SMALLINT ( room ); // - 844424930459648;
						room_name := ROOMS.ReadString ( 'Rooms ' + current_game, IntToStr ( room ), 'Unknown' );
						room_name_label.Caption := 'Room #' + IntToStr ( room ) + ': ' + room_name;
					end;

					spoils_list := ROOMS.ReadString ( 'Spoils ' + current_game, IntToStr ( room ), '' );
					spoils_listbox.Items.Clear;
					if ( spoils_list <> '' ) then begin
						spoils := spoils_list.Split ( ',' );
						spoils_listbox.Items.AddStrings ( spoils );
					end;

					if FileExists ( 'images/' + current_game + '/' + room_name + '.png' ) then begin
						map_image.Picture.LoadFromFile ( 'images/' + current_game + '/' + room_name + '.png' );
					end else begin
						map_image.Picture.Clear;
					end;
				end;
			end else begin
				room_name_label.Caption := 'Error. Make sure the game is running.';
			end;
		except
			on edit_room_button  :Exception do
				room_name_label.Caption := 'Error. Can''t read game''s memory.';
		end;
	end;

end;


procedure TForm1.edit_room_buttonClick ( Sender  :TObject );
var
	new_room_name  :STRING;
begin
	new_room_name := room_name;
	if InputQuery ( 'Editing Room # ' + IntToStr ( room ), 'Enter this Room''s name', new_room_name ) then begin
		ROOMS.WriteString ( 'Rooms ' + current_game, IntToStr ( room ), new_room_name );
	end;
end;


procedure TForm1.FormClose ( Sender  :TObject; var CloseAction  :TCloseAction );
begin
	// close the process on exit if it's been opened
	if start_stop_button.Down = True then begin
		Timer1.Enabled := False;
		CloseHandle ( hProcess );
	end;
	// free additionally created objects
	ROOMS.Free;
	process_list.Free;
	UnregisterHotKey ( Handle, 111000 );
end;


procedure TForm1.WMHotKey ( var MSG  :TWMHotKey );
begin
	fullscreen_map := NOT fullscreen_map;

	Form1.Visible := False;
	if ( fullscreen_map = True ) then begin
		x := Form1.Left;
		y := Form1.top;
		w := Form1.Width;
		h := Form1.Height;
		Application.ProcessMessages;
		state := Form1.WindowState;
		Form1.FormStyle := fsStayOnTop;
		Form1.BorderStyle := bsNone;
		Form1.Left := 0;
		Form1.Top := 0;
		form1.Width := Screen.Width;
		Form1.Height := Screen.Height;
	end else begin
		Form1.WindowState := state;
		Form1.FormStyle := fsNormal;
		Form1.BorderStyle := bsSizeable;
		Application.ProcessMessages;
		Form1.Position := poDesigned;
		Form1.Left := x;
		Form1.Top  := y;
		form1.Width := w;
		Form1.Height := h;
	end;

	Form1.Visible := True;
	RegisterHotKey ( Handle, 111000, MOD_WIN, VK_Y );

end;

end.
