unit wilga_imagebuffer;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, JS,
  wilga;  // TColor + WilgaAddPutImageDataCommand

type
  // Prosty RGBA używany wewnętrznie
  TRGBA = packed record
    r, g, b, a: Byte;
  end;

  { TWilgaImageBuffer
    - trzyma bufor pikseli w pamięci
    - w Draw() pakuje go do Uint8ClampedArray i wysyła jako jedna komenda do Wilgi
  }
  TWilgaImageBuffer = record
    Width, Height: Integer;
    Pixels: array of TRGBA;

    procedure Init(AWidth, AHeight: Integer);
    procedure Free;
    function  IsValid: Boolean;

    procedure Resize(AWidth, AHeight: Integer);

    procedure SetPixel(x, y: Integer; const col: TColor); inline;
    procedure Clear(const col: TColor);

    // Rysuje bufor w aktualnej ramce Wilgi w punkcie (dstX, dstY)
    procedure Draw(dstX, dstY: Integer);
  end;
function ColorToRGBA(const c: TColor): TRGBA; inline;
function ClampByte(v: Integer): Byte; inline;
implementation

function ClampByte(v: Integer): Byte; inline;
begin
  if v < 0 then v := 0
  else if v > 255 then v := 255;
  Result := v;
end;
function ColorToRGBA(const c: TColor): TRGBA; inline;
begin
  Result.r := ClampByte(c.r);
  Result.g := ClampByte(c.g);
  Result.b := ClampByte(c.b);
  Result.a := ClampByte(c.a);
end;



{ TWilgaImageBuffer }

procedure TWilgaImageBuffer.Init(AWidth, AHeight: Integer);
begin
  Width  := AWidth;
  Height := AHeight;
  if (Width > 0) and (Height > 0) then
    SetLength(Pixels, Width * Height)
  else
    SetLength(Pixels, 0);
end;

procedure TWilgaImageBuffer.Free;
begin
  SetLength(Pixels, 0);
  Width  := 0;
  Height := 0;
end;

function TWilgaImageBuffer.IsValid: Boolean;
begin
  Result := (Width > 0) and (Height > 0) and (Length(Pixels) = Width * Height);
end;

procedure TWilgaImageBuffer.Resize(AWidth, AHeight: Integer);
begin
  if (AWidth = Width) and (AHeight = Height) then
    Exit;

  Init(AWidth, AHeight);
end;

procedure TWilgaImageBuffer.SetPixel(x, y: Integer; const col: TColor);
var
  idx: Integer;
begin
  if not IsValid then Exit;
  if (x < 0) or (y < 0) or (x >= Width) or (y >= Height) then Exit;

  idx := y * Width + x;
  Pixels[idx] := ColorToRGBA(col);
end;

procedure TWilgaImageBuffer.Clear(const col: TColor);
var
  i: Integer;
  rgba: TRGBA;
begin
  if not IsValid then Exit;
  rgba := ColorToRGBA(col);

  for i := 0 to High(Pixels) do
    Pixels[i] := rgba;
end;

procedure TWilgaImageBuffer.Draw(dstX, dstY: Integer);
var
  jsBuf : TJSUint8ClampedArray;
  i     : Integer;
  idx   : Integer;
  rgba  : TRGBA;
begin
  if not IsValid then Exit;

  jsBuf := TJSUint8ClampedArray.new(Width * Height * 4);

  idx := 0;
  for i := 0 to High(Pixels) do
  begin
    rgba := Pixels[i];
    jsBuf[idx    ] := rgba.r;
    jsBuf[idx + 1] := rgba.g;
    jsBuf[idx + 2] := rgba.b;
    jsBuf[idx + 3] := rgba.a;
    Inc(idx, 4);
  end;

  // TYLKO TO – żadnego gCtx tutaj
  WilgaAddPutImageDataCommand(dstX, dstY, Width, Height, jsBuf);
end;
end.
