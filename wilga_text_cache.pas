unit wilga_text_cache;
{$mode objfpc}
{$modeswitch advancedrecords}

interface

uses
  JS, Web, SysUtils, Math;

type
  // Styl determinujący wygląd bitmapy tekstu
  TTextStyle = record
    SizePx: Integer;
    Family: String;
    Fill: Cardinal;        // 0xAARRGGBB
    AlignH: String;        // 'left' | 'center' | 'right'
    AlignV: String;        // 'top' | 'middle' | 'alphabetic' | 'bottom'
    OutlinePx: Integer;
    Outline: Cardinal;
    ShadowOffsetX: Integer;
    ShadowOffsetY: Integer;
    ShadowBlur: Integer;
    ShadowColor: Cardinal;
    Padding: Integer;
  end;

  // Offscreen „tekstura” (canvas) trzymana w cache
  TTexture = record
    canvas: TJSHTMLCanvasElement;
    width, height: Integer;
    loaded: Boolean;
  end;

  // Dokładne metryki tekstu
  TTextMetricsI = record
    w  : Integer;  // szerokość
    asc: Integer;  // ascent
    desc: Integer; // descent
  end;

procedure InitTextCache(ACapacity: Integer = 256);
procedure ClearTextCache;
function  GetTextTexture(const Text: String; const S: TTextStyle): TTexture;

// === DEBUG/STATY ===
procedure TextCache_BeginFrame; // wołaj na starcie klatki
procedure TextCache_GetStats(out Hits, Misses, Created, Evicted,
                             FrameHits, FrameMisses: NativeInt);

implementation

type
  TItem = record
    Key: String;
    Tex: TTexture;
  end;

var
  GItems: array of TItem;
  GIndex: TJSMap = nil;   // Key -> Integer
  GCap  : Integer = 0;
  GPtr  : Integer = 0;

  // Statystyki
  GHits, GMisses, GCreated, GEvicted: NativeInt;
  GFrameHits, GFrameMisses: NativeInt;
procedure RegisterTextCanvasForWorker(cnv: TJSHTMLCanvasElement); inline;
begin
  asm
    var worker = window.__wilgaRenderWorker;
    if (!worker || !cnv || typeof createImageBitmap !== 'function') return;

    // globalny licznik ID tekstur współdzielony przez WSZYSTKIE canvasy
    if (!cnv.__wilgaTexId) {
      if (!window.__wilgaNextTexId) window.__wilgaNextTexId = 1;
      cnv.__wilgaTexId = window.__wilgaNextTexId++;
    }
    var id = cnv.__wilgaTexId;

    createImageBitmap(cnv).then(function(bmp) {
      worker.postMessage(
        { type: 'registerTexture', id: id, bitmap: bmp },
        [bmp]
      );
    });
  end;
end;

function ColorToCanvasRGBA(const C: Cardinal): String; inline;
var r,g,b,a: Byte;
begin
  a := (C shr 24) and $FF;
  r := (C shr 16) and $FF;
  g := (C shr 8)  and $FF;
  b := (C       ) and $FF;
  Result := Format('rgba(%d,%d,%d,%.3f)', [r,g,b, a/255.0]);
end;

function MakeOffscreenCanvas(w,h: Integer): TJSHTMLCanvasElement; inline;
begin
  Result := TJSHTMLCanvasElement(document.createElement('canvas'));
  Result.width  := w;
  Result.height := h;
end;

function CreateTextureFromCanvas(cnv: TJSHTMLCanvasElement): TTexture; inline;
begin
  Result.canvas := cnv;
  Result.width  := cnv.width;
  Result.height := cnv.height;
  Result.loaded := True;

  // NOWE: zarejestruj canvas tekstowy w workerze jako teksturę
  RegisterTextCanvasForWorker(cnv);
end;

procedure ReleaseTexture(var tex: TTexture); inline;
begin
  tex.loaded := False;
  tex.canvas := nil;
  tex.width := 0;
  tex.height := 0;
