program JuliaFractalBufferDemo;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

uses
  SysUtils, Math,
  wilga,
  wilga_extras,      // dla ColorFromHSV itp.
  wilga_imagebuffer; // nasz bufor pikseli

const
  JULIA_COLS = 500;
  JULIA_ROWS = 400;
  JULIA_MAX_ITER = 45;

  RE_MIN = -1.6;
  RE_MAX =  1.6;
  IM_MIN = -1.2;
  IM_MAX =  1.2;

var
  JuliaBuf: TWilgaImageBuffer;
  gTime   : Double = 0.0;

  ColToRe: array of Double;
  RowToIm: array of Double;
  Palette: array of TColor;

procedure BuildXYMaps;
var
  i: Integer;
  reSpan, imSpan: Double;
begin
  SetLength(ColToRe, JULIA_COLS);
  SetLength(RowToIm, JULIA_ROWS);

  reSpan := RE_MAX - RE_MIN;
  imSpan := IM_MAX - IM_MIN;

  for i := 0 to JULIA_COLS-1 do
    ColToRe[i] := RE_MIN + (i / (JULIA_COLS-1)) * reSpan;

  for i := 0 to JULIA_ROWS-1 do
    RowToIm[i] := IM_MIN + (i / (JULIA_ROWS-1)) * imSpan;
end;

procedure BuildPalette;
var
  i: Integer;
  v, h, s, vv: Double;
begin
  SetLength(Palette, JULIA_MAX_ITER+1);
  for i := 0 to JULIA_MAX_ITER do
  begin
    v := i / JULIA_MAX_ITER;
    if v < 0 then v := 0;
    if v > 1 then v := 1;

    h  := v;             
    s  := 1.0;
    vv := Power(v, 0.5); // trochę mocniejsza jasność w cieniach

    Palette[i] := ColorFromHSV(h, s, vv, 255);
  end;
end;

procedure UpdateFractal;
var
  x, y    : Integer;
  zx, zy  : Double;
  cx, cy  : Double;
  zx2, zy2: Double;
  iter    : Integer;
  tNorm   : Double;
  color   : TColor;
begin
  if not JuliaBuf.IsValid then Exit;

  // animowany parametr c
  tNorm := gTime * 0.08;
  cx := -0.7    + 0.3 * Sin(tNorm);
  cy :=  0.27015 + 0.3 * Cos(tNorm * 1.2);

  for y := 0 to JULIA_ROWS-1 do
  begin
    for x := 0 to JULIA_COLS-1 do
    begin
      zx := ColToRe[x];
      zy := RowToIm[y];

      iter := 0;
      while (iter < JULIA_MAX_ITER) do
      begin
        zx2 := zx * zx;
        zy2 := zy * zy;

        if (zx2 + zy2 > 4.0) then
          Break;

        // z = z^2 + c
        zy := 2.0 * zx * zy + cy;
        zx := zx2 - zy2 + cx;

        Inc(iter);
      end;

      if iter >= JULIA_MAX_ITER then
        color := COLOR_BLACK
      else
        color := Palette[iter];

      JuliaBuf.SetPixel(x, y, color);
    end;
  end;
end;

procedure Update(const dt: Double);
begin
  gTime += dt;
  UpdateFractal;
end;

procedure Draw(const dt: Double);
var
  sw, sh: Integer;
  dx, dy: Integer;
begin
  ClearBackground(COLOR_BLACK);

  sw := GetScreenWidth;
  sh := GetScreenHeight;

  dx := (sw - JULIA_COLS) div 2;
  dy := (sh - JULIA_ROWS) div 2;

  // jedna komenda putImageData w ramach frame:
  JuliaBuf.Draw(dx, dy);

  //DrawFPS(10, 10, COLOR_WHITE);
  DrawText('Julia (Wilga + ImageBuffer)', 10, 30, 16, COLOR_WHITE);
end;

begin
  InitWindow(800, 600, 'Wilga Julia Fractal (ImageBuffer)');
  SetFPS(60);
  SetCloseOnEscape(True);

  JuliaBuf.Init(JULIA_COLS, JULIA_ROWS);
  BuildXYMaps;
  BuildPalette;

  Run(@Update, @Draw);
end.
