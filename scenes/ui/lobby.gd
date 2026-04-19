extends CanvasLayer

@onready var start_btn = $ColorRect/VBoxContainer/StartButton
@onready var waiting_label = $ColorRect/VBoxContainer/WaitingLabel
@onready var player_count_label = $ColorRect/VBoxContainer/PlayerCountLabel
@onready var connection_info_container = $ColorRect/VBoxContainer/ConnectionInfoContainer
@onready var ip_label = $ColorRect/VBoxContainer/ConnectionInfoContainer/IpPanel/IpLabel
@onready var game_id_label = $ColorRect/VBoxContainer/ConnectionInfoContainer/GameIdPanel/GameIdLabel
@onready var game_id_panel = $ColorRect/VBoxContainer/ConnectionInfoContainer/GameIdPanel

var load_timer: float = 10.0
var time_left: float = 10.0
var progress_bar: ProgressBar

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	progress_bar = ProgressBar.new()
	progress_bar.max_value = load_timer
	progress_bar.value = 0
	progress_bar.custom_minimum_size = Vector2(0, 30)
	progress_bar.show_percentage = false
	start_btn.get_parent().add_child(progress_bar)
	start_btn.get_parent().move_child(progress_bar, start_btn.get_index())
	
	if NetworkManager.is_hosting_game:
		start_btn.show()
		start_btn.disabled = true
		waiting_label.text = "Loading terrain..."
	else:
		start_btn.hide()
		progress_bar.hide()
		waiting_label.text = "Waiting for Host... (Match begins ~10s after host creation)"
		
	if NetworkManager.active_host_ip != "":
		ip_label.text = "IP: " + NetworkManager.active_host_ip
		if NetworkManager.active_game_id != "":
			game_id_label.text = "ID: " + NetworkManager.active_game_id
		else:
			game_id_panel.hide()
	else:
		connection_info_container.hide()

func _process(delta):
	if multiplayer.has_multiplayer_peer():
		var count = multiplayer.get_peers().size() + 1
		player_count_label.text = "Players Connected: " + str(count)
		
	if NetworkManager.is_hosting_game and time_left > 0:
		time_left -= delta
		progress_bar.value = load_timer - time_left
		waiting_label.text = "Loading terrain: %d s" % ceil(time_left)
		if time_left <= 0:
			time_left = 0
			progress_bar.hide()
			start_btn.disabled = false
			waiting_label.text = "Ready to start!"

func _on_start_button_pressed():
	# Disable button so we don't spam
	start_btn.disabled = true
	var mm = get_tree().root.find_child("MultiplayerManager", true, false)
	if mm and mm.has_method("start_match_request"):
		mm.start_match_request.rpc_id(1)

func _on_copy_ip_pressed():
	DisplayServer.clipboard_set(NetworkManager.active_host_ip)

func _on_copy_game_id_pressed():
	DisplayServer.clipboard_set(NetworkManager.active_game_id)
