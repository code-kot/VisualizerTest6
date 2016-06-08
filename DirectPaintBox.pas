unit DirectPaintBox;

interface

uses
  Vcl.Controls, System.SyncObjs, System.Classes, Winapi.D3D10, Winapi.DXGI,
  System.Win.ComObj, Winapi.Windows, Winapi.DxgiFormat, Vcl.Direct2D,
  Winapi.D2D1, Winapi.Messages, Winapi.DxgiType, Vcl.Graphics, System.Types,
  System.SysUtils, System.Math, Winapi.D3D10_1, Winapi.Dwmapi,

  Frame;

type
  TDirectPaintBox = class(TWinControl)
  private
    FDeviceResourcesLock: TCriticalSection;

    FD2DBitmap: ID2D1Bitmap;
    FD2DBitmapRect: TRectF;

    FBitmapChanged: Boolean;
    FBitmapLock: TCriticalSection;

    FBitmapData: TBytes;
    FBitmapDataRect: TRect;

    FD3D10Device: ID3D10Device1;
    FDXDevice: IDXGIDevice1;
    FDXGIAdapter: IDXGIAdapter;
    FDXGIFactory: IDXGIFactory;
    FDXGISwapChain: IDXGISwapChain;
    FRenderTarget: ID2D1RenderTarget;
    FDXGIOutput: IDXGIOutput;

    FPerformanceFrequency: Int64;  // ticks per second
    FPreviousTicks, FCurrentTicks: Int64;

    procedure CreateDeviceResources;
    procedure CreateRenderTarget;
    procedure ResizeSwapChain;
    procedure DiscardDeviceResources;

    { Catching paint events }
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMDisplayChange(var Message: TWMDisplayChange); message WM_DISPLAYCHANGE;
    function UpdateBitmap: Integer;

    procedure Paint; overload;
  public
    { Life-time management }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Paint(AFrameData: TFrameData); overload;
  end;


implementation

const
  BG_COLOR = clNavy;

{ TDirectPaintBox }

constructor TDirectPaintBox.Create(AOwner: TComponent);
var
  PresentParams: TDwmPresentParameters;
begin
  inherited Create(AOwner);

  FDeviceResourcesLock := TCriticalSection.Create;
  FBitmapLock := TCriticalSection.Create;
  QueryPerformanceFrequency(FPerformanceFrequency);

//  System.Win.ComObj.OleCheck(
//    DwmEnableComposition(DWM_EC_DISABLECOMPOSITION)
//  );

//  PresentParams.cbSize := SizeOf(PresentParams);
//  PresentParams.fQueue := True;
//  PresentParams.cRefreshStart := 1;
//  PresentParams.cBuffer := 2;
//  PresentParams.fUseSourceRate := True;
//  PresentParams.rateSource.uiNumerator := 60;
//  PresentParams.rateSource.uiDenominator := 1;
//  PresentParams.cRefreshesPerFrame := 1;
//  PresentParams.eSampling := DWM_SOURCE_FRAME_SAMPLING_COVERAGE;
//
//  System.Win.ComObj.OleCheck(
//    DwmSetPresentParameters(Self.Handle, PresentParams)
//  );
end;

procedure TDirectPaintBox.CreateDeviceResources;
var
  SwapChainDesc: DXGI_SWAP_CHAIN_DESC;
begin
  System.Win.ComObj.OleCheck(
    D3D10CreateDevice1(
      nil,
      D3D10_DRIVER_TYPE_HARDWARE,
      0,
      D3D10_CREATE_DEVICE_BGRA_SUPPORT, // {$IFDEF DEBUG} or D3D10_CREATE_DEVICE_DEBUG{$ENDIF},
      D3D10_FEATURE_LEVEL_10_1,
      D3D10_1_SDK_VERSION,
      FD3D10Device)
  );

  FDXDevice := FD3D10Device as IDXGIDevice1;