end;

function BuildFontString(const Size: Integer; const Family: String): String; inline;
begin
  if Family <> '' then
    Result := IntToStr(Size) + 'px "' + Family + '", system-ui, sans-serif'
  else
    Result := IntToStr(Size) + 'px system-ui, sans-serif';
end;

function MakeKey(const Text: String; const S: TTextStyle): String; inline;
begin
  Result :=
    'f=' + BuildFontString(S.SizePx, S.Family) +
    '|t=' + Text +
    '|fill=' + IntToHex(S.Fill, 8) +
    '|outpx=' + IntToStr(S.OutlinePx) +
    '|out=' + IntToHex(S.Outline, 8) +
    '|ah=' + S.AlignH +
    '|av=' + S.AlignV +
    '|sx=' + IntToStr(S.ShadowOffsetX) +
    '|sy=' + IntToStr(S.ShadowOffsetY) +
    '|sb=' + IntToStr(S.ShadowBlur) +
    '|sc=' + IntToHex(S.ShadowColor, 8) +
    '|pad=' + IntToStr(S.Padding);
end;

function MeasureText(ctx: TJSCanvasRenderingContext2D; const s: String; fontPx: Integer): TTextMetricsI;
var w, asc, desc: Double;
begin
  // Próbuj użyć dokładnych metryk z Canvas; fallback dla starszych implementacji
  asm
    var m = ctx.measureText(s);
    w    = m.width;
    asc  = (m.actualBoundingBoxAscent  !== undefined) ? m.actualBoundingBoxAscent  : 0.80 * fontPx;
    desc = (m.actualBoundingBoxDescent !== undefined) ? m.actualBoundingBoxDescent : 0.30 * fontPx;
  end;
  Result.w    := Ceil(w);
  Result.asc  := Ceil(asc);
  Result.desc := Ceil(desc);
end;

function BuildTextTexture(const Text: String; const S: TTextStyle): TTexture;
var
  pad, w, h: Integer;
  cnv: TJSHTMLCanvasElement;
  ctx: TJSCanvasRenderingContext2D;
  drawX, drawY: Double;
  fontStr: String;
  m: TTextMetricsI;
  asc, desc, totalH: Integer;
begin
  // 1) Pomiar
  cnv := MakeOffscreenCanvas(1,1);
  ctx := TJSCanvasRenderingContext2D(cnv.getContext('2d'));
  fontStr := BuildFontString(S.SizePx, S.Family);
  ctx.font := fontStr;

  m := MeasureText(ctx, Text, S.SizePx);
  asc := m.asc; desc := m.desc;

  pad := Max(0, S.Padding);
  totalH := asc + desc;
  w := Max(1, m.w + pad*2);
  h := Max(1, totalH + pad*2);

  // 2) Render do docelowego offscreen
  cnv := MakeOffscreenCanvas(w, h);
  ctx := TJSCanvasRenderingContext2D(cnv.getContext('2d'));
  ctx.font := fontStr;

  // W cache rysujemy ZAWSZE na 'alphabetic' baseline,
  // a AlignV mapujemy do pozycji linii bazowej.
  ctx.textBaseline := 'alphabetic';
  ctx.textAlign := S.AlignH;

  // X: klasycznie
  if S.AlignH = 'center' then drawX := w * 0.5
  else if S.AlignH = 'right' then drawX := w - pad
  else drawX := pad;

  // Y: oblicz pozycję linii bazowej względem 'alphabetic'
  if (S.AlignV = 'top') then
    // chcemy, by górny asc był równy pad
    drawY := pad + asc
  else if (S.AlignV = 'middle') then
    // środek optyczny (asc - desc)/2 trafia w środek obrazu
    drawY := (h * 0.5) + (asc - desc) * 0.5
  else if (S.AlignV = 'bottom') then
    // chcemy, by dół (desc) był przy dolnym padzie
    drawY := h - pad - desc
  else // 'alphabetic'
    // naturalna linia bazowa tuż nad dolnym paddingiem
    drawY := h - pad - desc;

  // Cień
  if (S.ShadowBlur > 0) or (S.ShadowOffsetX <> 0) or (S.ShadowOffsetY <> 0) then
  begin
    ctx.shadowBlur := S.ShadowBlur;
    ctx.shadowColor := ColorToCanvasRGBA(S.ShadowColor);
    asm
      ctx.shadowOffsetX = S.ShadowOffsetX;
      ctx.shadowOffsetY = S.ShadowOffsetY;
    end;
  end;

  // Obrys
  if S.OutlinePx > 0 then
  begin
    ctx.lineJoin := 'round';
    ctx.lineWidth := S.OutlinePx * 2;
    ctx.strokeStyle := ColorToCanvasRGBA(S.Outline);
    ctx.strokeText(Text, drawX, drawY);
  end;

  // Wypełnienie
  ctx.fillStyle := ColorToCanvasRGBA(S.Fill);
  ctx.fillText(Text, drawX, drawY);

  Result := CreateTextureFromCanvas(cnv);
