unit wilga_tint_cache;
{$mode objfpc}
{$modeswitch advancedrecords}
{$DEFINE WILGA_TINT_DEBUG}

interface

uses
  JS, Web, SysUtils, Math, wilga;

procedure InitTintCache(MaxItems: Integer = 256);
procedure ClearTintCache;

// Stały BaseKey to Twoje ID zasobu (np. indeks w atlasie/loaderze)
function GetTintedTexture(const Base: TTexture; BaseKey: LongWord;
                          Color: TColor): TTexture;

procedure PrewarmTint(const Base: TTexture; BaseKey: LongWord;
                      const Colors: array of TColor);

implementation

type
  TTintEntry = record
    Key     : String;    // "w{W}h{H}id{BaseKey}c{r}_{g}_{b}_{a}"
    Tex     : TTexture;  // gotowa tekstura (CreateTextureFromCanvas)
    LastUse : Cardinal;  // do LRU
  end;

var
  GCache    : array of TTintEntry;
  GMaxItems : Integer = 256;
  GTick     : Cardinal = 0;

  // Współdzielony offscreen canvas do tintowania
  GOff      : TJSHTMLCanvasElement = nil;
  GOffCtx   : TJSCanvasRenderingContext2D = nil;

  // Mapa kluczy -> indeks w GCache dla szybkiego wyszukiwania
  GIndex    : TJSMap = nil;

function ClampI(v, lo, hi: Integer): Integer; inline;
begin
  if v < lo then Exit(lo);
  if v > hi then Exit(hi);
  Result := v;
end;

procedure EnsureOffscreen(w, h: Integer);
begin
  if GOff = nil then
  begin
    GOff := TJSHTMLCanvasElement(document.createElement('canvas'));
    GOffCtx := TJSCanvasRenderingContext2D(GOff.getContext('2d'));
  end;
  if (GOff.width <> w) or (GOff.height <> h) then
  begin
    GOff.width := w;
    GOff.height := h;
  end;
end;

function ColorKey(const C: TColor): String; inline;
begin
  Result := IntToStr(C.r)+'_'+IntToStr(C.g)+'_'+IntToStr(C.b)+'_'+IntToStr(C.a);
end;

function MakeKey(const Base: TTexture; BaseKey: LongWord; const C: TColor): String; inline;
begin
  Result := 'w'+IntToStr(Base.width)+'_h'+IntToStr(Base.height)+'_id'+IntToStr(BaseKey)+'_c'+ColorKey(C);
end;

function FindIndexByKey(const K: String): Integer;
var
  v: JSValue;
begin
  if (GIndex <> nil) and GIndex.has(K) then
  begin
    v := GIndex.get(K);
    Exit(Integer(v));
  end;
  Result := -1;
end;

procedure TouchIndex(idx: Integer); inline;
begin
  Inc(GTick);
  GCache[idx].LastUse := GTick;
end;

procedure FreeEntry(var E: TTintEntry);
begin
  if (E.Tex.canvas <> nil) then
    ReleaseTexture(E.Tex);
  E := Default(TTintEntry);
end;

procedure EvictIfNeeded;
var
  i, victim, n: Integer;
  bestTick: Cardinal;
  victimKey: String;
begin
  n := Length(GCache);
  if n <= GMaxItems then Exit;

  victim := 0; bestTick := High(Cardinal);
  for i := 0 to n-1 do
    if GCache[i].LastUse < bestTick then
    begin
      bestTick := GCache[i].LastUse;
      victim := i;
    end;

  victimKey := GCache[victim].Key;
  FreeEntry(GCache[victim]);

  // przenieś ostatni na miejsce ofiary
  GCache[victim] := GCache[n-1];
  SetLength(GCache, n-1);

  if (GIndex <> nil) then
  begin
    GIndex.delete(victimKey);
    // zaktualizuj pozycję przeniesionego elementu
    if victim < Length(GCache) then
      GIndex.&set(GCache[victim].Key, victim);
  end;
end;

function BuildTintTextureViaCanvas(const Base: TTexture; const C: TColor): TTexture;
begin
  EnsureOffscreen(Base.width, Base.height);

  // fill RGB
  GOffCtx.fillStyle := 'rgb(' + IntToStr(C.r) + ',' + IntToStr(C.g) + ',' + IntToStr(C.b) + ')';
  GOffCtx.fillRect(0, 0, Base.width, Base.height);

  // multiply z bazą
  GOffCtx.globalCompositeOperation := 'multiply';
  GOffCtx.drawImage(Base.canvas, 0, 0);

  // alfa z oryginału
  GOffCtx.globalCompositeOperation := 'destination-in';
  GOffCtx.drawImage(Base.canvas, 0, 0);

  // przywróć domyślną operację
  GOffCtx.globalCompositeOperation := 'source-over';

  Result := CreateTextureFromCanvas(GOff);
end;

procedure InsertCacheTex(const Key: String; const Tex: TTexture);
var
  e: TTintEntry;
  n: Integer;
begin
  e.Key := Key;
  e.Tex := Tex;
  Inc(GTick);
  e.LastUse := GTick;

  n := Length(GCache);
  SetLength(GCache, n+1);
  GCache[n] := e;

  if (GIndex <> nil) then
    GIndex.&set(Key, n);

  EvictIfNeeded;
end;

procedure InitTintCache(MaxItems: Integer);
begin
  GMaxItems := ClampI(MaxItems, 1, 8192);
  SetLength(GCache, 0);

  // upewnij się, że mamy mapę
  if GIndex = nil then
    GIndex := TJSMap.new
  else
    GIndex.clear;

  GTick := 0;
  // nie zwalniamy GOff/GOffCtx; zostają do ponownego użycia
end;

procedure ClearTintCache;
var
  i: Integer;
begin
  for i := 0 to High(GCache) do
    FreeEntry(GCache[i]);
  SetLength(GCache, 0);
  if GIndex <> nil then GIndex.clear;
  GTick := 0;
  // nie zwalniamy GOff/GOffCtx; zostają do ponownego użycia
end;

function GetTintedTexture(const Base: TTexture; BaseKey: LongWord;
                          Color: TColor): TTexture;
var
  key: String;
  idx: Integer;
begin
  key := MakeKey(Base, BaseKey, Color);

  idx := FindIndexByKey(key);
  if idx >= 0 then
  begin
    TouchIndex(idx);
    Exit(GCache[idx].Tex);
  end;

  // miss → budujemy przez canvas i wkładamy do cache
  InsertCacheTex(key, BuildTintTextureViaCanvas(Base, Color));
  Result := GCache[High(GCache)].Tex;
end;

procedure PrewarmTint(const Base: TTexture; BaseKey: LongWord;
                      const Colors: array of TColor);
var
  i: Integer;
begin
  for i := 0 to High(Colors) do
    GetTintedTexture(Base, BaseKey, Colors[i]);
end;

end.
