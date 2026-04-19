class_name MultiplayerManager
extends Node

# The bulk of this script is for the authority (host/server).
@onready var _player_spawn_point = $"../PlayerSpawn"

var _multiplayer_scene = preload("res://scenes/player/player.tscn")
var _players_in_game: Dictionary = {}
var _player_stats: Dictionary = {}
var is_match_started = false

# ── Match Timer ──────────────────────────────────────────────────
# Edit this value to change the match length (in seconds)
const MATCH_DURATION: float = 30.0  # 5:00
var _time_remaining: float = MATCH_DURATION
var _timer_sync_accum: float = 0.0  # Only broadcast timer every second

func _process(delta):
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		var stats_changed = false
		for net_id in _players_in_game:
			var p = _players_in_game[net_id]
			if is_instance_valid(p) and _player_stats.has(net_id):
				var h = int(p.global_position.y)
				if _player_stats[net_id]["height"] != h:
					_player_stats[net_id]["height"] = h
					stats_changed = true
					
		if stats_changed:
			update_local_scoreboard()
			sync_scoreboard.rpc(_player_stats)
			
		# Match timer — only runs when match is active
		if is_match_started and _time_remaining > 0:
			_time_remaining -= delta
			_timer_sync_accum += delta
			
			# Sync timer to all clients once per second
			if _timer_sync_accum >= 1.0:
				_timer_sync_accum = 0.0
				sync_timer.rpc(_time_remaining)
				update_local_scoreboard_timer(_time_remaining)
			
			if _time_remaining <= 0:
				_time_remaining = 0
				_on_match_end()

func _ready():
	# NOTE: For client peers, this likely loaded (as part of the Game scene) 
	# before we have an active connection (peer). Therefore, don't rely on this
	# function for client-side network setup or authority checks.

	print("MultiplayerManager ready!")

	# This section is for the authority (host/server), so we don't check for authority
	# unless a peer has been established.
	if multiplayer.has_multiplayer_peer() && is_multiplayer_authority():
		# Leverage the peer connected signal to trigger the player spawn
		multiplayer.peer_connected.connect(_peer_connected)
		
		# Handle the disconnect signal here so we have access to what needs cleaned up in game.
		multiplayer.peer_disconnected.connect(_peer_disconnected)
		
		# We don't want to add a player to a dedicated server instance
		if NetworkManager.is_hosting_game && not OS.has_feature(NetworkManager.DEDICATED_SERVER_FEATURE_NAME):
			print("Adding Host player to game...")
			_add_player_to_game(1)

func _add_player_to_game(network_id: int):
	if is_multiplayer_authority():
		print("Adding player to game: %s" % network_id)
		
		if _players_in_game.get(network_id) == null:
			var player_to_add = _multiplayer_scene.instantiate()
			player_to_add.name = str(network_id)
			_player_stats[network_id] = { "kills": 0, "height": 0 }
			
			_players_in_game[network_id] = player_to_add
			
			# Set the spawn position BEFORE adding to tree so MultiplayerSpawner sends the 
			# correct initial state to the client, preventing desync fall-throughs.
			_ready_player(player_to_add, _players_in_game.size() - 1)
			
			_player_spawn_point.add_child(player_to_add)
			
			if is_multiplayer_authority():
				sync_scoreboard.rpc(_player_stats)
				update_local_scoreboard()
		else:
			print("Warning! Attempted to add existing player to game: %s" % network_id)
	
func _remove_player_from_game(network_id: int):
	if is_multiplayer_authority():
		print("Removing player from game: %s" % network_id)
		if _players_in_game.has(network_id):
			var player_to_remove = _players_in_game[network_id]
			if player_to_remove:
				player_to_remove.queue_free()		
				_players_in_game.erase(network_id)
				_player_stats.erase(network_id)
				
				if is_multiplayer_authority():
					sync_scoreboard.rpc(_player_stats)
					update_local_scoreboard()

# Setup initial or reload saved player properties
func _ready_player(player: CharacterBody3D, index: int = 0):
	if is_multiplayer_authority():
		var markers = _player_spawn_point.get_children().filter(func(c): return c is Marker3D)
		if markers.size() > 0:
			var marker = markers[index % markers.size()]
			# Using local position avoids the !is_inside_tree error when setting before add_child
			player.position = marker.position
		else:
			player.position = Vector3(randi_range(-2, 2), 2,randi_range(-2, 2))

func get_spawn_pos(network_id: int) -> Vector3:
	var keys = _players_in_game.keys()
	keys.sort()
	var idx = keys.find(network_id)
	if idx == -1: idx = 0
	
	var markers = _player_spawn_point.get_children().filter(func(c): return c is Marker3D)
	if markers.size() > 0:
		return markers[idx % markers.size()].global_position
	return Vector3(0, 150, 0)
	
@rpc("any_peer", "call_remote", "reliable")
func sync_scoreboard(stats: Dictionary):
	_player_stats = stats
	update_local_scoreboard()