end;


procedure InsertItem(const Key: String; const Tex: TTexture);
var idx: Integer;
begin
  if GIndex = nil then
    GIndex := TJSMap.new;

  if Length(GItems) < GCap then
  begin
    SetLength(GItems, Length(GItems)+1);
    idx := High(GItems);
  end
  else
  begin
    idx := GPtr mod GCap;
    if GItems[idx].Tex.loaded then
      ReleaseTexture(GItems[idx].Tex);
    Inc(GEvicted);
  end;

  GItems[idx].Key := Key;
  GItems[idx].Tex := Tex;
  GIndex.&set(Key, idx); // 'set' jest słowem kluczowym w Pascalu -> użyj &set
  Inc(GPtr);
end;

function FindIndex(const Key: String): Integer;
var v: JSValue;
begin
  if (GIndex <> nil) and GIndex.has(Key) then
  begin
    v := GIndex.get(Key);
    Exit(Integer(v));
  end;
  Exit(-1);
end;

procedure InitTextCache(ACapacity: Integer);
begin
  GCap := Max(16, ACapacity);
  SetLength(GItems, 0);
  GIndex := TJSMap.new;
  GPtr := 0;

  GHits := 0; GMisses := 0; GCreated := 0; GEvicted := 0;
  GFrameHits := 0; GFrameMisses := 0;
end;

procedure ClearTextCache;
var i: Integer;
begin
  for i := 0 to High(GItems) do
    if GItems[i].Tex.loaded then
      ReleaseTexture(GItems[i].Tex);
  SetLength(GItems, 0);
  if GIndex <> nil then GIndex.clear;
  GPtr := 0;

  GHits := 0; GMisses := 0; GCreated := 0; GEvicted := 0;
  GFrameHits := 0; GFrameMisses := 0;
end;

function GetTextTexture(const Text: String; const S: TTextStyle): TTexture;
var key: String; idx: Integer;
begin
  if GCap = 0 then
    InitTextCache(256); // lazy start

  key := MakeKey(Text, S);
  idx := FindIndex(key);
  if idx >= 0 then
  begin
    Inc(GHits);
    Inc(GFrameHits);
    Exit(GItems[idx].Tex);
  end;

  Inc(GMisses);
  Inc(GFrameMisses);

  Result := BuildTextTexture(Text, S);
  Inc(GCreated);
  InsertItem(key, Result);
end;

// === DEBUG/STATY ===

procedure TextCache_BeginFrame;
begin
  GFrameHits := 0;
  GFrameMisses := 0;
end;

procedure TextCache_GetStats(out Hits, Misses, Created, Evicted,
                             FrameHits, FrameMisses: NativeInt);
begin
  Hits := GHits;
  Misses := GMisses;
  Created := GCreated;
  Evicted := GEvicted;
  FrameHits := GFrameHits;
  FrameMisses := GFrameMisses;
end;

end.
