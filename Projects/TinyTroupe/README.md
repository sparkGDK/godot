# Tiny Troupe

Un mic puzzle 2D in Godot 4.7, inspirat de jocurile clasice cu omuleti care merg singuri spre iesire.

## Cum rulezi

Deschide folderul `Godot/Projects/TinyTroupe` in Godot sau porneste scena principala din editor.

## Controale

- `1` Builder: construieste scari peste goluri.
- `2` Digger: sapa in jos prin teren.
- `3` Basher: sparge pereti in fata.
- `4` Blocker: opreste si intoarce alti omuleti.
- `5` Floater: reduce viteza de cadere.
- Click pe un omulet pentru a-i da jobul selectat.
- Click pe bara de sus pentru a selecta joburi.
- `A/D` sau sageti: muta camera.
- Scroll mouse: muta camera.
- `C`: camera automata.
- `Space`: pauza.
- `R`: restart nivel.
- `N`: nivel urmator.
- `Esc`: inchide jocul.

Obiectivul este sa salvezi numarul cerut de omuleti inainte sa ramai fara trupa.

## Android build

Ruleaza:

```powershell
.\build_android_debug.ps1
```

APK-ul debug se genereaza in `build/android/TinyTroupe-debug.apk`.

## Editare niveluri

Nivelurile sunt in scena principala, sub `Main/Levels`.

- `LevelXX/Spawn`: muta markerul ca sa schimbi locul de aparitie.
- `LevelXX/Exit`: muta `Area2D` sau redimensioneaza `CollisionShape2D`.
- `LevelXX/Terrain/GroundXX`: muta platformele si peretii.
- Pentru dimensiuni, selecteaza `CollisionShape2D` dintr-un `GroundXX` si schimba `RectangleShape2D.size`.
- Selecteaza nodul `LevelXX` ca sa schimbi in inspector numarul de omuleti, tinta si stocul de tool-uri.

Nivelurile 2 si 3 sunt puse mai jos in scena, ca sa le poti edita fara sa stea peste primul.
