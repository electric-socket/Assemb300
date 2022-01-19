Program ASSEMB;  { Tests the ASSEM120 unit }
Uses Assem120,Crt,Dos;
{$M $5000,0,$10000}

{ By Joseph J. Tamburino / 7 Christopher Rd / Westford, MA 01886
  Prodigy account #:  NWNJ91A }

{     TO RUN THIS PROGRAM:
         1)  Substitute your own debugger and command.com paths (lines 21,22)
                           -- or --
             Remove the debugger portion of the code (in the main
             program block)

         2)  Using Turbo Pascal, compile and run the program (Tested only with
             Turbo Pascal 5.0)

         3)  Enter a legal 8088/86 instruction, and observe the results
}

Const
     PathCommandCom:  string=('c:\command.com'); { Substitute YOUR command.com here }
     PathDebugger:  string=('symdeb');           { Substitute YOUR debugger here }

Type
     HexByte = string[2];             {Storage for a 2-digit hex number}

Var
     Instruction,St:  string;
     TestFile:  text;
     i:  integer;
     Start:  word;

Function Hex(n:  byte):  HexByte;
{ Given a 1-byte number, n, return its hex equivalent }
Const
     Digits:  string='0123456789ABCDEF';

Begin
     Hex:=Digits[n shr 4+1]+Digits[n and 15+1]
End;

Function HexW(n:  word):  string;
Begin
     HexW:=Hex(Hi(n))+Hex(Lo(n))
End;

Procedure Capitalize(Var St:  string);
{ Strip lowercase characters from St }
Var
     i:  integer;

Begin
     For i:=1 to length(St) do St[i]:=Upcase(St[i])
End;

Function FromHex(n:  string):  word;
{ Given a hexadecimal character string in the form "Hx[xxx]", return its
  numeric equivalent }
Var
     n1:  byte;
     Tmp:  word;
     i:  integer;

Begin
     Capitalize(n);
     Tmp:=0;
     i:=2;
     While (i<=length(n)) and (n[i] in ['0'..'9','A'..'F']) do
     Begin
          Tmp:=Tmp shl 4;
          if n[i] in ['A'..'F'] then
                n1:=15-(ord('F')-ord(n[i]))
          else
                n1:=9-(ord('9')-ord(n[i]));
          Tmp:=Tmp+n1;
          inc(i)
     End;
     FromHex:=Tmp
End;

Begin
      ClrScr;
      Write('Enter HEX offset to start from  [',HexW(InstructionAddr),']:  ');
      ReadLn(St);
      if St<>'' then InstructionAddr:=FromHex('h'+St);
      Start:=InstructionAddr;
      Repeat
           WriteLn('Enter an instruction to assemble (ENTER to quit):  ');
           Write('XXXX:',HexW(InstructionAddr),':  ');
           ReadLn(Instruction);
           if Instruction<>'' then
           Begin
                Assemble(Instruction);   { <----  This does the assembling }
                WriteLn;
                assign(testfile,'testfile');
                rewrite(testfile);
                writeln(testfile,'e '+HexW(InstructionAddr));
                Inc(InstructionAddr,BytePtr-1);
                Write('Bytes for instruction:  ');
                For i:=1 to BytePtr-1 do
                Begin
                      Write(Hex(Bytes[i]),' ');
                      Write(testfile,Hex(Bytes[i]),' ')
                End;
                Writeln(TestFile);
                Writeln(TestFile,'u '+HexW(Start)+' '+HexW(InstructionAddr-1));
                WriteLn(TestFile,'q');
                Close(TestFile);
                WriteLn;
                Exec(PathCommandCom,'/C '+PathDebugger+' <testfile');
                WriteLn; Writeln
           End
      Until Instruction=''
End.