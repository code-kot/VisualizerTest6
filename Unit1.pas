unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.Direct2D, Winapi.D2D1, Vcl.ExtCtrls, Vcl.Imaging.pngimage,
  System.DateUtils, System.Types,

  DirectPaintBox, DataGenerator;

type
  TForm1 = class(TForm)
    img1: TImage;
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    { Private declarations }
    FPaintBox: TDirectPaintBox;
    FDataGeneratorThread: TDataGeneratorThread;

    procedure FreeDataGeneratorThread;
    procedure CreatePaintBox;
  protected
    procedure CreateWnd; override;
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

{ TForm1 }

procedure TForm1.CreateWnd;
begin
  inherited CreateWnd;

  CreatePaintBox;
end;

procedure TForm1.CreatePaintBox;
begin
  FPaintBox := TDirectPaintBox.Create(Self);
  FPaintBox.Parent := Self;
  FPaintBox.Align := alClient;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FreeDataGeneratorThread;
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_SPACE then
  begin
    FreeDataGeneratorThread;
    FDataGeneratorThread := TDataGeneratorThread.Create(img1.Picture.Graphic, FPaintBox);
    FDataGeneratorThread.Priority := tpTimeCritical;
  end
  else
  if Key = VK_ESCAPE then
  begin
    FreeDataGeneratorThread;
  end;
end;

procedure TForm1.FreeDataGeneratorThread;
begin
  if Assigned(FDataGeneratorThread) then
  begin
    FDataGeneratorThread.Terminate;
    FDataGeneratorThread.WaitFor;
    FreeAndNil(FDataGeneratorThread);
  end;
end;

end.
