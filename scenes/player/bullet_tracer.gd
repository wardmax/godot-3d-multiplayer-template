extends MeshInstance3D

func init(from: Vector3, to: Vector3):
	var dist = from.distance_to(to)
	if dist < 0.1:
		queue_free()
		return
		
	global_position = from
	# Points towards hit point
	look_at(to)
	# Add random rotation around the Z-axis (muzzle direction) for variation
	rotate_object_local(Vector3.FORWARD, randf() * TAU)
	
	# Initial random scale for variety - increased for better visibility
	var base_scale = randf_range(1.0, 2.0)
	scale = Vector3(base_scale, base_scale, base_scale)
	
	var tween = create_tween()
	# Fast grow and shrink effect
	tween.tween_property(self, "scale", Vector3.ZERO, 0.05).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(queue_free)
