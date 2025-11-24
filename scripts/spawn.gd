extends Node3D

@onready var address_input: LineEdit = $Menu/IPInput
@onready var spawn_player: Node3D = $SpawnPlayer
@onready var menu: Control = $Menu
@onready var active_player_label: Label = $GameUI/Active
@onready var multiplayer_chat: Control = $MultiplayerChat

var active_players_count: int = 0
var stored_player_data = {}
var player_states = {}  # Format: {player_id: {"nick": "name", "alive": true, "color": Color.WHITE}}
var players_pending_removal = []  # Track players being removed to prevent sync issues

# Character scenes
var character_scenes = {
	"RedTop": "res://scenes/RedTop.tscn",
	"BlackOutfit": "res://scenes/BlackOutfit.tscn",
	"RedTShirt": "res://scenes/RedTShirt.tscn",
	"ScarfShades": "res://scenes/BlueTShirt.tscn"
}

var chat_visible = false

func _ready():
	# Headless server check
	if OS.has_feature("dedicated_server"):
		_setup_headless_mode()
		return
	
	# Client mode setup
	multiplayer_chat.hide()
	menu.show()
	active_player_label.hide()
	multiplayer_chat.set_process_input(true)
	
	Network.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	if multiplayer.is_server():
		Network.connect("player_connected", Callable(self, "_on_player_connected"))

func _setup_headless_mode():
	print("🏃 Headless mode activated - skipping visual setup")
	# Hide all visual elements in headless mode
	if menu:
		menu.hide()
	if active_player_label:
		active_player_label.hide()
	if multiplayer_chat:
		multiplayer_chat.hide()
	
	# Setup network for headless
	Network.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	if multiplayer.is_server():
		Network.connect("player_connected", Callable(self, "_on_player_connected"))

# ============ MULTIPLAYER MODE FUNCTIONS ============

func _on_player_connected(peer_id, player_info):
	if OS.has_feature("dedicated_server"):
		_add_player_headless(peer_id, player_info)
	else:
		_add_player(peer_id, player_info)

func _on_peer_disconnected(id):
	if multiplayer.is_server():
		_safe_remove_player(id)
		
func _on_host_pressed():
	menu.hide()
	
	# Get player name from GameManager
	var player_name = "Player"
	if GameManager.is_logged_in and GameManager.current_player_data:
		player_name = GameManager.current_player_data.get("username", "Player")
	
	Network.start_host(player_name, "player")
	# Add host as first player
	await get_tree().process_frame
	var host_id = multiplayer.get_unique_id()
	if Network.players.has(host_id):
		_add_player(host_id, Network.players[host_id])

func _on_join_pressed():
	menu.hide()
	
	# Get player name from GameManager
	var player_name = "Player"
	if GameManager.is_logged_in and GameManager.current_player_data:
		player_name = GameManager.current_player_data.get("username", "Player")
	
	Network.join_game(player_name, "player", address_input.text.strip_edges())

func _add_player_headless(id: int, player_info: Dictionary):
	"""Headless server player management - no visuals"""
	if id in players_pending_removal:
		return
	
	# Just track player state without visual representation
	var nick = player_info.get("nick", "Player")
	player_states[id] = {"nick": nick, "alive": true, "color": Color.WHITE}
	
	print("Headless: Player ", id, " (", nick, ") connected")
	
	# Update player display
	if multiplayer.is_server():
		_update_active_players_display()
		rpc("sync_player_states", player_states)

func _add_player(id: int, player_info: Dictionary):
	"""Client-side player spawn with visuals"""
	if spawn_player.has_node(str(id)) or id in players_pending_removal:
		return
	
	# Each player loads their exact character from their local GameManager
	var character_name = "RedTop"
	
	if GameManager.is_logged_in and GameManager.current_player_data:
		character_name = GameManager.current_player_data.get("character")
		print("Player ", id, " loading character: ", character_name)
	
	# Load the exact character scene they selected
	var scene_path = character_scenes.get(character_name)
	var character_scene = load(scene_path)
	
	if not character_scene:
		return
	
	var player = character_scene.instantiate()
	player.name = str(id)
	spawn_player.add_child(player, true)
	
	# Spawn with increased radius (8)
	player.global_position = get_spawn_point()
	
	# Set nickname from player_info
	var nick = player_info.get("nick", "Player")
	player_states[id] = {"nick": nick, "alive": true, "color": Color.WHITE}
	
	# Set player nickname display
	if player.has_node("PlayerNick/Nickname"):
		player.get_node("PlayerNick/Nickname").text = nick
		player.get_node("PlayerNick/Nickname").modulate = Color.WHITE
	
	# Create minimap for local player
	if id == multiplayer.get_unique_id():
		_create_minimap_for_player(id, player)
	
	# Update player display
	if multiplayer.is_server():
		_update_active_players_display()
		rpc("sync_player_states", player_states)