//  System.Win.ComObj.OleCheck(
//    FDXDevice.SetMaximumFrameLatency(2)
//  );

  System.Win.ComObj.OleCheck(
    FDXDevice.GetAdapter(FDXGIAdapter)
  );

  System.Win.ComObj.OleCheck(
    FDXGIAdapter.GetParent(IDXGIFactory, FDXGIFactory)
  );

  ZeroMemory(@SwapChainDesc, SizeOf(SwapChainDesc));
//  SwapChainDesc.BufferDesc.Width := Self.Width;
//  SwapChainDesc.BufferDesc.Height := Self.Height;
//  SwapChainDesc.BufferDesc.RefreshRate.Numerator := 60;
//  SwapChainDesc.BufferDesc.RefreshRate.Denominator := 1;
  SwapChainDesc.BufferDesc.Format := DXGI_FORMAT_B8G8R8A8_UNORM;
  SwapChainDesc.SampleDesc.Count := 1;
  SwapChainDesc.SampleDesc.Quality := 0;
  SwapChainDesc.BufferUsage := DXGI_USAGE_RENDER_TARGET_OUTPUT;
  SwapChainDesc.BufferCount := 4;
  SwapChainDesc.OutputWindow := Self.Handle;
  SwapChainDesc.Windowed := True;
  SwapChainDesc.SwapEffect := DXGI_SWAP_EFFECT_SEQUENTIAL;
  SwapChainDesc.Flags := Cardinal(DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH);

  System.Win.ComObj.OleCheck(
    FDXGIFactory.CreateSwapChain(FD3D10Device, SwapChainDesc, FDXGISwapChain)
  );

  System.Win.ComObj.OleCheck(
    FDXGISwapChain.GetContainingOutput(FDXGIOutput)
  );

  CreateRenderTarget;
end;

procedure TDirectPaintBox.CreateRenderTarget;
var
  DpiX, DpiY: Single;
  DXGISurface: IDXGISurface;
  RenderTargetProperties: D2D1_RENDER_TARGET_PROPERTIES;
begin
  System.Win.ComObj.OleCheck(
    FDXGISwapChain.GetBuffer(0, IDXGISurface, DXGISurface)
  );

  D2DFactory.GetDesktopDpi(DpiX, DpiY);

  RenderTargetProperties := D2D1RenderTargetProperties(
    D2D1_RENDER_TARGET_TYPE_HARDWARE,
    D2D1PixelFormat(DXGI_FORMAT_UNKNOWN, D2D1_ALPHA_MODE_PREMULTIPLIED),
    DpiX,
    DpiY
  );

  System.Win.ComObj.OleCheck(
    D2DFactory.CreateDxgiSurfaceRenderTarget(
      DXGISurface,
      RenderTargetProperties,
      FRenderTarget)
  );

  DXGISurface := nil;
end;

destructor TDirectPaintBox.Destroy;
begin
  DiscardDeviceResources;

  FDeviceResourcesLock.Free;
  FBitmapLock.Free;

  inherited Destroy;
end;

procedure TDirectPaintBox.DiscardDeviceResources;
begin
  FDeviceResourcesLock.Enter;
  try
    FRenderTarget := nil;
    FDXGIOutput := nil;
    FDXGISwapChain := nil;
    FDXGIFactory := nil;
    FDXGIAdapter := nil;
    FDXDevice := nil;
    FD3D10Device := nil;
  finally
    FDeviceResourcesLock.Leave;
  end;
end;

procedure TDirectPaintBox.Paint;
var
  hr: HRESULT;
  RenderRectSize, BitmapRectSize: TD2D1SizeF;
  RenderRect: TD2D1RectF;
  Scale: Single;
  TransformMatrix: TD2DMatrix3X2F;
  PreviousTicks, CurrentTicks: Int64;
  PresentCount: Cardinal;
begin
  if FDeviceResourcesLock.TryEnter then
  try
    if not Assigned(FRenderTarget) then
      CreateDeviceResources;

