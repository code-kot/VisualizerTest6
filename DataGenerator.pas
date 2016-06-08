unit DataGenerator;

interface

uses
  System.Classes, Vcl.Graphics, System.SyncObjs, System.SysUtils, Winapi.Ole2,
  Winapi.Windows, Winapi.MMSystem, System.DateUtils, System.Math, System.Types,

  Frame, DirectPaintBox;

type
  TDataGeneratorThread = class(TThread)
  private
    FPerformanceFrequency: Int64;  // ticks per second

    FTerminatedEvent: TEvent;
    FSourceBitmap: TBimapData;
    FFrameBitmap: TFrameData;
    FFrameBitmapLock: TCriticalSection;
    FFrameStartPosition: Double;
    FFrameStartPositionInt: Integer;
    FPaintBox: TDirectPaintBox;

    procedure ShiftFrame(Delta: Integer);
    function GetFrame: TFrameData;
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
    procedure Render;
  public
    constructor Create(Graphic: TGraphic; APaintBox: TDirectPaintBox);
    destructor Destroy; override;

    property Frame: TFrameData read GetFrame;
  end;

implementation

const
  FRAME_WIDTH = 1500;
  FRAME_TIME = 1000.0/60; // ms for 1 frame
  COLUMN_TIME = 4.2; // ms for 1 new column
  COLUMNS_PER_MS = 1/COLUMN_TIME; // new columns per 1 ms
//  FRAME_STEP = 4;
  FRAME_STEP = FRAME_TIME / COLUMN_TIME; // new columns per frame time

{ TDataGeneratorThread }

constructor TDataGeneratorThread.Create(Graphic: TGraphic; APaintBox: TDirectPaintBox);
var
  i, j: Integer;
  Bitmap: Vcl.Graphics.TBitmap;
  BitmapLinesArray: array of PIntegerArray;
begin
  inherited Create;

  FTerminatedEvent := TEvent.Create(nil, True, False, '');
  FFrameBitmapLock := TCriticalSection.Create;

  Bitmap := Vcl.Graphics.TBitmap.Create;
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.Assign(Graphic);

    SetLength(BitmapLinesArray, Bitmap.Height);
    for i := 0 to Bitmap.Height - 1 do
      BitmapLinesArray[i] := Bitmap.ScanLine[i];

    SetLength(FSourceBitmap, Bitmap.Width);
    for i := 0 to Length(FSourceBitmap) - 1 do
    begin
      SetLength(FSourceBitmap[i], Bitmap.Height);
      for j := 0 to Length(FSourceBitmap[i]) - 1 do
        FSourceBitmap[i][j] := BitmapLinesArray[j][i];
    end;
  finally
    Bitmap.Free;
  end;

  SetLength(FFrameBitmap, FRAME_WIDTH);
  for i := 0 to Length(FFrameBitmap) - 1 do
    FFrameBitmap[i] := @FSourceBitmap[i];

  FPaintBox := APaintBox;
end;

destructor TDataGeneratorThread.Destroy;
begin
  FreeAndNil(FTerminatedEvent);
  FreeAndNil(FFrameBitmapLock);

  inherited Destroy;
end;

procedure TDataGeneratorThread.Execute;
var
  ShiftDelta: Double;
  ElapsedTime: Double;  // ms
  ShiftsCount: Cardinal;
  PreviousTicks, CurrentTicks: Int64;
//  TimeFromLastShift: Double; // ms
begin
  NameThreadForDebugging(ClassName);
  { Place thread code here }
  QueryPerformanceFrequency(FPerformanceFrequency);

  CoInitialize(nil);
  try
    QueryPerformanceCounter(PreviousTicks);
//    TimeFromLastShift := 0;
    Render;

//    timeBeginPeriod(1);
    try
      while not Terminated do
//      while FTerminatedEvent.WaitFor(1) = wrTimeout do
      begin
//        QueryPerformanceCounter(CurrentTicks);
//        ElapsedTime := (CurrentTicks - PreviousTicks) * 1000 / FPerformanceFrequency;
//        PreviousTicks := CurrentTicks;
//        OutputDebugString(PChar(Format('%s.Execute: Delta = %.4f ms', [ClassName, ElapsedTime])));

        // shift source frame
