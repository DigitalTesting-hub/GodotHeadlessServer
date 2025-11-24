extends Node

const DEFAULT_PORT: int = 8080
const MAX_PLAYERS: int = 10

var players = {}
var player_info = {
	"nick": "host",
	"character": "player"
}

signal player_connected(peer_id, player_info)
signal server_disconnected
signal server_started(port)

# Server management
var available_ports = [8080, 8081, 8082, 8083, 8084]  # Multiple ports for multiple hosts
var current_port: int = DEFAULT_PORT

func _ready() -> void:
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.connected_to_server.connect(_on_connected_ok)

# Headless server start
func start_headless_server(nickname: String = "Server", port: int = DEFAULT_PORT) -> bool:
	if OS.has_feature("dedicated_server"):
		print("Starting dedicated server on port: ", port)
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error:
		print("❌ Failed to create server: ", error)
		return false
	
	multiplayer.multiplayer_peer = peer
	current_port = port
	
	player_info["nick"] = nickname
	player_info["character"] = "server"
	players[1] = player_info.duplicate()
	
	print("✅ Dedicated server started on port: ", port)
	server_started.emit(port)
	return true

# Regular host (for client-hosted games)
func start_host(nickname: String, character: String, port: int = DEFAULT_PORT):
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error:
		return error
	
	multiplayer.multiplayer_peer = peer
	current_port = port

	if !nickname or nickname.strip_edges() == "":
		nickname = "Host_" + str(1)

	player_info["nick"] = nickname
	player_info["character"] = character
	players[1] = player_info.duplicate()
	player_connected.emit(1, player_info)

func join_game(nickname: String, character: String, address: String = "127.0.0.1", port: int = DEFAULT_PORT):
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error:
		return error

	multiplayer.multiplayer_peer = peer

	if !nickname or nickname.strip_edges() == "":
		nickname = "Player_" + str(multiplayer.get_unique_id())

	player_info["nick"] = nickname
	player_info["character"] = character

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info.duplicate()
	player_connected.emit(peer_id, player_info)

func _on_player_connected(id):
	_register_player.rpc_id(id, player_info)

@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)

func _on_player_disconnected(id):
	players.erase(id)
	print("Player disconnected: ", id)

func _on_connection_failed():
	multiplayer.multiplayer_peer = null
	print("Connection failed")

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	players.clear()
	print("Server disconnected")
	server_disconnected.emit()

func get_server_info() -> Dictionary:
	return {
		"port": current_port,
		"player_count": players.size(),
		"max_players": MAX_PLAYERS
	}
