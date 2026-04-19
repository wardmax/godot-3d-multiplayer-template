extends CharacterBody3D

@export var SPEED = 5.0
@export var ACCEL = 10.0
@export var FRICTION = 30.0
@export var JUMP_VELOCITY = 4.5
@export var MOUSE_SENSITIVITY = 0.003

@export var FIRE_RATE = .2
@export var MAX_AMMO = 20
@export var RELOAD_TIME = 2.0
@export var BULLET_SPREAD = 3 # Spread amount at the raycast's max distance

enum Weapon { GUN, THROWABLE, SHOVEL }
var current_weapon = Weapon.GUN

var equipped_throwable_scene = "res://scenes/player/footbomb.tscn"
var is_priming_throw: bool = false
var primed_throw_force: float = 15.0

var current_ammo = 20
var collected_blocks = 0
var time_since_last_shot = 0.0
var is_reloading = false

var trajectory_multimesh := MultiMeshInstance3D.new()
var charge_start_time: float = 0.0

var server_last_shot_time = 0
var consecutive_shots = 0

# Procedural Recoil State
var gun_recoil_rotation = Vector3.ZERO
var target_gun_recoil_rotation = Vector3.ZERO
var gun_base_rotation = Vector3.ZERO

# Get gravity from project settings to keep it consistent
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _enter_tree():
	var id = str(name).to_int()
	if id != 0:
		set_multiplayer_authority(id)
		var sync = get_node_or_null("MultiplayerSynchronizer")
		if sync:
			sync.set_multiplayer_authority(id)

func _ready():
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 40
	var sphere = SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = mat
	mm.mesh = sphere
	
	trajectory_multimesh.multimesh = mm
	trajectory_multimesh.top_level = true
	trajectory_multimesh.visible = false
	add_child(trajectory_multimesh)
	
	# Configure authority if name is already set (Server), or wait for renamed signal (Client)
	_setup_authority()
	renamed.connect(_setup_authority)
	
	if has_node("Camera3D/gun"):
		gun_base_rotation = $Camera3D/gun.rotation

func _setup_authority():
	var id = str(name).to_int()
	if id == 0:
		return # Not yet renamed by MultiplayerSpawner
		
	set_multiplayer_authority(id)
	
	if has_node("MultiplayerSynchronizer"):
		$MultiplayerSynchronizer.set_multiplayer_authority(id)
		
	if is_multiplayer_authority():
		var mm = get_tree().root.find_child("MultiplayerManager", true, false)
		if mm and not mm.is_match_started:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
		if has_node("Camera3D"):
			$Camera3D.current = true
		
		# Request spawn info from server (clients only)
		if not multiplayer.is_server():
			request_spawn_point.rpc_id(1)
		
		# Set initial weapon models
		set_weapon(Weapon.GUN)
	else:
		if has_node("Camera3D"):
			$Camera3D.current = false

func _unhandled_input(event):
	# Only handle look input for the local player
	if not is_multiplayer_authority():
		return
		
	var mm = get_tree().root.find_child("MultiplayerManager", true, false)
	if mm and not mm.is_match_started:
		return

	# Handle Mouse Look
	if event is InputEventMouseMotion:
		# Rotate the whole player left/right (Y axis)
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		
		# Rotate the camera up/down (X axis) - Assumes you have a Camera3D child
		var camera = $Camera3D 
		if camera:
			camera.rotate_x(event.relative.y * MOUSE_SENSITIVITY)
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

	# Toggle mouse capture with ESC
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

@export var health = 100

