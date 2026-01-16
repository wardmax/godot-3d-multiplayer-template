extends Area2D

@export var speed: float = 1500.0
@export var lifetime: float = .5

var _time_passed: float = 0.0
@export var damage: int = 20
var shooter_id: int # We need to set this when the bullet is spawned

func _physics_process(delta: float) -> void:
	# 1. Move the bullet forward based on its rotation
	# (Vector2.RIGHT assumes your bullet sprite faces right by default)
	var direction = Vector2.RIGHT.rotated(rotation)
	global_position += direction * speed * delta

	# 2. Track time passed
	_time_passed += delta
	
	# 3. Only the server should decide when the bullet dies
	if multiplayer.is_server():
		if _time_passed >= lifetime:
			queue_free() # This deletion will sync to all clients automatically


func _on_body_entered(body: Node2D) -> void:
	# ONLY the server handles hit logic
	if not multiplayer.is_server():
		return
	# Check if the thing we hit is a player and NOT the person who shot it
	if body.is_in_group("players") and body.name != str(shooter_id):
		if body.has_method("take_damage"):
			print("shooter",shooter_id,"body",body)
			body.take_damage(damage)
		queue_free() # Destroy bullet after hit
	elif body.is_in_group("walls"):
		queue_free() # Destroy bullet on walls
