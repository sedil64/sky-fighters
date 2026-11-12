extends Node
## Autoload: opciones de la partida elegidas en el menú.

const MENU := "res://scenes/Menu.tscn"
const ARENA := "res://scenes/Arena.tscn"
const LEVEL_NAMES := ["Fácil", "Normal", "Difícil"]

## "cpu" = 1 jugador contra la CPU, "versus" = 2 jugadores.
var mode := "cpu"
## 0 = fácil, 1 = normal, 2 = difícil.
var cpu_level := 1


func start(new_mode: String, level := cpu_level) -> void:
	mode = new_mode
	cpu_level = level
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(ARENA)


func to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU)
