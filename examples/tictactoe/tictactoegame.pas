unit TicTacToeGame;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

interface

uses
  VSComputerGameAI;

type

  TPlayer = (plPlayer, plComputer);

  { TTicTacToeGame }

  TTicTacToeGame = class(TGame)
  private
    FStartingPlayer: TPlayer;
    FPlayerMark: Char;
  public
    function GetInitialState: TGameNode; override;
    procedure OnTurnChange(AState: TGameNode); override;
    procedure OnComputerMove(AState: TGameNode); override;
    procedure OnPlayerMove(var AState: TGameNode); override;
    procedure OnGameOver(AState: TGameNode); override;
  end;

implementation

uses
  SysUtils;

const
  BoardSize = 3;

type
  // 1-dimensional array is easier to work with, after all there's
  // an equivalence formula to map to 2-dimensional array:
  // Board[i,j] = Board[i * BoardSize + j]
  TBoard = array [0 .. BoardSize * BoardSize - 1] of Char;

  {$ifdef DEBUG}
  { TBoardHelper }

  TBoardHelper = type helper for TBoard
    function ToString: String;
  end;
  {$endif DEBUG}

const
  EmptyBoard: TBoard = (
    ' ', ' ', ' ',
    ' ', ' ', ' ',
    ' ', ' ', ' '
  );

  // 8 possible ways to win
  WinningStates: array [0 .. 7, 0 .. 2] of Integer = (
    // horizontal
    (0, 1, 2),
    (3, 4, 5),
    (6, 7, 8),
    // vertical
    (0, 3, 6),
    (1, 4, 7),
    (2, 5, 8),
    // diagonal
    (0, 4, 8),
    (2, 4, 6)
  );

  // How many plies the AI looks ahead on each difficulty. The search always
  // starts on the AI's own turn, so:
  //   easy       : 2 plies (1 if the human starts)
  //   normal     : 4 plies (3 if the human starts)
  //   hard       : 6 plies (5 if the human starts)
  //   unbeatable : 9 plies (8 if the human starts; enough for the whole game)
  BaseDepth: array [1 .. 4] of Integer = (2, 4, 6, 9);

function BoardToString(const Board: TBoard; const IndentStr: String): String;
begin
  Result := Format
          ( IndentStr + '+---+---+---+' + LineEnding
          + IndentStr + '| %s | %s | %s |' + LineEnding
          + IndentStr + '+---+---+---+' + LineEnding
          + IndentStr + '| %s | %s | %s |' + LineEnding
          + IndentStr + '+---+---+---+' + LineEnding
          + IndentStr + '| %s | %s | %s |' + LineEnding
          + IndentStr + '+---+---+---+'
          ,
          [
            Board[0],  Board[1], Board[2],
            Board[3],  Board[4], Board[5],
            Board[6],  Board[7], Board[8]
          ]
  );
end;

function OppositeMark(const AMark: Char): Char; inline;
begin
  if AMark = 'X' then
    Result := 'O'
  else
    Result := 'X';
end;

type

  {
    TTicTacToeNode
    Describes a state of the game made from 3 properties:
    - Current board condition (FBoard)
    - Player that is going to move (FPlayer)
    - Mark character used by that player (FMarkChar)
  }

  TTicTacToeNode = class(TGameNode)
  private
    FBoard: TBoard;
    FPlayer: TPlayer;
    FMarkChar: Char;
  public
    property Board: TBoard read FBoard;
    property Player: TPlayer read FPlayer;
    function GetWinner: Char;
    function IsTerminal: boolean; override;
    function GetHeuristicValue: Integer; override;
    procedure GenerateNextStates; override;
    constructor Create(const ABoard: TBoard; const APlayer: TPlayer; const AMarkChar: Char);
  end;


{$ifdef DEBUG}
{ TBoardHelper }

function TBoardHelper.ToString: String;
var
  i: Integer;
  c: Char;
begin
  Result := '[';
  for i := Low(Self) to High(Self) do begin
    Result := Result + '"' + Self[i] + '"';
    if i < High(Self) then c := ',' else c := ']';
    Result := Result + c;
  end;
end;
{$endif DEBUG}

{ TTicTacToeNode }

constructor TTicTacToeNode.Create(const ABoard: TBoard; const APlayer: TPlayer; const AMarkChar: Char);
begin
  inherited Create;
  FBoard := ABoard;
  FPlayer := APlayer;
  FMarkChar := AMarkChar;
