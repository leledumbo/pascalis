program tictactoe;

{$mode objfpc}

uses
  TicTacToeGame;

begin
  with TTicTacToeGame.Create do
    try
      Play;
    finally
      Free;
    end;
end.
