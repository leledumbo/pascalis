unit VSComputerGameAI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections, Math, fgl;

type
  TGameNode = class;

  { TNextStates }

  TNextStates = class(specialize TFPGObjectList<TGameNode>)
  public
    constructor Create;
  end;

  { TNodeStack
    Kept for backwards compatibility; the search implementation no longer
    needs an explicit path stack. }

  TNodeStack = class(specialize TStack<TGameNode>)
  end;

  { TGameNode }

  TGameNode = class
  private
    FNextStatesGenerated: Boolean;
    function GetNextStates: TNextStates;
  protected
    FValue: Integer;
    FNextStates: TNextStates;
    procedure GenerateNextStates; virtual; abstract;
    function GetHeuristicValue: Integer; virtual; abstract;
  public
    property NextStates: TNextStates read GetNextStates;
    property Value: Integer read GetHeuristicValue write FValue;
    constructor Create;
    destructor Destroy; override;
    function IsTerminal: Boolean; virtual; abstract;
  end;

  TSearchFunction = procedure (const ADepth: Integer) of object;

  { TGameTree }

  TGameTree = class
  private
    FRoot: TGameNode;
    FCurrentState: TGameNode;
    function MiniMaxValue(const ANode: TGameNode; const ADepth: Integer;
      const AMaximizePlayer: Boolean): Integer;
    function AlphaBetaValue(const ANode: TGameNode; const ADepth: Integer;
      AAlpha, ABeta: Integer; const AMaximizePlayer: Boolean): Integer;
  public
    property Root: TGameNode read FRoot;
    property CurrentState: TGameNode read FCurrentState write FCurrentState;
    constructor Create(const ARoot: TGameNode);
    destructor Destroy; override;
    procedure MiniMax(const ADepth: Integer);
    procedure AlphaBetaPruning(const ADepth: Integer);
  end;

  { TGame }

  TGame = class
  private
    FTree: TGameTree;
  protected
    FDifficulty: Integer;
    FComputerFirst: Boolean;
    FUseAlphaBetaPruning: Boolean;
  public
    function GetInitialState: TGameNode; virtual; abstract;
    procedure OnTurnChange(AState: TGameNode); virtual; abstract;
    procedure OnComputerMove(AState: TGameNode); virtual; abstract;
    procedure OnPlayerMove(var AState: TGameNode); virtual; abstract;
    procedure OnGameOver(AState: TGameNode); virtual; abstract;
    procedure Play;
  end;

implementation

{ TNextStates }

constructor TNextStates.Create;
begin
  inherited Create(True);
end;

{ TGameNode }

constructor TGameNode.Create;
begin
  FNextStates := TNextStates.Create;
  FNextStatesGenerated := false;
end;

destructor TGameNode.Destroy;
begin
  FNextStates.Free;
  inherited Destroy;
end;

function TGameNode.GetNextStates: TNextStates;
begin
  // Generate next states just once per node: faster execution and smaller
  // memory footprint.
  if not FNextStatesGenerated then begin
    GenerateNextStates;
    FNextStatesGenerated := true;
  end;
  Result := FNextStates;
end;

{ TGameTree }

constructor TGameTree.Create(const ARoot: TGameNode);
begin
  FRoot := ARoot;
  FCurrentState := FRoot;
end;

destructor TGameTree.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TGameTree.MiniMaxValue(const ANode: TGameNode;
  const ADepth: Integer; const AMaximizePlayer: Boolean): Integer;
var
  LValue: Integer;
  LNode: TGameNode;
begin
  if (ADepth <= 0) or ANode.IsTerminal then
    Result := ANode.Value
  else begin
    if AMaximizePlayer then begin
      Result := -MaxInt;
      for LNode in ANode.NextStates do begin
        LValue := MiniMaxValue(LNode, ADepth - 1, false);
        if LValue > Result then
          Result := LValue;
      end;
    end else begin
      Result := MaxInt;
      for LNode in ANode.NextStates do begin
        LValue := MiniMaxValue(LNode, ADepth - 1, true);
        if LValue < Result then
          Result := LValue;
      end;
    end;
  end;
end;

function TGameTree.AlphaBetaValue(const ANode: TGameNode; const ADepth: Integer;
  AAlpha, ABeta: Integer; const AMaximizePlayer: Boolean): Integer;
var
  LValue: Integer;
  LNode: TGameNode;
begin
  if (ADepth <= 0) or ANode.IsTerminal then
    Result := ANode.Value
  else if AMaximizePlayer then begin
    Result := -MaxInt;
    for LNode in ANode.NextStates do begin
      LValue := AlphaBetaValue(LNode, ADepth - 1, AAlpha, ABeta, false);
      if LValue > Result then
        Result := LValue;
      if Result > AAlpha then
        AAlpha := Result;
      if ABeta <= AAlpha then
        Break;
    end;
  end else begin
    Result := MaxInt;
    for LNode in ANode.NextStates do begin
      LValue := AlphaBetaValue(LNode, ADepth - 1, AAlpha, ABeta, true);
      if LValue < Result then
        Result := LValue;
      if Result < ABeta then
        ABeta := Result;
      if ABeta <= AAlpha then
        Break;
    end;
  end;
end;

procedure TGameTree.MiniMax(const ADepth: Integer);
var
  LValue, LBestValue: Integer;
  LNode, LBestNode: TGameNode;
begin
  // The search is performed when it is the computer's turn, so the computer
  // is the maximizing player at the root of the tree.
  LBestNode := nil;
  LBestValue := -MaxInt;
  for LNode in FCurrentState.NextStates do begin
    LValue := MiniMaxValue(LNode, ADepth - 1, false);
    if LValue > LBestValue then begin
      LBestValue := LValue;
      LBestNode := LNode;
    end;
  end;
  if LBestNode <> nil then
    FCurrentState := LBestNode;
end;

procedure TGameTree.AlphaBetaPruning(const ADepth: Integer);
var
  LValue, LAlpha, LBestValue: Integer;
  LNode, LBestNode: TGameNode;
begin
  // The search is performed when it is the computer's turn, so the computer
  // is the maximizing player at the root of the tree.
  LBestNode := nil;
  LBestValue := -MaxInt;
  LAlpha := -MaxInt;
  for LNode in FCurrentState.NextStates do begin
    LValue := AlphaBetaValue(LNode, ADepth - 1, LAlpha, MaxInt, false);
    if LValue > LBestValue then begin
      LBestValue := LValue;
      LBestNode := LNode;
    end;
    if LBestValue > LAlpha then
      LAlpha := LBestValue;
  end;
  if LBestNode <> nil then
    FCurrentState := LBestNode;
end;

{ TGame }

procedure TGame.Play;
var
  LSearchFunction: TSearchFunction;
  LIsComputerMove: Boolean;
  LState: TGameNode;
begin
  FTree := TGameTree.Create(GetInitialState);
  try
    if FUseAlphaBetaPruning then
      LSearchFunction := @FTree.AlphaBetaPruning
    else
      LSearchFunction := @FTree.MiniMax;

    LIsComputerMove := FComputerFirst;
    OnTurnChange(FTree.CurrentState);
    repeat
      if LIsComputerMove then begin
        OnComputerMove(FTree.CurrentState);
        LSearchFunction(FDifficulty);
      end else begin
        LState := FTree.CurrentState;
        OnPlayerMove(LState);
        FTree.CurrentState := LState;
      end;
      LIsComputerMove := not LIsComputerMove;
      OnTurnChange(FTree.CurrentState);
    until FTree.CurrentState.IsTerminal;
    OnGameOver(FTree.CurrentState);
  finally
    FTree.Free;
  end;
end;

end.
