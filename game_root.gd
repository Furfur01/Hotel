class_name HotelGameRoot
extends Node

const ControllerScript = preload("res://run_controller.gd")
const PlayerScene = preload("res://player.tscn")
const HUDScript = preload("res://hud.gd")

var run_controller: Node
var floor_host: Node3D
var player: CharacterBody3D
var hud: HotelHUD


func _ready() -> void:
	floor_host = Node3D.new()
	floor_host.name = "FloorHost"
	add_child(floor_host)

	hud = HUDScript.new() as HotelHUD
	hud.name = "HUD"
	add_child(hud)

	player = PlayerScene.instantiate() as CharacterBody3D
	player.name = "Player"
	player.managed_mode = true
	add_child(player)

	run_controller = ControllerScript.new()
	run_controller.name = "RunController"
	add_child(run_controller)
	run_controller.configure(self, floor_host, player, hud)
	run_controller.start_new_run()
