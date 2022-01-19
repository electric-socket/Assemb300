Program Translate;
{ Translates MNEMONIC.LST to MNEMONIC.BIN }
Type
    EncodRec=record
         Mnem:  string[8];
         Byte1:  string[9];
         OpType,Byte2,Class:  byte
    End;

    ChartType = array[0..160] of EncodRec;

Var
     Fin:  text;
     Fout:  file of ChartType;
     Chart:  ChartType;
     ChartPtr:  integer;
     Line:  string;
     Item:  string;
     Value:  byte;
     Code:  integer;

Const
     NO_OPERAND =            0;
     REG_MEM_REGISTER =      1;
     IMMEDIATE_AL_AX =       2;
     IMMEDIATE_REG_MEM =     3;
     DIRECT_IN_SEGMENT =     4;
     INDIRECT_IN_SEGMENT =   5;
     DIRECT_INTRASEGMENT =   6;
     INDIRECT_INTRASEGMENT = 7;
     REGISTER_MEMORY =       8;
     A16_BIT_REGISTER =      9;
     ESC =                  10;
     IMMEDIATE_PORT =       11;
     PORT_ADDRESS_IN_DX =   12;
     INT =                  13;
     EIGHT_BIT_REL =        14;
     MEMORY_AL_AX =         15;
     AL_AX_MEMORY =         16;
     REG_MEM_SR =           17;
     SR_REG_MEM =           18;
     SEGMENT_REGISTER =     19;
     ANOTHER_INSTRUCTION =  20;
     RET =                  21;
     IMMEDIATE_REGISTER =   22;

Function NextItem(Var Line:  string):  string;
{Takes an item (each item is separated by a | character) from Line.}
{Whitespace is ignored.  The item is removed from the left of Line.}
Var
     p:  integer;
     Item:  string;

Begin
      p:=Pos('|',Line);
      if p=0 then p:=Length(Line);
      Item:='';
      For p:=1 to p do
      Begin
           if not (Line[1] in [' ','|']) then Item:=Item+Line[1];
           Line:=Copy(Line,2,Length(Line)-1)
      End;
      NextItem:=Item
End;

Procedure Capitalize(Var St:  string);
Var
      i:  integer;

Begin
     For i:=1 to length(St) do St[i]:=Upcase(St[i])
End;

Function FromHex(n:  string):  word;
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

Function FromBin(n:  string):  word;
Var
     i,mult,res:  word;

Begin
     Mult:=1; res:=0;
     For i:=1 to length(n)-1 do
     Begin
          if n[length(n)]='1' then
               res:=res+mult;
          n:=Copy(n,1,length(n)-1);
          mult:=mult shl 1
     End;
     FromBin:=res
End;

Function GetValue(St:  string):  byte;
Begin
     if St='' then
     Begin
          GetValue:=0;
          Exit
     End;
     Case St[1] of
          'B':  GetValue:=lo(FromBin(St));
          'H':  GetValue:=lo(FromHex(St))
          else
          Begin
                WriteLn(#7,'Error in LST file.');
                Close(Fin);
                Halt
          End
     End
End;


Function GetOpType(St:  string):  byte;
Begin
     if St='NO_OPERAND' then GetOpType:=NO_OPERAND else
     if St='REG/MEM,REGISTER' then GetOpType:=REG_MEM_REGISTER else
     if St='IMMEDIATE,AL/AX' then GetOpType:=IMMEDIATE_AL_AX else
     if St='IMMEDIATE,REG/MEM' then GetOpType:=IMMEDIATE_REG_MEM else
     if St='DIRECT_IN_SEGMENT' then GetOpType:=DIRECT_IN_SEGMENT else
     if St='INDIRECT_IN_SEGMENT' then GetOpType:=INDIRECT_IN_SEGMENT else
     if St='DIRECT_INTRASEGMENT' then GetOpType:=DIRECT_INTRASEGMENT else
     if St='INDIRECT_INTRASEGMENT' then GetOpType:=INDIRECT_INTRASEGMENT else
     if St='REGISTER/MEMORY' then GetOpType:=REGISTER_MEMORY else
     if St='16-BIT_REGISTER' then GetOpType:=A16_BIT_REGISTER else
     if St='ESC' then GetOpType:=ESC else
     if St='IMMEDIATE_PORT' then GetOpType:=IMMEDIATE_PORT else
     if St='PORT_ADDRESS_IN_DX' then GetOpType:=PORT_ADDRESS_IN_DX else
     if St='INT' then GetOpType:=INT else
     if St='8-BIT-REL' then GetOpType:=EIGHT_BIT_REL else
     if St='MEMORY,AL/AX' then GetOpType:=MEMORY_AL_AX else
     if St='AL/AX,MEMORY' then GetOpType:=AL_AX_MEMORY else
     if St='REG/MEM,SR' then GetOpType:=REG_MEM_SR else
     if St='SR,REG/MEM' then GetOpType:=SR_REG_MEM else
     if St='IMMEDIATE,REGISTER' then GetOpType:=IMMEDIATE_REGISTER else
     if St='SEGMENT_REGISTER' then GetOpType:=SEGMENT_REGISTER else
     if St='ANOTHER_INSTRUCTION' then GetOpType:=ANOTHER_INSTRUCTION else
     if St='RET' then GetOpType:=RET else
     Begin
          WriteLn(#7,St,' is a bad operand type.');
          Close(fin);
          Halt
     End
End;

Function Blank(Line:  string):  boolean;
Var
     i:  integer;

Begin
     Blank:=TRUE;
     For i:=1 to length(Line) do
          if not (Line[i] in [#32,#0]) then Blank:=FALSE
End;

Begin
     Assign(Fin,'mnemonic.lst');
     Reset(Fin);
     ChartPtr:=0;
     Repeat
          ReadLn(Fin,Line);
          Capitalize(Line);
          if (Line[1]<>';') and (not Blank(Line)) then
          Begin
               inc(ChartPtr);
               Chart[ChartPtr].Mnem:=NextItem(Line);
               if Chart[ChartPtr].Mnem<>'ENDOFLIS' then
               Begin
                    Chart[ChartPtr].Byte1:=NextItem(Line);
                    Item:=NextItem(Line);
                    Chart[ChartPtr].OpType:=GetOpType(Item);
                    Item:=NextItem(Line);
                    Chart[ChartPtr].Byte2:=GetValue(Item);
                    Item:=NextItem(Line);
                    Val(Item,Value,Code);
                    Chart[ChartPtr].Class:=Value
               End
          End
     Until Chart[ChartPtr].Mnem='ENDOFLIS';
     dec(ChartPtr);
     Close(Fin);
     Assign(Fout,'programs\mnemonic.bin');
     Rewrite(Fout);
     Write(Fout,Chart);
     Close(Fout)
End.