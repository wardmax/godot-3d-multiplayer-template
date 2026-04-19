extends Area3D

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# Only server handles kills to keep it authoritative
	if not multiplayer.is_server():
		return
	
	if body.has_method("die"):
		body.die(0)  # 0 = no killer (environmental death)