//    QueryPerformanceCounter(PreviousTicks);
    System.Win.ComObj.OleCheck(
      UpdateBitmap
    );
//    QueryPerformanceCounter(CurrentTicks);
//    OutputDebugString(PChar(Format('%s.Paint: UpdateBitmap with OleCheck time = %.4f ms', [ClassName, (CurrentTicks - PreviousTicks) * 1000 / FPerformanceFrequency])));

//    QueryPerformanceCounter(PreviousTicks);
    FRenderTarget.BeginDraw;
    try
      FRenderTarget.Clear(D2D1ColorF(BG_COLOR));

      if Assigned(FD2DBitmap) then
      begin
        BitmapRectSize.width := FD2DBitmapRect.right - FD2DBitmapRect.left;
        BitmapRectSize.height := FD2DBitmapRect.bottom - FD2DBitmapRect.top;

        FRenderTarget.GetSize(RenderRectSize);
        if IsZero(BitmapRectSize.width) then
          Scale := 0
        else
          Scale := RenderRectSize.height / BitmapRectSize.width;

        if not IsZero(Scale) then
        begin
          RenderRect := D2D1RectF(0, 0, RenderRectSize.height, FD2DBitmapRect.Height * Scale);

          TransformMatrix := TD2DMatrix3X2F.Rotation(-90, FD2DBitmapRect.Width * Scale / 2, FD2DBitmapRect.Width * Scale / 2);
          TransformMatrix := TransformMatrix * TD2DMatrix3X2F.Scale(1, -1, D2D1PointF(RenderRectSize.width / 2, RenderRectSize.height / 2));
          FRenderTarget.SetTransform(TransformMatrix);

          FRenderTarget.DrawBitmap(FD2DBitmap, @RenderRect, 1,
            D2D1_BITMAP_INTERPOLATION_MODE_LINEAR, @FD2DBitmapRect);
        end;
      end;
    finally
      hr := FRenderTarget.EndDraw;
    end;

//    QueryPerformanceCounter(CurrentTicks);
//    OutputDebugString(PChar(Format('%s.Paint: Rendering time = %.4f ms', [ClassName, (CurrentTicks - PreviousTicks) * 1000 / FPerformanceFrequency])));

    if hr = D2DERR_RECREATE_TARGET then
    begin
      FRenderTarget := nil;
      CreateRenderTarget;
      FBitmapChanged := True;
    end;

//    FDXGISwapChain.GetContainingOutput(FDXGIOutput);
//    FDXGIOutput.WaitForVBlank;

//    QueryPerformanceCounter(FCurrentTicks);

//    if ((FCurrentTicks - FPreviousTicks) * 1000 / FPerformanceFrequency) < 1000.0/60 then
//      hr := FDXGISwapChain.Present(1, 0)
//    else
//      hr := FDXGISwapChain.Present(0, 0);

//    QueryPerformanceCounter(PreviousTicks);
    hr := FDXGISwapChain.Present(1, 0);

//    OutputDebugString(PChar(Format('%s.Paint: Time from last Present end = %.4f ms', [ClassName, (FCurrentTicks - FPreviousTicks) * 1000 / FPerformanceFrequency])));
//    QueryPerformanceCounter(FPreviousTicks);

//    FDXGISwapChain.GetLastPresentCount(PresentCount);
//    OutputDebugString(PChar(Format('%s.Paint: PresentCount = %d', [ClassName, PresentCount])));
//    QueryPerformanceCounter(CurrentTicks);
//    OutputDebugString(PChar(Format('%s.Paint: Present time = %.4f ms', [ClassName, (CurrentTicks - PreviousTicks) * 1000 / FPerformanceFrequency])));


    if (hr <> S_OK) and (hr <> DXGI_STATUS_OCCLUDED) then
      DiscardDeviceResources;
  finally
    FDeviceResourcesLock.Leave;
  end;
end;

procedure TDirectPaintBox.Paint(AFrameData: TFrameData);
var
  i: Integer;
  Count: Integer;