func _physics_process(delta: float) -> void:
	# Only handle input for the local player
	if not is_multiplayer_authority():
		return

	var mm = get_tree().root.find_child("MultiplayerManager", true, false)
	if mm and not mm.is_match_started:
		velocity = Vector3.ZERO
		# Snap to ground as it generates async in the background
		var query = PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 50, 0), global_position + Vector3(0, -150, 0))
		query.exclude = [self.get_rid()]
		var result = get_world_3d().direct_space_state.intersect_ray(query)
		if result and result.collider is VoxelTerrain:
			# Snap slightly above the voxel surface so they're waiting on the floor comfortably
			global_position.y = result.position.y + 1.0
		return

	# 1. Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Handle Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 3. WASD Movement (Relative to where you are looking)
	var input_dir = Input.get_vector("left", "right", "up", "down")
	
	# transform.basis ensures 'forward' is wherever the player is facing
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = move_toward(velocity.x, -direction.x * SPEED, ACCEL * delta)
		velocity.z = move_toward(velocity.z, -direction.z * SPEED, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)

	move_and_slide()

	# Weapon Switching
	if Input.is_physical_key_pressed(KEY_1):
		set_weapon(Weapon.THROWABLE)
	elif Input.is_physical_key_pressed(KEY_2):
		set_weapon(Weapon.GUN)
	elif Input.is_physical_key_pressed(KEY_3):
		set_weapon(Weapon.SHOVEL)

	# 4. Scoreboard Toggling
	if Input.is_physical_key_pressed(KEY_TAB):
		var sb = get_tree().root.find_child("Scoreboard", true, false)
		if sb: sb.visible = true
	else:
		var sb = get_tree().root.find_child("Scoreboard", true, false)
		if sb: sb.visible = false

	# 5. Shooting & Reloading
	time_since_last_shot += delta
	
	# Procedural Continuous Recoil
	var is_shooting = Input.is_action_pressed("shoot") and not is_reloading and current_ammo > 0
	if is_shooting:
		var time = Time.get_ticks_msec() / 1000.0
		# Pitch up by ~4.5 degrees (0.08 radians) and add a tiny vertical vibration
		target_gun_recoil_rotation.x = 0.08 + sin(time * 45.0) * 0.01
		# Wiggle side-to-side (Yaw)
		target_gun_recoil_rotation.y = sin(time * 35.0) * 0.04
		# Wiggle roll slightly
		target_gun_recoil_rotation.z = cos(time * 30.0) * 0.03
	else:
		target_gun_recoil_rotation = Vector3.ZERO
		
	gun_recoil_rotation = gun_recoil_rotation.lerp(target_gun_recoil_rotation, delta * 24.0)
	if has_node("Camera3D/gun"):
		$Camera3D/gun.rotation = gun_base_rotation + gun_recoil_rotation
	
	if Input.is_action_just_pressed("reload") or Input.is_physical_key_pressed(KEY_R):
		if current_ammo < MAX_AMMO and not is_reloading and current_weapon == Weapon.GUN:
			$SoundFX/reloadFX.play()
			reload_weapon()
			
	if current_weapon == Weapon.THROWABLE:
		var holding_left = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_pressed("shoot")
		
		# Start priming throw
		if holding_left and not is_priming_throw:
			is_priming_throw = true
			charge_start_time = Time.get_ticks_msec() / 1000.0
			
		if is_priming_throw:
			if holding_left:
				# Scale throw force based on hold time (up to 1.5 seconds)
				var hold_duration = (Time.get_ticks_msec() / 1000.0) - charge_start_time
				primed_throw_force = lerp(5.0, 30.0, min(hold_duration / 1.5, 1.0))
				draw_trajectory()
			else:
				# Let go -> throw it!
				is_priming_throw = false
				trajectory_multimesh.visible = false
				request_spawn_throwable.rpc_id(1, equipped_throwable_scene, get_node("Camera3D/gun/Muzzle").global_position, -$Camera3D.global_transform.basis.z * primed_throw_force)
				set_weapon(Weapon.GUN)
	elif current_weapon == Weapon.SHOVEL:
		if time_since_last_shot >= 0.5: # Dig/place cooldown
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_pressed("shoot"):
				time_since_last_shot = 0.0
				shovel_action.rpc_id(1, true)
				$SoundFX/shootFX.pitch_scale = randf_range(1.4, 1.6)
				$SoundFX/shootFX.play()
			elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				if collected_blocks > 0:
					time_since_last_shot = 0.0
					shovel_action.rpc_id(1, false)
					$SoundFX/shootFX.pitch_scale = randf_range(0.7, 0.9)
					$SoundFX/shootFX.play()
				else:
					if Input.is_action_just_pressed("aim") or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
						$SoundFX/dryfireFX.play()
	else:
		if Input.is_action_pressed("shoot") and not is_reloading:
			if time_since_last_shot >= FIRE_RATE:
				if current_ammo > 0:
					time_since_last_shot = 0.0
					current_ammo -= 1
					shoot.rpc_id(1) # Send to server
					
					$SoundFX/shootFX.pitch_scale = randf_range(0.9, 1.2)
					$SoundFX/shootFX.play()
				elif Input.is_action_just_pressed("shoot"):
					print("Click! Out of ammo.")
					$SoundFX/dryfireFX.play()