func get_spawn_point() -> Vector3:
	var base_position = spawn_player.global_position
	var random_angle = randf() * 2 * PI
	var random_radius = randf() * 4.0
	
	var offset = Vector3(
		cos(random_angle) * random_radius,
		0,
		sin(random_angle) * random_radius
	)
	
	return base_position + offset

func _safe_remove_player(id: int):
	"""Safely remove player with proper cleanup order"""
	if id in players_pending_removal:
		return
	
	players_pending_removal.append(id)
	
	# 1. First destroy the minimap to prevent reference errors (client only)
	if not OS.has_feature("dedicated_server"):
		_destroy_minimap_for_player(id)
	
	# 2. Remove the player node safely (client only)
	if not OS.has_feature("dedicated_server") and spawn_player.has_node(str(id)):
		var player_node = spawn_player.get_node(str(id))
		if player_node:
			# Disable the player node first to stop any processing
			player_node.set_process(false)
			player_node.set_physics_process(false)
			player_node.hide()
			
			# Queue free for safe deletion
			player_node.queue_free()
	
	# 3. Remove from player states
	player_states.erase(id)
	
	# 4. Update display and sync
	_update_active_players_display()
	
	# 5. Sync with all clients if server
	if multiplayer.is_server():
		rpc("sync_player_states", player_states)
	
	# 6. Remove from pending list after a frame
	call_deferred("_remove_from_pending_removal", id)

func _remove_from_pending_removal(id: int):
	players_pending_removal.erase(id)

func _on_quit_pressed() -> void:
	get_tree().quit()

# ============ PLAYER STATES AND DISPLAY ============

func _update_active_players_display():
	var alive_count = 0
	for player_id in player_states:
		if player_states[player_id]["alive"]:
			alive_count += 1
	
	active_players_count = alive_count
	
	# Update the display label with names and status
	_update_active_player_label()
	
	# Sync with all clients if server
	if multiplayer.is_server():
		rpc("sync_active_players_count", active_players_count)

func _update_active_player_label():
	if active_player_label and not OS.has_feature("dedicated_server"):
		var display_text = "Connected Players (" + str(active_players_count) + "):\n"
		
		for player_id in player_states:
			var player_data = player_states[player_id]
			var status_icon = "🟢" if player_data["alive"] else "🔴"
			display_text += status_icon + " " + player_data["nick"] + "\n"
		
		active_player_label.text = display_text
		active_player_label.show()
		
	# Headless server logging
	if OS.has_feature("dedicated_server"):
		print("Active Players: ", active_players_count, " - ", player_states)

# RPC to sync player states across all clients
@rpc("any_peer", "call_local", "reliable")
func sync_player_states(states: Dictionary):
	# Only process states for players that aren't being removed
	var filtered_states = {}
	for player_id in states:
		if player_id not in players_pending_removal:
			filtered_states[player_id] = states[player_id]
	
	player_states = filtered_states
	_update_active_player_label()
	
	# Update visual nickname colors for all players (client only)
	if not OS.has_feature("dedicated_server"):
		for player_id in player_states:
			var player_node = spawn_player.get_node_or_null(str(player_id))
			if player_node and player_node.has_node("PlayerNick/Nickname") and is_instance_valid(player_node):
				var player_data = player_states[player_id]
				player_node.get_node("PlayerNick/Nickname").modulate = player_data["color"]

@rpc("any_peer", "call_local", "reliable")
func sync_active_players_count(count: int):
	active_players_count = count
	_update_active_player_label()

# ============ INPUT HANDLING ============

func _input(event):
	# Skip input handling in headless mode
	if OS.has_feature("dedicated_server"):
		return
		
	# Chat toggle
	if event.is_action_pressed("toggle_chat"):
		toggle_chat()

# ============ MULTIPLAYER CHAT ============

func toggle_chat():
	if menu.visible or OS.has_feature("dedicated_server"):
		return

	chat_visible = !chat_visible
	if chat_visible:
		multiplayer_chat.show()
	else:
		multiplayer_chat.hide()
		get_viewport().set_input_as_handled()