//        TimeFromLastShift := TimeFromLastShift + ElapsedTime;
//
//        OutputDebugString(PChar(Format('%s.Execute: TimeFromLastShift = %.4f ms', [ClassName, TimeFromLastShift])));

        ShiftsCount := 1;
//        ShiftsCount := Trunc(TimeFromLastShift / FRAME_TIME) + 1;
//        if ShiftsCount > 1 then
//          OutputDebugString(PChar(Format('%s.Execute: ShiftsCount = %d !!!!!!!!!!!!!!!!!!!!!!!!!!', [ClassName, ShiftsCount])))
//        else
//          OutputDebugString(PChar(Format('%s.Execute: ShiftsCount = %d', [ClassName, ShiftsCount])));

        ShiftDelta := ShiftsCount * FRAME_STEP;

                                       // 2047.789        -     0 !!!!!
        ShiftFrame(Round(ShiftDelta - (FFrameStartPosition - FFrameStartPositionInt)));

        FFrameStartPosition := FFrameStartPosition - ShiftDelta;

        while CompareValue(FFrameStartPosition, 0) <> GreaterThanValue do
          FFrameStartPosition := FFrameStartPosition + Length(FSourceBitmap); // - 1;

//        TimeFromLastShift := TimeFromLastShift - ShiftsCount * FRAME_TIME;

        // render
        Render;
      end;
    finally
//      timeEndPeriod(1);
    end;
  finally
    CoUninitialize;
  end;
end;

function TDataGeneratorThread.GetFrame: TFrameData;
begin
  FFrameBitmapLock.Enter;
  try
    SetLength(Result, Length(FFrameBitmap));
    CopyMemory(@Result[0], @FFrameBitmap[0], Length(Result) * SizeOf(Result[0]));
  finally
    FFrameBitmapLock.Leave;
  end;
end;

procedure TDataGeneratorThread.Render;
//var
//  PreviousTicks, CurrentTicks: Int64;
begin
//  QueryPerformanceCounter(PreviousTicks);
  FPaintBox.Paint(Frame);
//  QueryPerformanceCounter(CurrentTicks);
//  OutputDebugString(PChar(Format('%s.Render: Paint time = %.4f ms', [ClassName, (CurrentTicks - PreviousTicks) * 1000 / FPerformanceFrequency])));
end;

procedure TDataGeneratorThread.TerminatedSet;
begin
  inherited TerminatedSet;

  if Assigned(FTerminatedEvent) then
    FTerminatedEvent.SetEvent;
end;

procedure TDataGeneratorThread.ShiftFrame(Delta: Integer);
var
  i: Integer;
begin
  if Delta < 0 then
    Delta := Delta + Length(FSourceBitmap);
  Delta := Delta mod Length(FSourceBitmap);
  Dec(FFrameStartPositionInt, Delta);
  while FFrameStartPositionInt < 0 do
    FFrameStartPositionInt := FFrameStartPositionInt + Length(FSourceBitmap);

  if Delta > FRAME_WIDTH then
    Delta := FRAME_WIDTH;

  FFrameBitmapLock.Enter;
  try
    for i := FRAME_WIDTH - 1 downto Delta do
      FFrameBitmap[i] := FFrameBitmap[i - Delta];

    if FFrameStartPositionInt + Delta >= Length(FSourceBitmap) then
    begin
      for i := 0 to Length(FSourceBitmap) - FFrameStartPositionInt - 1 do
        FFrameBitmap[i] := @FSourceBitmap[FFrameStartPositionInt + i];
      for i := Length(FSourceBitmap) - FFrameStartPositionInt to Delta - 1 do
        FFrameBitmap[i] := @FSourceBitmap[i];
    end
    else
      for i := 0 to Delta - 1 do
        FFrameBitmap[i] := @FSourceBitmap[FFrameStartPositionInt + i];
  finally
    FFrameBitmapLock.Leave;
  end;
end;

end.