func draw_trajectory():
	trajectory_multimesh.visible = true
	var mm = trajectory_multimesh.multimesh
	
	# Hide all initially
	for i in range(mm.instance_count):
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	
	var muzzle = get_node_or_null("Camera3D/gun/Muzzle")
	var cam = get_node_or_null("Camera3D")
	if not muzzle or not cam:
		return
		
	var start_pos = muzzle.global_position
	var initial_vel = -cam.global_transform.basis.z * primed_throw_force
	
	var time_step = 0.05
	var current_pos = start_pos
	var current_vel = initial_vel
	
	for i in range(mm.instance_count):
		mm.set_instance_transform(i, Transform3D(Basis(), current_pos))
		
		var next_vel = current_vel + Vector3(0, -gravity, 0) * time_step
		var next_pos = current_pos + current_vel * time_step + Vector3(0, -gravity, 0) * time_step * time_step * 0.5
		
		var query = PhysicsRayQueryParameters3D.create(current_pos, next_pos)
		query.exclude = [self.get_rid()]
		var result = get_world_3d().direct_space_state.intersect_ray(query)
		
		if result:
			if i + 1 < mm.instance_count:
				mm.set_instance_transform(i + 1, Transform3D(Basis(), result.position))
			break
			
		current_pos = next_pos
		current_vel = next_vel

func reload_weapon():
	is_reloading = true
	print("Reloading...")
	await get_tree().create_timer(RELOAD_TIME).timeout
	current_ammo = MAX_AMMO
	is_reloading = false
	print("Reload complete!")

@rpc("any_peer", "call_local")
func shoot():
	# Only the server handles the actual hit detection logic
	if not multiplayer.is_server():
		return
		
	# Track consecutive shots for recoil control
	var current_time = Time.get_ticks_msec()
	# If it's been more than 2.5x the fire rate since the last shot, reset consecutive shots
	if current_time - server_last_shot_time > (FIRE_RATE * 1000 * 2.5):
		consecutive_shots = 0
		
	server_last_shot_time = current_time
	consecutive_shots += 1
		
	var ray = $Camera3D/RayCast3D
	var muzzle = $Camera3D/gun/Muzzle
	
	if ray and muzzle:
		# Save the original target position to restore it later
		var original_target = ray.target_position
		
		# Only apply spray after the first 2 shots
		if consecutive_shots > 2:
			# Apply random bullet spread to the target position
			# Ray points along local -Y (0, -1500, 0), so we spread across X and Z.
			# Multiply by a factor so BULLET_SPREAD represents the spread amount at 50 meters.
			var spread_factor = abs(ray.target_position.y) / 50.0 
			ray.target_position.x += randf_range(-BULLET_SPREAD, BULLET_SPREAD) * spread_factor
			ray.target_position.z += randf_range(-BULLET_SPREAD, BULLET_SPREAD) * spread_factor
		
		ray.force_raycast_update()
		
		var hit_point = ray.to_global(ray.target_position)	
		var target = ray.get_collider()
		var hit_normal = Vector3.UP
		var hit_something = false
		
		if ray.is_colliding():
			hit_point = ray.get_collision_point()
			hit_normal = ray.get_collision_normal()
			hit_something = true
			
			# Handle hitting players
			if target and target.has_method("take_damage"):
				var shooter = multiplayer.get_remote_sender_id()
				var body_part = ["head","body"][ray.get_collider_shape()]
				if(body_part == "head"):
					target.take_damage(100, shooter) #headshot
				else:
					target.take_damage(randi_range(15,30), shooter)
				hit_something = false # Don't place a static bullet hole on damageable entities
			
			#hitting voxel
			# Get the VoxelTool
			elif target is VoxelTerrain:
				var world_pos = hit_point - hit_normal * 0.1
				var local_pos = target.to_local(world_pos)
				var voxel_pos = Vector3i(
					floor(local_pos.x),
					floor(local_pos.y),
					floor(local_pos.z)
				)
				# Replicate the voxel destruction to all clients
				destroy_voxel.rpc(target.get_path(), voxel_pos)
				
			# Apply physics force if it's a Rigidbody
			if target is RigidBody3D:
				var push_dir = (hit_point - muzzle.global_position).normalized()
				target.apply_impulse(push_dir * 5.0, hit_point - target.global_position)
		
		# Broadcast visual effects to all clients
		create_tracer.rpc(muzzle.global_position, hit_point)
		
		if hit_something:
			create_bullethole.rpc(hit_point, hit_normal)
			
		# Restore original raycast path for the next shot
		ray.target_position = original_target
		