//  PreviousTicks, CurrentTicks: Int64;
begin
//  QueryPerformanceCounter(PreviousTicks);
  FBitmapLock.Enter;
  try
    FBitmapDataRect := TRect.Create(0, 0, Length(AFrameData[0]^), Length(AFrameData));

    Count := Length(AFrameData[0]^) * 4;
    SetLength(FBitmapData, Length(AFrameData) * Count);

    for i := 0 to Length(AFrameData) - 1 do
      CopyMemory(@(FBitmapData[i * Count]), @(AFrameData[i]^[0]), Count);

    FBitmapChanged := True;
  finally
    FBitmapLock.Leave;
  end;
//  QueryPerformanceCounter(CurrentTicks);
//  OutputDebugString(PChar(Format('%s.Paint: Update FBitmapData Delta = %.4f ms', [ClassName, (CurrentTicks - PreviousTicks) * 1000 / FPerformanceFrequency])));
//  PreviousTicks := CurrentTicks;
  Paint;
//  QueryPerformanceCounter(CurrentTicks);
//  OutputDebugString(PChar(Format('%s.Paint: Paint Delta = %.4f ms', [ClassName, (CurrentTicks - PreviousTicks) * 1000 / FPerformanceFrequency])));
end;

procedure TDirectPaintBox.ResizeSwapChain;
begin
  FDeviceResourcesLock.Enter;
  try
    FRenderTarget := nil;

    if FDXGISwapChain.ResizeBuffers(0, 0, 0, DXGI_FORMAT_UNKNOWN, 0) = S_OK then
      CreateRenderTarget
    else
      DiscardDeviceResources;
  finally
    FDeviceResourcesLock.Leave;
  end;
end;

function TDirectPaintBox.UpdateBitmap: Integer;
var
  Pitch: Integer;
//  PreviousTicks, CurrentTicks: Int64;
begin
  if not FBitmapChanged then
    Exit(0);

//  QueryPerformanceCounter(PreviousTicks);

  FBitmapLock.Enter;
  try
    FD2DBitmap := nil;

    // update from FBitmapData
    if Length(FBitmapData) > 0 then
    begin
      Pitch := FBitmapDataRect.Right * 4;

      Result := FRenderTarget.CreateBitmap(
        D2D1SizeU(FBitmapDataRect.Right, FBitmapDataRect.Bottom),
        @FBitmapData[0],
        Pitch,
        D2D1BitmapProperties(D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE)),
        FD2DBitmap);

      FD2DBitmapRect := TRectF.Create(FBitmapDataRect);
    end
    else
      Result := 0;

    FBitmapChanged := False;
  finally
    FBitmapLock.Leave;
  end;

//  QueryPerformanceCounter(CurrentTicks);
//  OutputDebugString(PChar(Format('%s.UpdateBitmap: Delta = %.4f ms', [ClassName, (CurrentTicks - PreviousTicks) * 1000 / FPerformanceFrequency])));
end;

procedure TDirectPaintBox.WMDisplayChange(var Message: TWMDisplayChange);
begin
  inherited;

  DiscardDeviceResources;

//  Message.Result := 0;
end;

procedure TDirectPaintBox.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  OutputDebugString(PChar('TDirectPaintBox.WMEraseBKGND'));

  Message.Result := 0;
end;

procedure TDirectPaintBox.WMPaint(var Message: TWMPaint);
var
  PaintStruct: TPaintStruct;
begin
  BeginPaint(Handle, PaintStruct);
  try
//    OutputDebugString(PChar('TDirectPaintBox.WMPaint'));
    Paint;
  finally
    EndPaint(Handle, PaintStruct);
  end;

  Message.Result := 0;
end;

procedure TDirectPaintBox.WMSize(var Message: TWMSize);
begin
  inherited;

  if Assigned(FD3D10Device) then
  begin
    ResizeSwapChain;
    Paint;
  end;

//  Message.Result := 0;
end;

end.
