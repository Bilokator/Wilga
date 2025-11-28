unit wilga_sprite_entity;

{$mode objfpc}{$H+}

interface

uses
  wilga, wilga_extras, Math;

type
  // 8 kierunków ruchu (do animacji kierunkowych)
  TDir8 = (
    dDown,        // 0,1
    dDownRight,   // 1,1
    dRight,       // 1,0
    dUpRight,     // 1,-1
    dUp,          // 0,-1
    dUpLeft,      // -1,-1
    dLeft,        // -1,0
    dDownLeft     // -1,1
  );

  // Stany animacji
  TSpriteState = (
    ssIdle,
    ssWalk,
    ssAttack,
    ssDie
  );

  // Pełny byt sprite’owy: sprite + animator + logika
  TSpriteEntity = record
    Sprite   : TSprite;          // pozycja, skala, orientacja
    Anim     : TSpriteAnimator;  // aktualna animacja
    State    : TSpriteState;     // Idle, Walk, Attack...
    Facing   : TVector2;         // kierunek ruchu (znormalizowany)
    Speed    : Double;           // prędkość jednostki
  end;

// KONSTRUKTORY
procedure SpriteEntityInit(var E: TSpriteEntity;
  const Tex: TTexture;
  FrameW, FrameH: Integer;
  AnimFPS: Single = 8.0);

// PRZEŁĄCZANIE STANÓW
procedure SpriteEntitySetState(var E: TSpriteEntity; S: TSpriteState);

// UPDATE — logika ruchu + animacja
procedure SpriteEntityUpdate(var E: TSpriteEntity; dt: Single);

// RYSOWANIE
procedure SpriteEntityDraw(const E: TSpriteEntity; const Tint: TColor);

// HELPERY: kierunki
function VecToDir8(const v: TVector2): TDir8;
function Dir8ToClipName(const Base: String; D: TDir8): String;

implementation

// Zamiana wektora na jeden z 8 kierunków
function VecToDir8(const v: TVector2): TDir8;
var
  ang: Single;
  deg: Integer;
begin
  if (v.x = 0) and (v.y = 0) then
    Exit(dDown);

  ang := ArcTan2(v.y, v.x); // -π .. π
  deg := Round(RadToDeg(ang));

  // Konwersja kątów na kierunki
  if (deg >= -22) and (deg < 22) then      Exit(dRight);
  if (deg >= 22) and (deg < 67) then       Exit(dDownRight);
  if (deg >= 67) and (deg < 112) then      Exit(dDown);
  if (deg >= 112) and (deg < 157) then     Exit(dDownLeft);
  if (deg >= 157) or (deg < -157) then     Exit(dLeft);
  if (deg >= -157) and (deg < -112) then   Exit(dUpLeft);
  if (deg >= -112) and (deg < -67) then    Exit(dUp);
  // pozostałe
  Result := dUpRight;
end;

// Generowanie nazwy klipu, np. "walk" + "_down"
function Dir8ToClipName(const Base: String; D: TDir8): String;
begin
  case D of
    dDown:      Result := Base + '_down';
    dDownRight: Result := Base + '_downright';
    dRight:     Result := Base + '_right';
    dUpRight:   Result := Base + '_upright';
    dUp:        Result := Base + '_up';
    dUpLeft:    Result := Base + '_upleft';
    dLeft:      Result := Base + '_left';
    dDownLeft:  Result := Base + '_downleft';
  end;
end;

// Inicjalizacja bytu
procedure SpriteEntityInit(var E: TSpriteEntity; const Tex: TTexture;
  FrameW, FrameH: Integer; AnimFPS: Single);
begin
  FillChar(E{%H-}, SizeOf(E), 0);

  // Ustawienie sprite'a
  SpriteFromTexture(E.Sprite, Tex);
  E.Sprite.FrameWidth  := FrameW;
  E.Sprite.FrameHeight := FrameH;

  // Domyślne parametry
  E.Speed := 100;
  E.Facing := V2(0,1); // domyślnie w dół

  // Inicjalizacja animatora
  SpriteAnimatorInit(E.Anim, @E.Sprite);
  E.Anim.FPS := AnimFPS;

  E.State := ssIdle;
end;

// Zmiana stanu
procedure SpriteEntitySetState(var E: TSpriteEntity; S: TSpriteState);
begin
  if E.State = S then Exit;
  E.State := S;

  case S of
    ssIdle:
      SpriteAnimPlay(E.Anim, 'idle');
    ssWalk:
      SpriteAnimPlay(E.Anim, 'walk');
    ssAttack:
      SpriteAnimPlay(E.Anim, 'attack');
    ssDie:
      SpriteAnimPlay(E.Anim, 'die');
  end;
end;

// Logika + animacja
procedure SpriteEntityUpdate(var E: TSpriteEntity; dt: Single);
var
  vel: TVector2;
  dir: TDir8;
begin
  // Ruch — na podstawie Facing
  vel := Vec2Scale(E.Facing, E.Speed * dt);
  E.Sprite.Position := Vec2Add(E.Sprite.Position, vel);

  // Jeśli stoi -> Idle
  if VecLength(E.Facing) < 0.01 then
    SpriteEntitySetState(E, ssIdle)
  else
    SpriteEntitySetState(E, ssWalk);

  // Dopasuj animację kierunkową
  if E.State = ssWalk then
  begin
    dir := VecToDir8(E.Facing);
    SpriteAnimPlay(E.Anim, Dir8ToClipName('walk', dir));
  end;

  SpriteAnimatorUpdate(E.Anim, dt);
end;

// Rysowanie bytu
procedure SpriteEntityDraw(const E: TSpriteEntity; const Tint: TColor);
begin
  SpriteDraw(E.Sprite, Tint);
end;

end.
