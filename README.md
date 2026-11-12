# Sky Fighters

Juego de lucha de plataformas estilo Smash (Godot 4.7, renderer Mobile, PC + Android), con el look de islas
flotantes de Sky Explorer. Proyecto independiente: de Sky Explorer solo se copiaron el modelo de isla,
`ModelFit.gd`, el ambiente (`assets/world_env.tres`) y las herramientas de modelos.

## Menú
`scenes/Menu.tscn` (escena principal): **1 jugador** contra la CPU (Fácil, Normal o Difícil), **2 jugadores** y Salir.
Se maneja con ratón, teclado (flechas + Enter, Esc para volver) o mando. En partida, Esc / Start = pausa
(continuar, reiniciar, menú); al terminar sale "Revancha" o "Menú principal".

## Controles
| | Jugador 1 | Jugador 2 |
|---|---|---|
| Mover | A / D | ← / → |
| Saltar (doble salto) | W o Espacio | ↑ |
| Abajo (caída rápida, bajar de plataforma) | S | ↓ |
| Ataque (+ dirección: lateral, arriba, abajo, aéreos) | F | K |
| Escudo (mantener, en el suelo) | G | L |
| Mando | mando 1 | mando 2 |

Contra la CPU, el jugador 1 puede usar cualquiera de los dos juegos de teclas. R = reiniciar.

## Android
En el móvil salen controles táctiles para el jugador 1 (`scripts/TouchControls.gd`): joystick a la izquierda (aparece
donde pongas el dedo; inclinarlo arriba/abajo elige el ataque, abajo también es caída rápida y bajar de plataforma) y
botones Atacar, Saltar y Escudo a la derecha. Botón de pausa arriba a la derecha y "atrás" de Android = pausa.
En táctil el menú solo ofrece 2 jugadores si hay dos mandos conectados.

Exportar (preset "Android" en `export_presets.cfg`, paquete `com.example.skyfighters`, firmado con la llave de depuración):
```
godot --headless --path . --export-debug "Android" "Sky Fighters.apk"
```
La exportación deja fuera `tools/` y `assets/concepts/`.

## Estructura
- `scenes/Arena.tscn` + `scripts/Arena.gd`: escenario (isla principal y 3 plataformas que se atraviesan desde abajo),
  aparición, zonas de KO, reaparición, fin de partida y hit-stop.
- `scripts/Fighter.gd`: luchador. Movimiento en el plano XY, salto doble, salto corto, caída rápida, ataques por
  dirección (tabla `ATTACKS`), % de daño y empuje que crece con el %, escudo (se gasta y se rompe), y si sales
  volando fuerte (`LAUNCH_KB`) caes tumbado y te levantas invulnerable. Usa las animaciones de
  `<nombre>_rigged.glb`; la tabla `ATTACK_ANIM` dice qué clip usa cada ataque y en qué segundo conecta (la
  velocidad se ajusta sola para cuadrar con el golpe). Sin modelo riggeado, se anima por código.
- `scripts/CpuBrain.gd`: la CPU. Es un "mando virtual": cada cierto tiempo (su tiempo de reacción) decide y pulsa
  los mismos botones que un jugador, así juega con las mismas reglas. La tabla `LEVELS` define cada dificultad
  (reacción, agresividad, escudo, volver al escenario, ataques aéreos, dudas y remates).
- `scripts/FightCamera.gd`: cámara lateral que encuadra a todos. `scripts/HUD.gd`: % y vidas, pausa y fin de partida.
- `scripts/Menu.gd`: menú principal. `scripts/UiKit.gd`: botones y paneles (estilo copiado de Sky Explorer).
- Autoloads: `Inputs` (acciones `p1_*` / `p2_*`) y `Game` (modo y dificultad elegidos).
- `assets/concepts/`: conceptos de los personajes (robot, sombra, neón, trapo). `assets/models_raw/`: GLB originales
  de Higgsfield (ignorados por Godot). `assets/models/`: listos para usar.

## Personajes: de concepto a 3D
1. Concepto con `z_image` (de frente, pose en A, brazos separados).
2. Malla con `sam_3_3d` → `assets/models_raw/<nombre>.glb`.
3. `python3 tools/fix_glb.py assets/models_raw/<nombre>.glb assets/models/<nombre>.glb --metallic 0 --roughness 0.9`
   (añade normales y corrige el material; sin esto se ven oscuros).
4. Mixamo: `python3 tools/glb_to_obj.py assets/models/<nombre>.glb build/mixamo/<nombre>_mixamo.zip`, súbelo,
   esqueleto "No Fingers" si tiene manoplas, y descarga las animaciones en **FBX Binary, With Skin** a
   `assets/models_raw/<nombre>_anims/`.
5. `godot --headless --path . --script res://tools/build_fighter.gd -- <nombre>` → `assets/models/<nombre>_rigged.glb`
   (recorta cada clip y quita el avance de la cadera; la tabla `CLIPS` es común a todos los luchadores).

Animaciones de Mixamo que espera `build_fighter.gd` (mismos nombres de archivo):
`BouncingFightIdle`, `Running`, `Jumping`, `Falling Idle`, `Body Jab Cross`, `Right Hook`, `Mma Kick`,
`Flying Kick`, `Body Block`, `Hit Reaction`, `Knocked Down`, `Getting Up`, `Victory Idle`.

Estado: trapo en 3D y animado. Robot, sombra y neón: solo concepto.

## Pruebas
```
godot --headless --path . --script res://tools/fight_test.gd
godot --headless --path . --script res://tools/cpu_test.gd
godot --headless --path . --script res://tools/touch_test.gd
```
`touch_test` simula dedos en la pantalla: joystick, atacar, saltar, escudo, joystick arriba + atacar y pausa.
`cpu_test` enfrenta a la CPU de cada dificultad a un jugador quieto durante 25 s: comprueba que se acerca, que pega,
que no se cae sola y que la difícil hace más daño que la fácil.
Comprueba: correr, ataque lateral con daño y empuje, empuje según %, doble salto, plataformas blandas
(subir desde abajo y bajar), KO, reaparición, escudo, caer tumbado y levantarse, fin de partida y celebración.
(En modo headless sale un `ERROR: Parameter "material" is null` del renderizador falso; es inofensivo.)
