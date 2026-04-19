extends Node3D

@export var speed: float = 40.0
@export var damage: float = 10.0
@export var lifetime: float = 2.0

var _timer: float = 0.0

func _ready():
	# Ensure the bullet is top-level so it doesn't move with the player that spawned it
	set_as_top_level(true)

func _physics_process(delta: float):
	# Move forward in local Z axis (usually -Z is forward in Godot)
	# However, since we set it top-level, we use transform.basis.z
	position -= transform.basis.z * speed * delta
	
	_timer += delta
	if _timer >= lifetime:
		queue_free()

func _on_area_3d_body_entered(body: Node3D):
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
	
	# Bullet hit something (wall or player)
	queue_free()