@rpc("any_peer", "call_local")
func destroy_voxel(terrain_path: NodePath, voxel_pos: Vector3i):
	var terrain = get_node_or_null(terrain_path)
	if terrain == null:
		# Try from the root in case the path is absolute
		terrain = get_tree().root.get_node_or_null(terrain_path)
	if terrain == null:
		push_warning("destroy_voxel: could not find VoxelTerrain at path: ", terrain_path)
		return
	var vt = terrain.get_voxel_tool()
	vt.set_voxel(voxel_pos, 0)

@rpc("any_peer", "call_local")
func destroy_voxel_sphere(terrain_path: NodePath, world_pos: Vector3, radius: float):
	var terrain = get_node_or_null(terrain_path)
	if terrain == null:
		terrain = get_tree().root.get_node_or_null(terrain_path)
	if terrain == null:
		push_warning("destroy_voxel_sphere: could not find VoxelTerrain at path: ", terrain_path)
		return
	var vt = terrain.get_voxel_tool()
	vt.value = 0
	var local_pos = terrain.to_local(world_pos)
	var local_radius = radius / terrain.scale.x
	vt.do_sphere(local_pos, local_radius)

@rpc("any_peer", "call_local")
func request_spawn_throwable(scene_path: String, pos: Vector3, impulse: Vector3):
	if not multiplayer.is_server():
		return
	var b_name = "Throw_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	spawn_throwable.rpc(scene_path, pos, impulse, b_name)

@rpc("any_peer", "call_local")
func spawn_throwable(scene_path: String, pos: Vector3, impulse: Vector3, b_name: String = ""):
	var bomb_scene = load(scene_path)
	if bomb_scene:
		var bomb = bomb_scene.instantiate()
		if b_name != "":
			bomb.name = b_name
		get_tree().root.add_child(bomb)
		bomb.global_position = pos
		
		# Football orientation alignment
		if impulse.length() > 0.1:
			var z_forward_basis = Basis.looking_at(impulse.normalized(), Vector3.UP)
			# The model is oriented along the X axis. Rotate our basis 90 deg so X points towards impulse.
			bomb.global_transform.basis = z_forward_basis.rotated(Vector3.UP, deg_to_rad(90))
			
		if bomb is RigidBody3D:
			bomb.apply_impulse(impulse)
			# Add tight spiral spin along its local X-axis (the nose)
			bomb.angular_velocity = bomb.global_transform.basis.x * 15.0

@rpc("any_peer", "call_local")
func create_bullethole(pos: Vector3, normal: Vector3):
	var bullethole = preload("res://scenes/world/bullethole.tscn").instantiate()
	get_tree().root.add_child(bullethole)
	bullethole.global_position = pos
	
	if normal != Vector3.ZERO:
		var up = Vector3.UP if abs(normal.y) < 0.999 else Vector3.RIGHT
		# Decals project along their local Y axis in Godot 4.
		# We align the decal's Y axis with the wall normal, meaning it points out the wall face.
		var align_basis = Basis()
		align_basis.y = normal
		align_basis.x = normal.cross(up).normalized()
		align_basis.z = align_basis.x.cross(normal).normalized()
		bullethole.global_basis = align_basis
		
	await get_tree().create_timer(3).timeout
	if is_instance_valid(bullethole):
		bullethole.queue_free()

