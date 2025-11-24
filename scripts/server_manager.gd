extends Node

@export var server_port: int = 8080
@export var server_name: String = "My Godot Server"
@export var auto_start: bool = true

var network: Network
var game_state: Node

func _ready():
	print("Initializing Headless Server...")
	
	# Check if running in headless mode
	if not OS.has_feature("dedicated_server"):
		print("⚠️  Not running in dedicated server mode")
	
	# Initialize network
	network = Network.new()
	add_child(network)
	network.server_started.connect(_on_server_started)
	network.server_disconnected.connect(_on_server_disconnected)
	network.player_connected.connect(_on_player_connected)
	network.player_disconnected.connect(_on_player_disconnected)
	
	if auto_start:
		start_server()

func start_server(port: int = server_port):
	print("🚀 Starting server on port: ", port)
	var success = network.start_headless_server(server_name, port)
	if success:
		print("✅ Server started successfully")
		_setup_headless_game_state()
	else:
		print("❌ Failed to start server")

func _setup_headless_game_state():
	# Create minimal game state for server
	game_state = Node.new()
	game_state.name = "GameState"
	add_child(game_state)
	
	print("🎮 Headless game state initialized")

func _on_server_started(port: int):
	print("🌟 Server is now listening on port: ", port)
	
	# Log server info
	var server_info = network.get_server_info()
	print("Server Info: ", server_info)

func _on_server_disconnected():
	print("🔴 Server stopped")
	# Cleanup
	if game_state:
		game_state.queue_free()
		game_state = null

func _on_player_connected(peer_id: int, player_info: Dictionary):
	print("👤 Player connected: ", player_info["nick"], " (ID: ", peer_id, ")")
	
	# Handle player connection in headless mode
	# No visual spawn, just game logic

func _on_player_disconnected(peer_id: int):
	print("👤 Player disconnected: ", peer_id)
	
	# Handle player disconnection in headless mode

# Server commands for management
func stop_server():
	print("🛑 Stopping server...")
	if network.multiplayer.multiplayer_peer:
		network.multiplayer.multiplayer_peer.close()

func _input(event):
	# Server management commands
	if event.is_action_pressed("ui_cancel"):  # ESC to stop server
		stop_server()
		get_tree().quit()

func _process(delta):
	# Server heartbeat/logic updates
	pass
