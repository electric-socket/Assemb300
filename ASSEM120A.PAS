Unit Assemb; { Version 3.00 - Pascal }
{ An instruction assembly unit }

{ By Joseph J. Tamburino / 7 Christopher Rd / Westford, MA 01886
  Prodigy account #:  NWNJ91A }

{ Revision history: }
{ Version 1.00 and below:  Program development for assemble procedures
                           is in progress
          1.10          :  Program has working "assemble" command
          1.20          :  Internal code changes made;  Use of MNEMONIC.BIN
                           instead of MNEMONIC.LST;  Use of TRANSLATE.PAS.
                           Two types of string variables are converted to
                           bytes.
          2.00          :  Program is translated into assembly language from
                           Pascal (This is the Pascal version -- 1.20)

   Newly updated for XDPascal 2020-01-19 by Paul Robinson
          3.00          :  Handle 32-bit assembly (previous version
                           was 16-bit                                    }


{  Additional information from
    Chapter 1 of Oracle IA-32 Assembly Language Reference Manual
    https://docs.oracle.com/cd/E19455-01/806-3773/6jct9o0aa/index.html     }


Interface
Var
     Bytes:  array[1..15] of byte;    {The resulting instruction's bytes}
     BytePtr:  integer;               {Indexing variable for Bytes[]}
     InstructionAddr:  word;          {Offset of next instruction}

Procedure Assemble(Instruct:  string);


Implementation
Type
     Registers = (Reg_AL', Reg_AH', Reg_BL', Reg_BH',  {8-bit registers}
                 Reg_CL', Reg_CH', Reg_DL', Reg_DH',
                 Reg_AX', Reg_BX', Reg_CX', Reg_DX',  {low 16 bits of %EAX..%EDI}
                 Reg_SP', Reg_BP', Reg_SI', Reg_DI',
                 Reg_EAX',Reg_ECX',Reg_EDX',Reg_EBX', {32-bit}
                 Reg_ESP',Reg_EBP',Reg_ESI',Reg_EDI',
                 Reg_CS', Reg_DS', Reg_SS', Reg_ES',  {Segment registers}
                 Reg_FS', Reg_GS'
     EncodRec=record                  {Record contains mnemonic information}
          Mnem:  string[8];           {   The mnemonic}
          Byte1:  string[9];          {   Initial byte information}
          prefix: byte;               {   instruction prefix, 0 if no prefix}
          OpType:  byte;              {   The operand type (see constants below) }
          Byte2:  byte;               {   The second byte or reg field }
          OpClass:  byte              {   The class of the mnemonic (see GetOperandType proc ) }
     End;
     ChartType=array[1..600] of EncodRec;   { Allocate 600 mnemonic entries }
     String4=String[4];              {Register names}

Var
     InstFile:  File;                 {File containing mnemonic/operand/class information}
     LastByte:  byte;                 {The byte from the last instruction (used for the REP prefix) }
     ExtendedInstruction:  boolean;   {This boolean is TRUE for segment overrides and REP prefixes}
     Chart:  ChartType;               {The memory-resident version of InstFile}
     ChartPtr:  integer;              {Used as an index to Chart}
     CurrentInstruct:  integer;       {Used to save the current instruction position from Chart}
     WordData:  boolean;              {Is true current instruction is using a word-length transfer}

Const
     BX=01;
     SI=02;
     DI=04;
     BP=08;
     MaxReg=30;
     RegList:  array[1..MaxReg] of string4=(
                 '%AL', '%AH', '%BL', '%BH',  {8-bit registers}
                 '%CL', '%CH', '%DL', '%DH',
                 '%AX', '%BX', '%CX', '%DX',  {low 16 bits of %EAX..%EDI}
                 '%SP', '%BP', '%SI', '%DI',
                 '%EAX','%ECX','%EDX','%EBX', {32-bit}
                 '%ESP','%EBP','%ESI','%EDI',
                 '%CS', '%DS', '%SS', '%ES',  {Segment registers}
                 '%FS', '%GS');

     AddrModes:  array[1..8] of byte=(BX+SI,
                                      BX+DI,
                                      BP+SI,
                                      BP+DI,
                                      SI,
                                      DI,
                                      BP,
                                      BX);

{ Each instruction has an operand-type associated with it.  I have provided a
  sample instruction in comments to demonstrate the differences among them.  }


     NO_OPERAND =            0;   { NOP }
     REG_MEM_REGISTER =      1;   { MOV BX,ES:[BP+5+SI] or MOV CX,DX }
     IMMEDIATE_AL_AX =       2;   { CMP AX,56 }
     IMMEDIATE_REG_MEM =     3;   { CMP BX,78 or CMP SS:[BP+8],0Ah }
     DIRECT_IN_SEGMENT =     4;   { CALL 567H }
     INDIRECT_IN_SEGMENT =   5;   { CALL [78] }
     DIRECT_INTRASEGMENT =   6;   { JMP 6543:8765 }
     INDIRECT_INTRASEGMENT = 7;   { JMP FAR [BX] }
     REGISTER_MEMORY =       8;   { PUSH BL or PUSH ES:[BX] }
     A16_BIT_REGISTER =      9;   { PUSH BX }
     ESC =                  10;   { ESC ES:[BP+DI+7],101011b }
     IMMEDIATE_PORT =       11;   { IN AL,0ABCh }
     PORT_ADDRESS_IN_DX =   12;   { IN AL,DX }
     INT =                  13;   { INT 67H or INT 3 }
     EIGHT_BIT_REL =        14;   { JL 90 or JMP SHORT 90 }
     MEMORY_AL_AX =         15;   { MOV ES:[SI],AL }
     AL_AX_MEMORY =         16;   { MOV AX,CS:[DI] }
     REG_MEM_SR =           17;   { MOV BX,ES or MOV [2],SS }
     SR_REG_MEM =           18;   { MOV ES,BX or MOV SS,[2] }
     SEGMENT_REGISTER =     19;   { PUSH ES }
     ANOTHER_INSTRUCTION =  20;   { REP MOVSB (MOVSB is the other instruction) }
     RET =                  21;   { RET or RET 6 }
     IMMEDIATE_REGISTER =   22;   { MOV BX,67 }


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

Function FromBin(n:  string):  word;
{ Given a binary character string in the form "Bx[xxx...]", return its
  numeric equivalent }
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

Function NextPart(Var Line:  string;  Separate:  char):  string;
{Takes an item (each item is separated by Separate) from Line.}
{Whitespace is ignored.  The item is removed from the left of Line.}
Var
     p:  integer;
     Item:  string;

Begin
      While Line[1]=' ' do Line:=Copy(Line,2,Length(Line)-1);
      p:=Pos(Separate,Line);
      if p=0 then p:=Length(Line);
      Item:='';
      For p:=1 to p do
      Begin
           if Line[1]<>Separate then Item:=Item+Line[1];
           Line:=Copy(Line,2,Length(Line)-1)
      End;
      NextPart:=Item
End;

Function StripMem(St:  string):  string;
{Strip anything contained inside brackets from St}
Var
     Strt:  boolean;
     i:  integer;

Begin
     Strt:=FALSE;
     For i:=1 to length(St) do
     Begin
          if St[i]=']' then Strt:=FALSE;
          if Strt then St[i]:=' ';
          if St[i]='[' then Strt:=TRUE
     End;
     StripMem:=St
End;

Function HasReg(Op:  string):  integer;
{ Returns:
            0 if Op is not a valid register
            1 if Op is a valid register<>AX, AH, or AL
            2 if Op is AX, AH, or AL
}
Var
     i:  integer;
     Tmp:  string;

Begin
     if Op='' then Begin HasReg:=0; exit end;
     Tmp:=StripMem(Op);
     i:=0;
     Repeat
           inc(i)
     Until (Tmp=RegList[i]) or (i=MaxReg);
     if (i=MaxReg) and (Tmp<>RegList[i]) then HasReg:=0;
     if (Tmp=RegList[i]) and (RegList[i][1]<>'A') then HasReg:=1;
     if (Tmp=RegList[i]) and (RegList[i][1]='A') then HasReg:=2
End;

Function HasMem(Op:  string):  Boolean;
{ Returns TRUE iff Op references memory }
Begin
     if Pos('[',Op)<>0 then
          HasMem:=TRUE
     else
          HasMem:=FALSE
End;

Function HasImm(Op:  string):  boolean;
{ Returns TRUE iff Op contains an immediate value }
Var
     i:  integer;
     Tmp:  string;

Begin
     HasImm:=FALSE;
     Tmp:=StripMem(Op);
     For i:=1 to length(Tmp) do
          if (Tmp[i] in ['0'..'9']) then
               HasImm:=TRUE
End;

Function HasMemReg(Op:  string):  boolean;
{ Returns TRUE iff Op references memory or is a valid register }
Begin
     if (HasMem(Op)) or (HasReg(Op)>0) then
          HasMemReg:=TRUE
     else
          HasMemReg:=FALSE
End;

Function IsFar(Op:  string):  boolean;
{ Returns TRUE iff Op is a string of type FAR }
Begin
     IsFar:=FALSE;
     if Pos('FAR',Op)<>0 then IsFar:=TRUE;
     if Pos(':',Op)<>0 then IsFar:=TRUE
End;

Function Has16BitReg(Op:  string):  boolean;
{ Returns TRUE iff Op uses 16-bit, valid registers }
Var
     i:  integer;
     Tmp:  string;

Begin
     Tmp:=StripMem(Op);
     Has16BitReg:=FALSE;
     For i:=1 to 8 do
          if Pos(RegList[i],Tmp)<>0 then Has16BitReg:=TRUE
End;

Function IsShort(Op:  string):  boolean;
{ Returns TRUE iff Op is of type SHORT }
Begin
     if Pos('SHORT',Op)<>0 then
          IsShort:=TRUE
     else
          IsShort:=FALSE
End;

Function HasEA(Op:  string):  boolean;
{ Returns TRUE iff Op contains an effective address }
Var
     i:  integer;

Begin
     HasEA:=FALSE;
     For i:=1 to length(Op) do
          if Op[i] in ['0'..'9'] then HasEA:=TRUE;
     if not HasMem(Op) then HasEA:=FALSE;
     For i:=1 to 16 do
          if Pos(RegList[i],Op)<>0 then HasEA:=FALSE
End;

Function HasSR(Op:  string):  boolean;
{ Returns TRUE if Op is a segment register }
Begin
     if (Op='ES') or (Op='CS') or (Op='DS') or (Op='SS') then
          HasSR:=TRUE
     else
          HasSR:=FALSE
End;

Function GetOperandType(Mnemonic:  string; Var Op,Op1,Op2:  string):  byte;
{ Given the mnemonic and the operand, return the operand type and
  the first and second operands, Op1 & Op2 }
Var
     p,i:  integer;
     Mem,Imm,Areg,AnyReg:  boolean;
     Reg:  integer;
     OpClass:  byte;

Begin
     GetOperandType:=NO_OPERAND;
     p:=Pos(',',Op);
     if p=0 then
     Begin
          Op1:=Op;
          Op2:=''
     End
     Else
     Begin
          Op1:=Copy(Op,1,p-1);
          Op2:=Copy(Op,p+1,Length(op))
     End;
     i:=1;
     While (i<=ChartPtr) and (Chart[i].Mnem<>Mnemonic) do
          inc(i);
     if i>ChartPtr then
     Begin
          WriteLn(#7,'Mnemonic not found in master listing.');
          Halt
     End;
     CurrentInstruct:=i;
     OpClass:=Chart[i].OpClass;
     if OpClass=1 then          {REP class}
     Begin
          GetOperandType:=ANOTHER_INSTRUCTION;
          Exit
     End;
     if Op1='' then Exit;
     Case OpClass of
          2:   Begin          { XCHG class }
                    if ((HasReg(Op1)=2) and (HasReg(Op2)=1)) or
                       ((HasReg(Op1)=1) and (HasReg(Op2)=2)) then
                           GetOperandType:=A16_BIT_REGISTER
                    else
                         GetOperandType:=REG_MEM_REGISTER
               End;
          3:   Begin           { RET class }
                    GetOperandType:=RET
               End;
          4:   Begin           { MOV class }
                    if (HasEA(Op1)) and (HasReg(Op2)=2) then
                         GetOperandType:=AL_AX_MEMORY
                    else
                    if (HasEA(Op2)) and (HasReg(Op1)=2) then
                         GetOperandType:=MEMORY_AL_AX
                    else
                    if (HasImm(Op2)) and (HasReg(Op1)>0) then
                         GetOperandType:=IMMEDIATE_REGISTER
                    else
                    if (HasSR(Op1)) and (HasMemReg(Op2)) then
                         GetOperandType:=REG_MEM_SR
                    else
                    if (HasSR(Op2)) and (HasMemReg(Op1)) then
                         GetOperandType:=SR_REG_MEM
                    else
                    if (HasMemReg(Op1)) and (HasMemReg(Op2)) then
                         GetOperandType:=REG_MEM_REGISTER
                    else
                    if (HasImm(Op2)) and (HasMemReg(Op1)) then
                         GetOperandType:=IMMEDIATE_REG_MEM
               End;
          5:   Begin           { 8-bit jump class }
                    GetOperandType:=EIGHT_BIT_REL
               End;
          6:   Begin           { INT class }
                    GetOperandType:=INT
               End;
          7:   Begin            { IN class }
                    if HasImm(Op2) then
                         GetOperandType:=IMMEDIATE_PORT
                    else
                         GetOperandType:=PORT_ADDRESS_IN_DX;
                    Op:=Op1
               End;
          8:   Begin            { OUT class }
                    if HasImm(Op1) then
                         GetOperandType:=IMMEDIATE_PORT
                    else
                         GetOperandType:=PORT_ADDRESS_IN_DX;
                    Op:=Op2
               End;
          9:   Begin            { MUL,DIV, and shift class }
                    GetOperandType:=REGISTER_MEMORY
               End;
          10:  Begin            { ESC class }
                    GetOperandType:=ESC
               End;
          11:  Begin            { PUSH/POP class }
                    if HasSR(Op1) then
                         GetOperandType:=SEGMENT_REGISTER
                    else
                    if Has16bitReg(Op1) then
                         GetOperandType:=A16_BIT_REGISTER
                    else
                         GetOperandType:=REGISTER_MEMORY
               End;
          12:  Begin            { INC/DEC class }
                    if Has16bitReg(Op1) then
                         GetOperandType:=A16_BIT_REGISTER
                    else
                         GetOperandType:=REGISTER_MEMORY
               End;
          13:  Begin            { All regular instructions class }
                    if (HasMemReg(Op1)) and (HasMemReg(Op2)) then
                         GetOperandType:=REG_MEM_REGISTER
                    else
                    if (HasImm(Op2)) and (HasMemReg(Op1)) then
                         GetOperandType:=IMMEDIATE_REG_MEM
                    else
                    if (HasImm(Op2)) and (HasReg(Op1)=2) then
                         GetOperandType:=IMMEDIATE_AL_AX
               End;
          14:  Begin            { CALL and JMP class }
                    if (Mnemonic='JMP') and (IsShort(Op1)) then
                         GetOperandType:=EIGHT_BIT_REL
                    else
                    if (IsFar(Op1)) then
                    Begin
                         if (HasImm(Op1)) then
                              GetOperandType:=DIRECT_INTRASEGMENT
                         else
                              GetOperandType:=INDIRECT_INTRASEGMENT
                    End
                    Else
                    Begin
                         if (HasImm(Op1)) then
                              GetOperandType:=DIRECT_IN_SEGMENT
                         else
                              GetOperandType:=INDIRECT_IN_SEGMENT
                    End
               End
               else
               Begin
                     WriteLn(#7,'Internal error:  invalid class specified in GetOperandType.');
                     Halt
               End
     End
End;

Function GetDisp(Op:  string):  word;
{ Given an operand, Op, return a displacement or an immediate value, if either
  is used.  Otherwise, return 0.  Examples of legal values are as follows:
              23     --  Uses decimal, base 10
              23h    --  Uses hexadecimal, base 16
              0abcdh --  Uses hexadecimal, base 16
              23t    --  Uses decimal, base 10
              10111b --  Uses binary, base 2
}
Var
     i,
     LT:  integer;
     TmpString:  string;
     Base:  integer;
     Disp:  word;

Begin
     i:=1;
     While (i<=Length(Op)) and (not (op[i] in ['0'..'9'])) do
          inc(i);
     if i>Length(Op) then
          Disp:=0
     else
     Begin
          TmpString:=''; Base:=10; {assume 10}
          While (Op[i] in ['0'..'9','A'..'F','H','T']) and (i<=Length(Op)) do
          Begin
               if Op[i] in ['0'..'9','A'..'F'] then
                    TmpString:=TmpString+Op[i];
               if op[i]='H' then Base:=16;
               if op[i]='T' then Base:=10;
               inc(i)
          End;
          LT := Length(TmpString);
          if (TmpString[LT]='B') and (Base=10) then
          Begin
               Base:=2;
               TmpString:=copy(TmpString,1,TL-1);
          End;
          Case Base of
               2:  Begin
                        TmpString:='B'+TmpString;
                        Disp:=FromBin(TmpString)
                   End;
               10: Val(TmpString,Disp,Base);
               16: Begin
                        TmpString:='H'+TmpString;
                        Disp:=FromHex(TmpString)
                   End
          End
     End;
     GetDisp:=Disp
End;

Function OpSize(Operand:  string):  integer;
{Returns the size Operand in bits}
Var
     i:  integer;
     Tmp:  string;

Begin
     Tmp:=StripMem(Operand);
     OpSize:=8;  {assume 8}
     if Pos('WORD PTR',Tmp)<>0 then OpSize:=16;
     For i:=1 to 8 do
          if Pos(RegList[i],Tmp)<>0 then OpSize:=16;
     if hi(GetDisp(Tmp))<>0 then OpSize:=16
End;

Function RegCode(Operand:  string):  byte;
{Returns the register code of the operand, and 8 if there is no register code}
Var
     i:  integer;
     Done:  boolean;

Begin
     i:=1; Done:=FALSE;
     While (i<=MaxReg) and (not done) do
     Begin
          if Operand=RegList[i] then
               Done:=TRUE
          else
               inc(i)
     End;
     if not done then
          RegCode:=8
     else
          RegCode:=Pred(i) and 7
End;

Function GetSR(Op:  string):  byte;
{ Returns the segment register code of Op.  Defaults to ES, so use Function
  HasSR to make sure there is a segment register before using }
Begin
     GetSR:=0;
     if Op='ES' then GetSR:=0;
     if Op='CS' then GetSR:=1;
     if Op='SS' then GetSR:=2;
     if Op='DS' then GetSR:=3
End;

Procedure Update_Bits(Value:  word;  NoBits,StartBit:  byte;  Var St:  string;  Position:  integer);
{ Given St, a binary string of bit-info, update its bits using the bits
  from Value.  Start at position Position of St.  Start using the
  bit mask in Startbit.  Continue for NoBits bits.  (Confusing?  Its easier
  just to look at the code) }
Var
     i:  integer;

Begin
     For i:=1 to NoBits do
     Begin
          if Value and StartBit=StartBit then
               St[Position+i-1]:='1'
          else
               St[Position+i-1]:='0';
          StartBit:=StartBit shr 1
     End
End;

Procedure DecodeByte(First:  string;  Second:  byte;  Operand,Op1,Op2:  string);
{First is a string of bits that include optional character identifiers that
substitute actual bit values.  DecodeByte decodes this string using information
contained in Operand, Op1, & Op2 and stores the value in Bytes[1].  Second
is copied directly to Bytes[2] for POSSIBLE future use.

      Bit Identifiers:

           D:    if 0, register source, else register destination
           W:    if 0, operand is a byte, else operand is a word.
           SW:   if X0, data are a byte.  If 01, data are a word.
                 if 11, data are a low-order byte, but CPU inserts a high-order
                 byte, with all bits equal to the MSB of the low byte
           REG:  3-bit register field (use RegCode)
           BRG:  3-bit 16-bit register field (use RegCode)
           XXX:  3-bit field used with ESC
           LR:   2-bit segment register field
           V:    if 0, shift/rotate count is 1, else it is CL
}
Var
     i,n:  integer;
     Comma:  integer;
     reg:  byte;

Begin
     Comma:=Pos(',',Operand);
     Capitalize(First);
     BytePtr:=0;
     if First[1]='H' then
     Begin
          Bytes[1]:=FromHex(First);
          BytePtr:=2;
          Bytes[2]:=Second;
          if Second<>0 then inc(BytePtr);
          Exit
     End;
     i:=2;
     While i<=Length(First) do
     Begin
          Case First[i] of
               'D':  Begin
                          First[i]:='1';  {assume non-memory destination}
                          n:=Pos('[',Operand);
                          if (n>0) and (Comma>0) then
                               if n<Comma then First[i]:='0'
                     End;
               'W':  Begin
                          if OpSize(Operand)=8 then
                          Begin
                               First[i]:='0';
                               WordData:=FALSE
                          End
                          else
                          Begin
                               WordData:=TRUE;
                               First[i]:='1'
                          End
                     End;
               'S':  Begin
                          if OpSize(Operand)=8 then
                          Begin
                               First[i]:='0';
                               First[i+1]:='0';
                               WordData:=FALSE
                          End
                          Else
                          Begin
                               First[i]:='0';
                               First[i+1]:='1';
                               WordData:=TRUE
                          End;
                          if (OpSize(Op1)=16) and (OpSize(Op2)=8) then
                          Begin
                               First[i]:='1';
                               First[i+1]:='1';
                               WordData:=FALSE
                          End;
                          inc(i)
                     End;
               'R':  Begin
                          reg:=RegCode(Op1);
                          Update_Bits(reg,3,4,First,i);
                          Inc(i,2)
                     End;
               'B':  Begin
                          reg:=RegCode(Op1);
                          if (reg=0) or (reg=8) then reg:=RegCode(Op2);
                          Update_Bits(reg,3,4,First,i);
                          Inc(i,2)
                     End;
               'X':  Begin
                          reg:=GetDisp(Op2);
                          Update_Bits(reg,3,32,First,i);
                          Inc(i,2)
                     End;
               'L':  Begin
                          reg:=GetSR(Op1);
                          Update_Bits(reg,2,2,First,i);
                          Inc(i)
                     End;
               'V':  Begin
                          reg:=GetDisp(Op2);
                          if reg=1 then
                               First[i]:='0'
                          else
                               First[i]:='1'
                     End
          End;
          inc(i)
     End;
     Bytes[1]:=FromBin(First);
     BytePtr:=2
End;

Function GetSO(Op:  string):  byte;
{If there is a segment-override, return its machine-code value, else return 0}
Begin
     GetSO:=0;
     if Pos('ES:[',Op)<>0 then GetSO:=$26;
     if Pos('CS:[',Op)<>0 then GetSO:=$2e;
     if Pos('SS:[',Op)<>0 then GetSO:=$36;
     if Pos('DS:[',Op)<>0 then GetSO:=$3e
End;

Function ConstructSecByte(mode,reg,rm:  byte):  byte;
{Given the mod, reg, and r/m fields, construct the resulting second byte}
Begin
     ConstructSecByte:=mode shl 6+reg shl 3+rm
End;

Procedure GetMode(Var Mode,rm:  byte;  Op:  string);
{Finds the addressing mode of Op which is returned in the mod and r/m fields}
Var
     i:  integer;
     Regs:  byte;
     disp:  word;
     ErrorFlag:  boolean;

Begin
     disp:=GetDisp(Op);  {First, find a displacement if there is one}
     if Disp<>0 then
     Begin
          Bytes[3]:=Lo(Disp);
          BytePtr:=4;
          if Disp>127 then
          Begin
               Bytes[4]:=Hi(Disp);
               BytePtr:=5
          End
     End
     Else
          BytePtr:=3;
     i:=1; Regs:=0;
     if Pos('BP',Op)<>0 then Regs:=BP;
     if Pos('BX',Op)<>0 then Inc(Regs,BX);
     if Pos('SI',Op)<>0 then Inc(Regs,SI);
     if Pos('DI',Op)<>0 then Inc(Regs,DI);
     i:=1;
     While (i<=8) and (AddrModes[i]<>Regs) do inc(i);
     if (Regs<>0) and (i>8) then
     Begin
          WriteLn(#7,'*** Illegal use of index registers.');
     End;
     if i>8 then
     Begin
          rm:=6;
          Mode:=0;
          Bytes[3]:=Lo(Disp);
          Bytes[4]:=Hi(Disp);
          BytePtr:=5
     End
     Else
     Begin
          rm:=pred(i);
          if disp=0 then mode:=0 else mode:=1;
          if disp>127 then mode:=2
     End
End;

Procedure Assemble(Instruct:  string);
{ Given an instruction, Instruct, return the resulting machine-language
  equivalent in the global Bytes[] array if there is one.  Otherwise an
  error will result.  Due to poor error checking, many errors WILL NOT
  be picked up, and the resulting bytes may possibly be erroneous.
  For instance, version 1.20 will not report AND AL,BX as an error but will
  instead return opcodes equivalent to AND AX,BX.  Similarly, the instruction
  MOV AL,WORD PTR 6, will generate code for the instruction MOV AX,6 }
Var
     Mnemonic:  string[8];
     OperandType,SecondByte:  byte;
     Operand,Op1,Op2,ByteField:  string;
     Tmp:  string;
     RegCode1,RegCode2:  byte;
     disp:  word;
     mode,reg,rm,SO:  byte;
     data:  word;
     i:  integer;

Procedure ModeRMdisp;
Begin
     GetMode(mode,rm,Op1);
     reg:=SecondByte;
     Bytes[2]:=ConstructSecByte(Mode,reg,rm)
End;

Procedure RegisterMemory;
Begin
     RegCode1:=RegCode(Op1);
     if RegCode1=8 then
          ModeRMdisp
     else
     Begin
          Mode:=3;
          reg:=SecondByte;
          rm:=RegCode1;
          Bytes[2]:=ConstructSecByte(Mode,reg,rm);
          BytePtr:=3
     End
End;

Function EightBitRelJump(Addr:  word):  byte;
Var
     IP:  word;

Begin
     IP:=InstructionAddr+2;
     if Addr<IP then
          EightBitRelJump:=256-(IP-Addr)
     else
          EightBitRelJump:=Addr-IP
End;

Function A16BitRelJump(Addr:  word):  word;
Var
     IP:  word;

Begin
     IP:=InstructionAddr+3;
     if Addr<IP then
          A16BitRelJump:=Succ($ffff-(IP-Addr))
     else
          A16BitRelJump:=Addr-IP
End;


Begin  {Assemble}
     Capitalize(Instruct);
     ExtendedInstruction:=FALSE;
     Repeat
     WordData:=FALSE;
     Mnemonic:=NextPart(Instruct,' ');
     Operand:=Instruct;
     SO:=GetSO(Operand);
     if SO<>0 then
     Begin
          LastByte:=SO;
          ExtendedInstruction:=TRUE
     End;
     OperandType:=GetOperandType(Mnemonic,Operand,Op1,Op2);
     i:=CurrentInstruct;
     While (i<=ChartPtr) and ((Chart[i].Mnem<>Mnemonic) or
           (Chart[i].OpType<>OperandType)) do
                inc(i);
     if i>ChartPtr then
     Begin
           WriteLn(#7,'*** Syntax Error in instruction');
           Exit
     End;
     ByteField:=Chart[i].Byte1;
     SecondByte:=Chart[i].Byte2;
     DecodeByte(ByteField,SecondByte,Operand,Op1,Op2);

     Case OperandType of
          ANOTHER_INSTRUCTION:
               Begin
                    LastByte:=Bytes[1];
                    if Operand='' then
                         OperandType:=NO_OPERAND
                    else
                         Instruct:=Operand
               End;
          REG_MEM_REGISTER:
               Begin
                    RegCode1:=RegCode(Op1);
                    RegCode2:=RegCode(Op2);
                    if RegCode1=8 then
                    Begin
                         GetMode(Mode,rm,Op1);
                         reg:=RegCode2
                    End;
                    if RegCode2=8 then
                    Begin
                         GetMode(Mode,rm,Op2);
                         reg:=RegCode1
                    End;
                    if (RegCode1<>8) and (RegCode2<>8) then
                    Begin
                         Mode:=3;
                         Reg:=RegCode1;
                         rm:=RegCode2;
                         BytePtr:=3
                    End;
                    Bytes[2]:=ConstructSecByte(Mode,reg,rm)
               End;
          IMMEDIATE_REG_MEM:
               Begin
                    data:=GetDisp(Op2);
                    RegCode1:=RegCode(Op1);
                    if RegCode1<>8 then
                    Begin
                         mode:=3;
                         reg:=SecondByte;
                         rm:=RegCode1;
                         Bytes[3]:=lo(data);
                         BytePtr:=4;
                         if WordData then
                         Begin
                              Bytes[4]:=hi(data);
                              BytePtr:=5
                         End
                    End
                    else
                    Begin
                         GetMode(mode,rm,Op1);
                         reg:=SecondByte;
                         Bytes[BytePtr]:=lo(data);
                         inc(BytePtr);
                         if WordData then
                         Begin
                              Bytes[BytePtr]:=hi(data);
                              inc(BytePtr)
                         End
                    End;
                    Bytes[2]:=ConstructSecByte(Mode,reg,rm)
               End;
          IMMEDIATE_AL_AX:
               Begin
                    data:=GetDisp(Op2);
                    Bytes[2]:=lo(Data);
                    BytePtr:=3;
                    if WordData then
                    Begin
                         Bytes[3]:=hi(Data);
                         BytePtr:=4
                    End
               End;
          EIGHT_BIT_REL:
               Begin
                    BytePtr:=3;
                    Bytes[2]:=EightBitRelJump(GetDisp(Op1))
               End;
          DIRECT_IN_SEGMENT:
               Begin
                    Bytes[2]:=Lo(A16BitRelJump(GetDisp(Op1)));
                    Bytes[3]:=Hi(A16BitRelJump(GetDisp(Op1)));
                    BytePtr:=4
               End;
          INDIRECT_IN_SEGMENT:
               ModeRMdisp;
          DIRECT_INTRASEGMENT:
               Begin
                    While (not (Op1[1] in ['0'..'9'])) and (length(Op1)>1) do
                         Op1:=Copy(Op1,2,length(Op1)-1);
                    data:=pos(':',Op1);
                    if data=0 then
                    Begin
                         Op1:='H'+Op1;
                         Bytes[2]:=Lo(FromHex(Op1));
                         Bytes[3]:=Hi(FromHex(Op2));
                         Bytes[4]:=0;
                         Bytes[5]:=0;
                         BytePtr:=6
                    End
                    Else
                    Begin
                         Tmp:='H'+Copy(Op1,data+1,length(Op1));
                         Op1:='H'+Op1;
                         Bytes[2]:=Lo(FromHex(Tmp));
                         Bytes[3]:=Hi(FromHex(Tmp));
                         Bytes[4]:=Lo(FromHex(Op1));
                         Bytes[5]:=Hi(FromHex(Op1));
                         BytePtr:=6
                    End
               End;
          INDIRECT_INTRASEGMENT:
               ModeRMdisp;
          REGISTER_MEMORY:
               RegisterMemory;
          ESC:
               Begin
                    SecondByte:=GetDisp(Op2) and 7;
                    RegisterMemory
               End;
          IMMEDIATE_PORT:
               Begin
                    if Mnemonic='IN' then
                         data:=GetDisp(Op2)
                    else
                         data:=GetDisp(Op1);
                    Bytes[2]:=data;
                    BytePtr:=3
               End;
          INT:
               Begin
                    data:=GetDisp(Op1);
                    if data=3 then
                         dec(Bytes[1])
                    else
                    Begin
                         Bytes[2]:=data;
                         BytePtr:=3
                    End
               End;
          IMMEDIATE_REGISTER:
               Begin
                    data:=GetDisp(Op2);
                    Bytes[2]:=lo(data);
                    BytePtr:=3;
                    if WordData then
                    Begin
                         Bytes[3]:=Hi(data);
                         BytePtr:=4
                    End
               End;
          MEMORY_AL_AX:
               Begin
                    data:=GetDisp(Op2);
                    Bytes[2]:=lo(data);
                    Bytes[3]:=hi(data);
                    BytePtr:=4
               End;
          AL_AX_MEMORY:
               Begin
                    data:=GetDisp(Op1);
                    Bytes[2]:=lo(data);
                    Bytes[3]:=hi(data);
                    BytePtr:=4
               End;
          REG_MEM_SR:
               Begin
                    RegCode1:=RegCode(Op2);
                    if RegCode1=8 then
                    Begin
                         GetMode(mode,rm,Op2);
                         reg:=GetSR(Op1)
                    End
                    else
                    Begin
                         mode:=3;
                         reg:=GetSR(Op1);
                         rm:=RegCode1;
                         BytePtr:=3
                    End;
                    Bytes[2]:=ConstructSecByte(mode,reg,rm)
               End;
          SR_REG_MEM:
               Begin
                    RegCode1:=RegCode(Op1);
                    if RegCode1=8 then
                    Begin
                         GetMode(mode,rm,Op1);
                         reg:=GetSR(op2)
                    end
                    else
                    Begin
                         mode:=3;
                         reg:=GetSR(op2);
                         rm:=RegCode1;
                         BytePtr:=3
                    End;
                    Bytes[2]:=ConstructSecByte(mode,reg,rm)
               End;
          RET:
               Begin
                    data:=GetDisp(Op1);
                    Bytes[2]:=lo(data);
                    Bytes[3]:=hi(data);
                    BytePtr:=4
               End
     End;
     if OperandType=ANOTHER_INSTRUCTION then
          ExtendedInstruction:=TRUE

     Until OperandType<>ANOTHER_INSTRUCTION;
     if ExtendedInstruction then
     Begin
          For i:=BytePtr-1 downto 1 do Bytes[i+1]:=Bytes[i];
          Bytes[1]:=LastByte;
          inc(BytePtr)
     End
End;

Begin { Unit initialization }
      Assign(InstFile,'mnemonic.bin');
      Reset(InstFile);
      Read(InstFile,Chart);
      Close(InstFile);
      ChartPtr:=1;
      While Chart[ChartPtr].Mnem<>'ENDOFLIS' do inc(ChartPtr);
      dec(ChartPtr);
      InstructionAddr:=0
End.