@rpc("any_peer", "call_local")
func create_tracer(from: Vector3, to: Vector3):
	var tracer = preload("res://scenes/player/bullet_tracer.tscn").instantiate()
	get_parent().add_child(tracer)
	tracer.init(from, to)
	
	if has_node("Camera3D/gun/AnimationPlayer"):
		var anim = $Camera3D/gun/AnimationPlayer
		anim.stop()
		anim.play("recoil")

@rpc("any_peer", "call_local")
func shovel_action(is_digging: bool):
	if not multiplayer.is_server():
		return
	
	var ray = $Camera3D/RayCast3D
	ray.force_raycast_update()
	if ray.is_colliding() and ray.get_collider() is VoxelTerrain:
		var hit_point = ray.get_collision_point()
		var hit_normal = ray.get_collision_normal()
		var target = ray.get_collider()
		
		var offset = -0.1 if is_digging else 0.1
		var world_pos = hit_point + hit_normal * offset
		var local_pos = target.to_local(world_pos)
		
		var voxel_pos = Vector3i(floor(local_pos.x), floor(local_pos.y), floor(local_pos.z))
		var val = 0 if is_digging else 1
		
		# A 3x3x3 chunk is modeled as costing/yielding 1 "bucket" of blocks for simplicity
		if is_digging:
			collected_blocks += 1
		else:
			collected_blocks -= 1
			
		update_collected_blocks.rpc_id(str(name).to_int(), collected_blocks)
		set_voxel_chunk_synced.rpc(target.get_path(), voxel_pos, val)

@rpc("any_peer", "call_local")
func update_collected_blocks(count: int):
	collected_blocks = count

@rpc("any_peer", "call_local")
func set_voxel_chunk_synced(terrain_path: NodePath, voxel_pos: Vector3i, val: int):
	var terrain = get_tree().root.get_node_or_null(terrain_path)
	if terrain == null:
		terrain = get_tree().root.find_child("VoxelTerrain", true, false)
	if terrain is VoxelTerrain:
		var vt = terrain.get_voxel_tool()
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					vt.set_voxel(voxel_pos + Vector3i(x, y, z), val)

@rpc("any_peer", "call_remote")
func request_spawn_point():
	if multiplayer.is_server():
		var mm = get_tree().root.find_child("MultiplayerManager", true, false)
		if mm:
			var pos = mm.get_spawn_pos(multiplayer.get_remote_sender_id())
			respawn.rpc_id(multiplayer.get_remote_sender_id(), pos)

func set_weapon(w: Weapon):
	current_weapon = w
	is_priming_throw = false
	trajectory_multimesh.visible = false
	update_weapon_mesh()
	
func update_weapon_mesh():
	var w_gun = get_node_or_null("Camera3D/gun")
	var w_shovel = get_node_or_null("Camera3D/Shovel")
	var w_bomb = get_node_or_null("Camera3D/Bomb")
	
	if w_gun: w_gun.visible = (current_weapon == Weapon.GUN)
	if w_shovel: w_shovel.visible = (current_weapon == Weapon.SHOVEL)
	if w_bomb: w_bomb.visible = (current_weapon == Weapon.THROWABLE)

func take_damage(amount, shooter_id=0):
	health -= amount
	print("Player took damage! Health: ", health)
	if health <= 0:
		die(shooter_id)

func die(shooter_id=0):
	print("Player died!")
	health = 100
	var spawn_pos = Vector3(0, 150, 0)
	
	if multiplayer.is_server():
		var mm = get_tree().root.find_child("MultiplayerManager", true, false)
		if mm:
			if shooter_id != 0:
				mm.report_kill(shooter_id)
			spawn_pos = mm.get_spawn_pos(str(name).to_int())
			
	respawn.rpc_id(get_multiplayer_authority(), spawn_pos)

@rpc("any_peer", "call_local")
func respawn(spawn_pos: Vector3):
	health = 100
	velocity = Vector3.ZERO
	
	# Raycast to ensure we start directly on the procedural ground
	var query = PhysicsRayQueryParameters3D.create(spawn_pos + Vector3(0, 100, 0), spawn_pos + Vector3(0, -200, 0))
	query.exclude = [self.get_rid()]
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	
	if result and result.collider is VoxelTerrain:
		global_position = result.position + Vector3(0, 1.0, 0)
	else:
		global_position = spawn_pos