end;

function TTicTacToeNode.GetWinner: Char;
var
  i, j: Integer;
  m: Char;
  AllSame: Boolean;
begin
  Result := ' ';
  for m in ['X', 'O'] do
    for i := Low(WinningStates) to High(WinningStates) do begin
      AllSame := true;
      for j := Low(WinningStates[i]) to High(WinningStates[i]) do
        if FBoard[WinningStates[i][j]] <> m then begin
          AllSame := false;
          Break;
        end;
      if AllSame then
        Exit(m);
    end;
end;

function TTicTacToeNode.IsTerminal: Boolean;
var
  i: Integer;
begin
  Result := GetWinner <> ' ';
  if not Result then begin
    // No winner yet: terminal only when the board is full (draw).
    Result := true;
    for i := Low(FBoard) to High(FBoard) do
      if FBoard[i] = ' ' then begin
        Result := false;
        Break;
      end;
  end;
end;

function TTicTacToeNode.GetHeuristicValue: Integer;
const
  WinScore = 10000;
var
  i, j: Integer;
  AIMark, HumanMark, Winner: Char;
  ACount, HCount: Integer;
  A1, A2, H1, H2: Integer;
begin
  // The node stores the mark of the player to move. The computer (AI) is
  // either that player or the opponent, so derive both marks from the
  // player-to-move information. The value is always given from the AI's point
  // of view (positive is good for the AI), matching the maximizing player in
  // the minimax/alpha-beta search.
  if FPlayer = plComputer then
    AIMark := FMarkChar
  else
    AIMark := OppositeMark(FMarkChar);
  HumanMark := OppositeMark(AIMark);

  Winner := GetWinner;
  if Winner = AIMark then
    FValue := WinScore
  else if Winner = HumanMark then
    FValue := -WinScore
  else begin
    // E(s) = 3 * (A2 - H2) + (A1 - H1), where A_n (H_n) is the number of
    // still-open winning lines containing exactly n AI (human) marks. A line
    // is still open for a side when it contains no mark of the opponent.
    A1 := 0; A2 := 0; H1 := 0; H2 := 0;
    for i := Low(WinningStates) to High(WinningStates) do begin
      ACount := 0;
      HCount := 0;
      for j := Low(WinningStates[i]) to High(WinningStates[i]) do begin
        if FBoard[WinningStates[i][j]] = AIMark then
          Inc(ACount)
        else if FBoard[WinningStates[i][j]] = HumanMark then
          Inc(HCount);
      end;
      if HCount = 0 then begin
        // Still open for the AI.
        if ACount = 1 then Inc(A1)
        else if ACount = 2 then Inc(A2);
      end else if ACount = 0 then begin
        // Still open for the human.
        if HCount = 1 then Inc(H1)
        else if HCount = 2 then Inc(H2);
      end;
    end;
    FValue := 3 * (A2 - H2) + (A1 - H1);
  end;
  Result := FValue;
end;

procedure TTicTacToeNode.GenerateNextStates;
var
  NextPlayer: TPlayer;
  NextPlayerMark: Char;
  i: Integer;
  TempBoard: TBoard;
begin
  if FPlayer = plPlayer then NextPlayer := plComputer else NextPlayer := plPlayer;
  if FMarkChar = 'X' then NextPlayerMark := 'O' else NextPlayerMark := 'X';

  if not IsTerminal then begin
    for i := Low(TBoard) to High(TBoard) do
      // If an empty cell is found, fill it
      if FBoard[i] = ' ' then begin
        TempBoard := FBoard;
        TempBoard[i] := FMarkChar;
        // and add as one of next possible states
        FNextStates.Add(TTicTacToeNode.Create(TempBoard, NextPlayer, NextPlayerMark));
      end;
  end;
end;

{ TTicTacToeGame }

function TTicTacToeGame.GetInitialState: TGameNode;
var
  InputLine: String;
  Err: Word;
  InputError: Boolean;
  DifficultyChoice: Integer;
