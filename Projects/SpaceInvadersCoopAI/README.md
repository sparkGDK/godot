# Space Invaders Coop Network

Un proiect Godot 4.7 cu un Space Invaders cooperativ in retea: P1 este host-ul, iar fiecare jucator care intra in LAN primeste automat propria nava.

## Gameplay

- Nava ta se misca lateral si trage in valurile de invadatori.
- Orice jucator nou se poate conecta oricand si apare imediat cu o nava proprie: P2, P3, P4 etc.
- Host-ul este autoritativ si sincronizeaza starea tuturor navelor, inamicilor, gloantelor si efectelor.
- Invadatorii se distrug pe segmente vizibile, nu mor din prima lovitura.
- Cele 3 baze defensive absorb proiectile si se sparg pe celule.
- Fiecare nivel foloseste alta formatie de invadatori.
- Fiecare nivel are 5 minute, iar timpul ramas devine bonus de scor la final.
- Loviturile ratate scad scorul comun, iar distrugerile adauga puncte cu popups vizibile.
- Unii invadatori transporta capsule bonus si lazi de arme.
- Armele care pot cadea: dublu, spread, laser penetrant si racheta exploziva.
- Invadatorii mai arunca uneori bombe lente care explodeaza si sparg bazele in zona.
- Efecte vizuale arcade: glow-uri, trail-uri, explozii cu shockwave, screen shake si fundal animat.
- Scorul este comun.
- Daca o nava co-op este lovita de mai multe ori, intra temporar in reparatii si revine automat.

## Controale

- P1 host: `A` / `D` sau sageti stanga/dreapta pentru miscare, `Space` pentru foc.
- Clienti P2/P3/P4...: `A` / `D` sau sageti stanga/dreapta pentru miscare, `Space` sau `Enter` pentru foc.
- `F2`: coop local pentru test, P1 cu `A` / `D` + `Space`, P2 cu sageti + `Enter`.
- `Esc`: reia cautarea de coechipier LAN.
- `R`: restart pe host.

## Multiplayer

Porneste jocul pe mai multe calculatoare din aceeasi retea sau mai multe instante pe acelasi PC. Prima instanta devine host, iar celelalte se conecteaza automat ca P2, P3, P4 si asa mai departe. Host-ul poate juca singur, iar jucatorii noi pot intra in orice moment fara sa reseteze nivelul.

## Rulare

Deschide `project.godot` in Godot 4.7 sau ruleaza:

```powershell
..\Godot_v4.7-stable_win64_console.exe --path . --editor
```
