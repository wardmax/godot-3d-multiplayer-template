extends RigidBody3D
class_name Throwable

@export var explode_on_impact: bool = true
@export var explosion_radius: float = 3.0
@export var fuse_time: float = 0.0
@export var destroy_voxels: bool = true
@export var shrapnel_count: int = 20
@export var shrapnel_speed: float = 15

var exploded: bool = false
var last_hit_terrain: NodePath

func _ready():
	if multiplayer.is_server():
		contact_monitor = true
		max_contacts_reported = 1
		body_entered.connect(_on_body_entered)
		
		if fuse_time > 0.0:
			get_tree().create_timer(fuse_time).timeout.connect(_explode)
	else:
		contact_monitor = false

func _physics_process(_delta):
	# Align the football nose (local X-axis) to face its velocity direction every frame.
	# This gives a realistic arc as gravity bends the trajectory.
	if linear_velocity.length() > 0.5:
		var vel_dir = linear_velocity.normalized()
		# Build a basis where the local X-axis points in the direction of travel.
		var up = Vector3.UP
		if abs(vel_dir.dot(up)) > 0.99:
			up = Vector3.FORWARD
		var new_basis = Basis(vel_dir, up.cross(vel_dir).normalized(), vel_dir.cross(up.cross(vel_dir).normalized()))
		# Smoothly blend to avoid snapping
		global_transform.basis = global_transform.basis.slerp(new_basis, 0.3)

func _on_body_entered(body):
	if body is VoxelTerrain:
		last_hit_terrain = body.get_path()
		
	if exploded or not multiplayer.is_server():
		return
		
	if explode_on_impact:
		_explode()
		
func _explode():
	if exploded or not multiplayer.is_server():
		return
	exploded = true
	_trigger_explosion()
	sync_explode.rpc()

@rpc("call_local", "authority", "reliable")
func sync_explode():
	_spawn_shrapnel()
	queue_free()

func _trigger_explosion():
	if destroy_voxels:
		var terrain_path = last_hit_terrain
		if terrain_path.is_empty():
			var terrain = get_tree().root.find_child("VoxelTerrain", true, false)
			if terrain:
				terrain_path = terrain.get_path()
			else:
				terrain_path = NodePath("/root/Game/world/VoxelTerrain")
		_find_player_and_explode(get_tree().root, terrain_path)

func _find_player_and_explode(node: Node, terrain_path: NodePath) -> bool:
	if node.has_method("destroy_voxel_sphere"):
		node.destroy_voxel_sphere.rpc(terrain_path, global_position, explosion_radius)
		return true
		
	for child in node.get_children():
		if _find_player_and_explode(child, terrain_path):
			return true
	return false

func _spawn_shrapnel():
	# Spawn shrapnel visually on server and clients
	for i in range(shrapnel_count):
		var s = RigidBody3D.new()
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(randf_range(0.05, 0.18), randf_range(0.05, 0.18), randf_range(0.05, 0.18))
		mesh_inst.mesh = box
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color("8d6319")
		mat.roughness = 0.9
		mesh_inst.material_override = mat
		
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		
		s.add_child(mesh_inst)
		s.add_child(col)
		get_tree().root.add_child(s)
		s.global_position = global_position
		
		# Random spread direction with upward bias
		var rand_dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.2, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		var speed = randf_range(shrapnel_speed * 0.4, shrapnel_speed)
		s.apply_impulse(rand_dir * speed)
		s.angular_velocity = Vector3(randf_range(-8,8), randf_range(-8,8), randf_range(-8,8))
		
		# Auto-clean shrapnel after a few seconds
		get_tree().create_timer(randf_range(2.5, 4.0)).timeout.connect(func():
			if is_instance_valid(s):
				s.queue_free()
		)
