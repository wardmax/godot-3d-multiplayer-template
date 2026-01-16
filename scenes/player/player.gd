extends CharacterBody2D

# --- Constants & Config ---
const SPEED = 300.0
const FRICTION = 1500.0
const ACCEL = 1500.0

# --- Dash Config ---
const DASH_SPEED = 1400.0
const DASH_DURATION = 0.25 
var is_dashing = false

@onready var bullet_packed_scene = preload("res://scenes/player/bullet.tscn")
@onready var health_bar = $HealthBarPivot/ProgressBar
@onready var health_bar_pivot = $HealthBarPivot
@onready var animation_player = $AnimatedSprite2D

# --- Variables ---
@export var health: int = 100: set = set_health

# --- Setup Logic ---
func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	if health_bar:
		health_bar.value = health
	
	collision_layer = 2 
	collision_mask = 1

	if not is_multiplayer_authority():
		set_physics_process(false)
	else:
		$Camera2D.make_current()

# --- Setters ---
func set_health(new_value: int) -> void:
	health = new_value
	if health_bar:
		health_bar.value = health

# --- Combat Logic ---
@rpc("any_peer", "call_local", "reliable")
func fire_bullet_rpc(target_pos: Vector2):
	if not multiplayer.is_server():
		return
	var bullet = bullet_packed_scene.instantiate()
	bullet.shooter_id = multiplayer.get_remote_sender_id()
	get_parent().add_child(bullet, true)
	bullet.global_position = self.global_position
	bullet.look_at(target_pos)

func take_damage(amount: int):
	if not multiplayer.is_server():
		return
	health -= amount
	if health <= 0:
		die_rpc.rpc()

@rpc("any_peer", "call_local", "reliable")
func die_rpc():
	health = 100
	if health_bar: health_bar.value = 100
	global_position = Vector2.ZERO 
	velocity = Vector2.ZERO

# --- Dash Logic ---
func dash():
	if is_dashing: return
	is_dashing = true
	
	# Dash towards mouse
	var dash_dir = global_position.direction_to(get_global_mouse_position())
	velocity = dash_dir * DASH_SPEED
	
	await get_tree().create_timer(DASH_DURATION).timeout
	
	# Snap back to normal speed instantly to stop the "sliding"
	velocity = dash_dir * SPEED
	is_dashing = false

# --- Main Loop ---
func _process(_delta: float) -> void:
	if health_bar_pivot:
		health_bar_pivot.global_rotation = 0.0

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	
	var mouse_pos = get_global_mouse_position()
	look_at(mouse_pos)
	
	# 1. MOVEMENT CALCULATIONS
	if not is_dashing:
		# Change "move" to whatever input you want to use to go forward
		if Input.is_action_pressed("move"): 
			var direction = global_position.direction_to(mouse_pos)
			velocity = velocity.move_toward(direction * SPEED, ACCEL * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	
	move_and_slide()

	# 2. ANIMATION CONTROLLER
	# We only play walk/idle if a "one-shot" animation isn't currently playing
	var is_playing_special = (animation_player.animation == "attack" or animation_player.animation == "dodge") and animation_player.is_playing()
	
	if not is_playing_special:
		if velocity.length() > 20:
			animation_player.play("walk")
		else:
			animation_player.stop() # Or play("idle") if you have one

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Handle Shooting
	if event.is_action_pressed("shoot"):
		# Play animation first
		animation_player.play("attack")
		# Fire bullet (RPC handles the server-side spawn)
		await animation_player.animation_finished
		fire_bullet_rpc.rpc(get_global_mouse_position())
		# Use await so the physics_process knows we are "busy" until the last frame
		

	# Handle Dashing
	if event.is_action_pressed("dash"):
		if not is_dashing:
			animation_player.play("dodge")
			dash()
			# Wait for animation to finish so it doesn't get cut off by "walk"
			await animation_player.animation_finished