func update_local_scoreboard():
	var scoreboard = get_tree().root.find_child("Scoreboard", true, false)
	if scoreboard and scoreboard.has_method("update_ui"):
		scoreboard.update_ui(_player_stats)

@rpc("any_peer", "call_local", "reliable")
func report_kill(killer_id: int):
	if is_multiplayer_authority():
		if _player_stats.has(killer_id):
			_player_stats[killer_id]["kills"] += 1
			sync_scoreboard.rpc(_player_stats)
			update_local_scoreboard()

func _peer_connected(network_id: int):
	print("Peer connected: %s" % network_id)
	if is_multiplayer_authority():
		_add_player_to_game(network_id)
		
func _peer_disconnected(network_id: int):
	print("Peer disconnected: %s" % network_id)
	_remove_player_from_game(network_id)

@rpc("any_peer", "call_local")
func start_match_request():
	if not is_multiplayer_authority(): return
	start_match.rpc()

@rpc("any_peer", "call_local", "reliable")
func start_match():
	is_match_started = true
	var lobby = get_tree().root.find_child("Lobby", true, false)
	if lobby: lobby.queue_free()
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if is_multiplayer_authority():
		for net_id in _players_in_game:
			var p = _players_in_game[net_id]
			if p:
				p.respawn.rpc_id(net_id, get_spawn_pos(net_id))

@rpc("any_peer", "call_local", "reliable")
func sync_timer(seconds: float):
	update_local_scoreboard_timer(seconds)

func update_local_scoreboard_timer(seconds: float):
	var scoreboard = get_tree().root.find_child("Scoreboard", true, false)
	if scoreboard and scoreboard.has_method("update_timer"):
		scoreboard.update_timer(seconds)

func _on_match_end():
	if not is_multiplayer_authority():
		return
	
	# Find the winner: highest height among all players
	var winner_id = -1
	var best_height = -INF
	for net_id in _player_stats:
		var h = _player_stats[net_id]["height"]
		if h > best_height:
			best_height = h
			winner_id = net_id
	
	end_match.rpc(winner_id, int(best_height))

@rpc("any_peer", "call_local", "reliable")
func end_match(winner_id: int, winner_height: int):
	is_match_started = false
	
	# Show winner overlay
	var overlay = CanvasLayer.new()
	overlay.name = "WinnerOverlay"
	var label = Label.new()
	label.anchor_left = 0.5
	label.anchor_top = 0.5
	label.anchor_right = 0.5
	label.anchor_bottom = 0.5
	label.grow_horizontal = 2
	label.grow_vertical = 2
	label.offset_left = -300.0
	label.offset_top = -60.0
	label.offset_right = 300.0
	label.offset_bottom = 60.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	
	if winner_id == multiplayer.get_unique_id():
		label.text = "🏆 YOU WIN!\nHeight: %dm" % winner_height
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	else:
		label.text = "Player %d WINS!\nHeight: %dm" % [winner_id, winner_height]
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	
	var hbox = HBoxContainer.new()
	hbox.anchor_left = 0.5
	hbox.anchor_top = 0.5
	hbox.anchor_right = 0.5
	hbox.anchor_bottom = 0.5
	hbox.grow_horizontal = 2
	hbox.grow_vertical = 2
	hbox.offset_left = -200.0
	hbox.offset_top = 100.0
	hbox.offset_right = 200.0
	hbox.offset_bottom = 150.0
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	
	var mm_btn = Button.new()
	mm_btn.text = "Main Menu"
	mm_btn.add_theme_font_size_override("font_size", 24)
	mm_btn.pressed.connect(func(): NetworkManager.disconnect_from_game())
	hbox.add_child(mm_btn)
	
	var pa_btn = Button.new()
	pa_btn.text = "Play Again"
	pa_btn.add_theme_font_size_override("font_size", 24)
	if is_multiplayer_authority():
		pa_btn.pressed.connect(func(): reset_to_lobby.rpc())
	else:
		pa_btn.pressed.connect(func():
			pa_btn.text = "Waiting for Host..."
			pa_btn.disabled = true
		)
	hbox.add_child(pa_btn)
	
	overlay.add_child(label)
	overlay.add_child(hbox)
	get_tree().root.add_child(overlay)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

@rpc("authority", "call_local", "reliable")
func reset_to_lobby():
	var root = get_tree().root
	var overlays = root.find_children("WinnerOverlay", "CanvasLayer", false, false)
	for o in overlays:
		o.queue_free()
		
	is_match_started = false
	_time_remaining = MATCH_DURATION
	
	for net_id in _player_stats:
		_player_stats[net_id]["height"] = 0
		_player_stats[net_id]["kills"] = 0
	
	if is_multiplayer_authority():
		sync_scoreboard.rpc(_player_stats)
		
	var lobby_inst = preload("res://scenes/ui/lobby.tscn").instantiate()
	lobby_inst.name = "Lobby"
	var game = get_parent()
	if game:
		game.add_child(lobby_inst)
		
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
