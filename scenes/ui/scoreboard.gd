extends CanvasLayer

@onready var item_list = $ColorRect/VBoxContainer/ItemList
@onready var timer_label = $ColorRect/VBoxContainer/TimerLabel

func update_ui(stats: Dictionary):
	if not is_node_ready():
		await ready
		
	# Clear old children
	for c in item_list.get_children():
		c.queue_free()
		
	# Sort players by height descending
	var sorted_players = stats.keys()
	sorted_players.sort_custom(func(a, b): return stats[a]["height"] > stats[b]["height"])
	
	for net_id in sorted_players:
		var p_data = stats[net_id]
		var hbox = HBoxContainer.new()
		
		var l_name = Label.new()
		l_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l_name.text = "Player " + str(net_id)
		if net_id == multiplayer.get_unique_id():
			l_name.text += " (You)"
			l_name.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		hbox.add_child(l_name)
		
		var l_kills = Label.new()
		l_kills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_kills.text = str(p_data["kills"])
		hbox.add_child(l_kills)
		
		var l_height = Label.new()
		l_height.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l_height.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l_height.text = str(p_data["height"]) + "m"
		hbox.add_child(l_height)
		
		item_list.add_child(hbox)

func update_timer(seconds_remaining: float):
	if not is_node_ready():
		await ready
	var mins = int(seconds_remaining) / 60
	var secs = int(seconds_remaining) % 60
	timer_label.text = "%d:%02d" % [mins, secs]
	
	# Flash red when time is low
	if seconds_remaining <= 30:
		timer_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	else:
		timer_label.remove_theme_color_override("font_color")