func is_chat_visible() -> bool:
	return chat_visible

func _on_server_disconnected():
	# Clear all player nodes safely (client only)
	if not OS.has_feature("dedicated_server"):
		for child in spawn_player.get_children():
			if is_instance_valid(child):
				child.queue_free()
		
		# Clear all minimaps
		_clear_all_minimaps()
	
	# Reset game state
	player_states.clear()
	stored_player_data.clear()
	players_pending_removal.clear()
	active_players_count = 0
	
	# Show menu for reconnection (client only)
	if not OS.has_feature("dedicated_server"):
		menu.show()
		active_player_label.hide()
	else:
		print("Server disconnected - headless mode")

func _create_minimap_for_player(player_id: int, player_node: Node3D):
	# Skip in headless mode
	if OS.has_feature("dedicated_server"):
		return
		
	var minimap_scene = load("res://level/scenes/minimap.tscn")
	if not minimap_scene:
		return
	
	var minimap_instance = minimap_scene.instantiate()
	add_child(minimap_instance)
	minimap_instance.name = "Minimap_" + str(player_id)
	
	# Setup minimap with player reference
	if is_instance_valid(player_node):
		minimap_instance.setup_minimap(player_node)

func _destroy_minimap_for_player(player_id: int):
	"""Safely destroy minimap for any player"""
	if OS.has_feature("dedicated_server"):
		return
		
	var minimap_node = get_node_or_null("Minimap_" + str(player_id))
	if minimap_node and is_instance_valid(minimap_node):
		minimap_node.queue_free()
		print("Destroyed minimap for player ", player_id)

func _clear_all_minimaps():
	"""Clear all minimap nodes"""
	if OS.has_feature("dedicated_server"):
		return
		
	for child in get_children():
		if child.name.begins_with("Minimap_") and is_instance_valid(child):
			child.queue_free()

# Manual RPC call for player death (call this from champ.gd when player dies)
@rpc("any_peer", "call_local", "reliable")
func report_player_death(player_id: int):
	if multiplayer.is_server() and player_id not in players_pending_removal:
		on_player_died(player_id)

func on_player_died(player_id: int):
	if player_states.has(player_id) and player_id not in players_pending_removal:
		player_states[player_id]["alive"] = false
		player_states[player_id]["color"] = Color.RED
		
		# Update the actual player's nickname color (client only)
		if not OS.has_feature("dedicated_server"):
			var player_node = spawn_player.get_node_or_null(str(player_id))
			if player_node and player_node.has_node("PlayerNick/Nickname") and is_instance_valid(player_node):
				player_node.get_node("PlayerNick/Nickname").modulate = Color.RED
		
		# Update display
		_update_active_players_display()
		
		# Sync with all clients
		if multiplayer.is_server():
			rpc("sync_player_states", player_states)
			
		# Headless logging
		if OS.has_feature("dedicated_server"):
			print("Player died: ", player_id)

# ============ SERVER MANAGEMENT ============

@rpc("any_peer", "call_local", "reliable")
func request_player_removal(player_id: int):
	"""Server receives request to remove a player"""
	if multiplayer.is_server():
		print("Removing player ", player_id, " from spawn")
		_safe_remove_player(player_id)

func _destroy_local_minimap():
	"""Destroy local player's minimap (client only)"""
	if OS.has_feature("dedicated_server"):
		return
		
	var local_id = multiplayer.get_unique_id()
	var minimap_node = get_node_or_null("Minimap_" + str(local_id))
	if minimap_node and is_instance_valid(minimap_node):
		minimap_node.queue_free()
		print("Destroyed local minimap for player ", local_id)

# ============ HEADLESS SERVER MANAGEMENT ============

func get_server_status() -> Dictionary:
	"""Get current server status for monitoring"""
	return {
		"player_count": active_players_count,
		"max_players": 10,  # Adjust as needed
		"players": player_states,
		"is_headless": OS.has_feature("dedicated_server")
	}

func shutdown_server():
	"""Gracefully shutdown the server"""
	print("Shutting down server...")
	
	# Notify all players
	if multiplayer.is_server():
		rpc("notify_server_shutdown")
	
	# Clean up
	player_states.clear()
	players_pending_removal.clear()
	
	# Close network
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	print("Server shutdown complete")

@rpc("any_peer", "call_local", "reliable")
func notify_server_shutdown():
	"""Notify clients that server is shutting down"""
	print("Server is shutting down...")
	# Clients can handle this notification as needed
