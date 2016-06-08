program VisualizerTest6;

uses
{$IFDEF DEBUG}
  FastMM4,
  FastMM4Messages,
{$ENDIF }
  Vcl.Forms,
  Unit1 in 'Unit1.pas' {Form1},
  DataGenerator in 'DataGenerator.pas',
  Frame in 'Frame.pas',
  DirectPaintBox in 'DirectPaintBox.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