begin
  WriteLn('Computer difficulty:');
  WriteLn('(1) Easy       - looks 1-2 moves ahead');
  WriteLn('(2) Normal     - looks 3-4 moves ahead');
  WriteLn('(3) Hard       - looks 5-6 moves ahead');
  WriteLn('(4) Unbeatable - looks 8-9 moves ahead');
  repeat
    Write('Your choice (type the number in brackets): ');
    ReadLn(InputLine);
    Val(InputLine, DifficultyChoice, Err);
    InputError := (Err <> 0) or not (DifficultyChoice in [1, 2, 3, 4]);
    if InputError then WriteLn('Incorrect choice, please type 1, 2, 3 or 4!');
  until not InputError;
  FDifficulty := BaseDepth[DifficultyChoice];

  repeat
    Write('Do you want to use alpha-beta pruning? [Y]es/[N]o: ');
    ReadLn(InputLine);
    InputError := (Length(InputLine) < 1) or not(UpCase(InputLine[1]) in ['Y','N']);
    if InputError then WriteLn('Incorrect choice, please type yes or no!');
  until not InputError;
  FUseAlphaBetaPruning := UpCase(InputLine[1]) = 'Y';

  repeat
    Write('Do you want to go first? [Y]es/[N]o: ');
    ReadLn(InputLine);
    InputError := (Length(InputLine) < 1) or not(UpCase(InputLine[1]) in ['Y','N']);
    if InputError then WriteLn('Incorrect choice, please type yes or no!');
  until not InputError;
  FComputerFirst := UpCase(InputLine[1]) = 'N';
  if FComputerFirst then begin
    FStartingPlayer := plComputer;
    FPlayerMark := 'O';
  end else begin
    FStartingPlayer := plPlayer;
    FPlayerMark := 'X';
    // Human moves first, so the AI is one ply behind and looks at one ply
    // less than the nominal depth of the chosen difficulty.
    Dec(FDifficulty);
  end;

  Result := TTicTacToeNode.Create(EmptyBoard, FStartingPlayer, 'X');
end;

procedure TTicTacToeGame.OnTurnChange(AState: TGameNode);
begin
  WriteLn(BoardToString(TTicTacToeNode(AState).Board, ''));
end;

procedure TTicTacToeGame.OnComputerMove(AState: TGameNode);
begin
  WriteLn('Computer move:');
end;

procedure TTicTacToeGame.OnPlayerMove(var AState: TGameNode);

  procedure GetXY(out X, Y: integer);

    procedure GetOne(const Name: char; out V: integer);
    var
      SV: string;
      E: word;
    begin
      repeat
        Write(Name + ' (1-', BoardSize, '): ');
        ReadLn(SV);
        V := 0;
        Val(SV, V, E);
        if E <> 0 then
          WriteLn(ErrOutput, 'Invalid digit at position ', E);
        if not (V in [1..BoardSize]) then
        begin
          WriteLn(ErrOutput, Name + ' must be in range 1-', BoardSize);
          E := 1;
        end;
      until E = 0;
    end;

  begin
    GetOne('X', X);
    GetOne('Y', Y);
  end;

  function IsMarkable(const X, Y: Integer): Boolean; inline;
  begin
    IsMarkable := TTicTacToeNode(AState).Board[(X - 1) * BoardSize + (Y - 1)] = ' ';
  end;

var
  X, Y: integer;
  i: integer;
  TempBoard: TBoard;
begin
  WriteLn('Player move:');
  TempBoard := TTicTacToeNode(AState).Board;
  repeat
    GetXY(X, Y);
    if not IsMarkable(X, Y) then
      WriteLn(ErrOutput, 'Position ', X, ',', Y, ' is not markable');
  until IsMarkable(X, Y);
  TempBoard[(X - 1) * BoardSize + (Y - 1)] := FPlayerMark;

  // Move to next state whose board equals TempBoard (AState.Board +
  // player choice)
  for i := 0 to AState.NextStates.Count - 1 do begin
    if TTicTacToeNode(AState.NextStates[i]).Board = TempBoard then begin
      AState := AState.NextStates[i];
      Exit;
    end;
  end;
end;

procedure TTicTacToeGame.OnGameOver(AState: TGameNode);
var
  Node: TTicTacToeNode;
begin
  Node := TTicTacToeNode(AState);
  if Node.GetWinner = ' ' then
    WriteLn('Draw!')
  else
    // A terminal node's Player field holds the player who would move next,
    // i.e. the loser.
    case Node.Player of
      plPlayer: WriteLn('You lose!');
      plComputer: WriteLn('You win!');
    end;
end;

end.
