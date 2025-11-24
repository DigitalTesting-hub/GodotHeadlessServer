extends CharacterBody3D

const NORMAL_SPEED = 2.0
const SPRINT_SPEED = 4.0
const CROUCH_SPEED = 1.0
const PRONE_SPEED = 0.67
const JUMP_VELOCITY = 4
const PLAYER_DAMAGE = 20
const MAX_HEALTH = 300

@export var current_weapon: WeaponType = WeaponType.GUN
@export var sync_weapon_visibility: bool = false
@export var armature_node: Node3D = null
var last_synced_animation: String = ""
@export var friendly_fire_enabled: bool = true
@onready var nickname: Label3D = $PlayerNick/Nickname
@export var sync_velocity: Vector3 = Vector3.ZERO
@onready var camera: Camera3D = $SpringArmOffset/SpringArm3D/Camera3D

# Collision shape sync via MPSynchronizer
@export var normal_collision_disabled: bool = false
@export var crouch_collision_disabled: bool = true
@export var prone_collision_disabled: bool = true

@export var sync_visible: bool = true 

@export_category("Objects")
@export var _body: Node3D = null
@export var _spring_arm_offset: Node3D = null

@export_category("Collision Shapes")
@export var normal_collision: CollisionShape3D = null
@export var crouch_collision: CollisionShape3D = null
@export var prone_collision: CollisionShape3D = null

@export_category("Weapon Nodes - Demo Paths")
@export var gun_node: Node3D = null
@export var melee_node: Node3D = null

# Audio nodes (headless servers don't need these)
@onready var walk_sound: AudioStreamPlayer3D = $WalkSound
@onready var run_sound: AudioStreamPlayer3D = $RunSound
@onready var jump_sound: AudioStreamPlayer3D = $JumpSound
@onready var gun_fire_sound: AudioStreamPlayer3D = $GunFireSound
@onready var melee_sound: AudioStreamPlayer3D = $MeleeSound 

# Combat nodes
@onready var raycast: RayCast3D = $SpringArmOffset/SpringArm3D/Camera3D/RayCast3D
@onready var health_label: Label = $HealthLabel
@onready var detection_area: Area3D = $DetectionArea
@onready var melee_hitbox: Area3D = $Champ/Armature/Skeleton3D/Hand/MeleeAttack

# MPSync Audio State
@export var footstep_counter: int = 0
@export var footstep_type: String = "walk"
@export var jump_counter: int = 0
@export var is_firing_sync: bool = false
@export var melee_counter: int = 0
@export var sync_is_melee_attacking: bool = false
@export var sync_is_dead: bool = false
@export var sync_stance: String = "normal"
@export var gun_fire_counter: int = 0  
@export var melee_sound_counter: int = 0 

# Local audio tracking
var last_footstep_counter: int = 0
var last_jump_counter: int = 0
var last_melee_counter: int = 0
var last_gun_fire_counter: int = 0 
var last_melee_sound_counter: int = 0  

# Remote player sound control
var last_sync_velocity: Vector3 = Vector3.ZERO
var velocity_stopped_frames: int = 0
var required_stopped_frames: int = 2
var last_damage_source: int = -1
var last_damage_weapon: String = ""

# Audio settings
var footstep_timer: float = 0.0
var walk_footstep_interval: float = 0.5
var run_footstep_interval: float = 0.3

# Stuck detection settings
@export_category("Stuck Detection")
@export var stuck_check_interval: float = 1.0
@export var stuck_trigger_duration: float = 2.0
@export var stuck_distance_threshold: float = 0.1

# Combat settings
@export_category("Combat Settings")
@export var fire_rate: float = 0.2
@export var red_particle_size: float = 0.02
@export var red_particle_count: int = 8
@export var black_dot_size: float = 0.04

@export_category("Melee Settings")
@export var melee_damage: int = 25
@export var melee_cooldown: float = 1.0

# State variables
var mouse_locked = true
var _current_speed: float
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Stuck detection variables
var last_position: Vector3 = Vector3.ZERO
var stuck_timer: float = 0.0
var stuck_duration: float = 0.0
var is_currently_stuck: bool = false

# Stance and movement state
var current_stance: String = "normal"
var is_running_mode: bool = false
var is_spectator: bool = false

# Collision stance tracking
var last_sync_stance: String = "normal"

# Auto-save for solo mode
var auto_save_timer: float = 0.0
var auto_save_interval: float = 30.0

# Combat state
var current_health: int = MAX_HEALTH
var can_shoot: bool = true
var is_firing_held: bool = false
var is_aiming: bool = false
var can_melee: bool = true
var is_melee_attacking: bool = false
var look_target: Vector3 = Vector3.ZERO
var has_look_target: bool = false

# Weapon system
enum WeaponType { GUN, MELEE }
var can_switch_weapon: bool = true

# Lobby modes
var god_mode: bool = false
var is_victory_dancing: bool = false

# ============ VEHICLE VARIABLES - SEPARATED ============
@export var is_in_vehicle: bool = false  # Shared for both driver and passenger
@export var is_driver: bool = false       # True only when driving
@export var is_passenger: bool = false    # True only when passenger
var nearby_car: Node3D = null              # For driver entry area
var nearby_passenger_car: Node3D = null    # For passenger entry area
var current_passenger_car: Node3D = null   # Store reference when seated as passenger

# Headless server flag
var is_headless_server: bool = false

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())
	
	# Check for headless server
	is_headless_server = OS.has_feature("dedicated_server")
	
	if has_node("SpringArmOffset/SpringArm3D/Camera3D"):
		if not is_spectator and not is_headless_server:
			$SpringArmOffset/SpringArm3D/Camera3D.current = is_multiplayer_authority()

func _ready():
	add_to_group("player")
	
	if is_headless_server:
		_setup_headless_mode()
		return
	
	_setup_audio_nodes()
	_validate_collision_shapes()
	_setup_collision()
	_setup_raycast()
	_setup_detection_area()
					
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_setup_input_actions()
		last_position = global_position
		_update_health_ui()
		_update_weapon_visibility()
		
		if melee_hitbox:
			_setup_melee_hitbox() 
			melee_hitbox.monitoring = false
			melee_hitbox.body_entered.connect(_on_melee_hitbox_body_entered)
	else:
		_setup_3d_audio_for_others()
		last_footstep_counter = footstep_counter
		last_jump_counter = jump_counter
		last_melee_counter = melee_counter
		last_sync_stance = sync_stance
	
	_update_weapon_visibility()
	_apply_collision_shape(current_stance)

func _setup_headless_mode():
	"""Setup for headless server - minimal components only"""
	print("🤖 Headless champ setup for player: ", name)
	
	# Only setup essential components
	_setup_collision()
	_setup_raycast()
	_setup_detection_area()
	
	if melee_hitbox:
		_setup_melee_hitbox()
		melee_hitbox.monitoring = false
		melee_hitbox.body_entered.connect(_on_melee_hitbox_body_entered)
	
	# Skip all visual/audio setup
	_apply_collision_shape(current_stance)

func _validate_collision_shapes():
	if not normal_collision:
		push_error("ERROR: Normal collision shape not assigned!")
	if not crouch_collision:
		push_error("ERROR: Crouch collision shape not assigned!")
	if not prone_collision:
		push_error("ERROR: Prone collision shape not assigned!")
	
	if normal_collision and crouch_collision and prone_collision:
		print("✓ All collision shapes validated for player: ", name)

func _setup_melee_hitbox():
	if not melee_hitbox:
		return
	
	melee_hitbox.collision_layer = 0
	melee_hitbox.set_collision_layer_value(9, true)
	melee_hitbox.collision_mask = 0
	melee_hitbox.set_collision_mask_value(3, true)
	melee_hitbox.set_collision_mask_value(4, true)
	melee_hitbox.set_collision_mask_value(6, true)
	
	if not is_headless_server:
		print("Player melee hitbox: Layer 9, Mask 3,4,6")

func _setup_collision():
	collision_layer = 0
	set_collision_layer_value(3, true)
	collision_mask = 0
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(3, true)
	set_collision_mask_value(4, true)
	
	if not is_headless_server:
		print("Player collision: Layer 3, Mask 1,2,3,4")

func _setup_detection_area():
	if not detection_area:
		detection_area = Area3D.new()
		detection_area.name = "DetectionArea"
		add_child(detection_area)
		
		var collision_shape = CollisionShape3D.new()
		var sphere = SphereShape3D.new()
		sphere.radius = 1.0
		collision_shape.shape = sphere
		detection_area.add_child(collision_shape)
		
		if not is_headless_server:
			print("Created DetectionArea for player")
	
	detection_area.collision_layer = 0
	detection_area.set_collision_layer_value(5, true)
	detection_area.collision_mask = 0

func _setup_raycast():
	if raycast:
		raycast.enabled = true
		raycast.target_position = Vector3(0, 0, -100)
		raycast.collision_mask = 0
		raycast.set_collision_mask_value(4, true)
		raycast.set_collision_mask_value(6, true)
		raycast.set_collision_mask_value(3, true)
		raycast.set_collision_mask_value(2, true)
		
		if not is_headless_server:
			print("Player raycast: Mask 2,3,4,6")

func _setup_input_actions():
	# Skip input setup for headless servers
	if is_headless_server:
		return
		
	_add_key_input("move_forward", KEY_W)
	_add_key_input("move_backward", KEY_S)
	_add_key_input("move_left", KEY_A)
	_add_key_input("move_right", KEY_D)
	_add_key_input("jump", KEY_SPACE)
	_add_key_input("toggle_mouse", KEY_M)
	_add_key_input("toggle_run", KEY_SHIFT)
	_add_key_input("fire", KEY_F)
	_add_key_input("melee_attack", KEY_E)
	_add_key_input("crouch", KEY_C)
	_add_key_input("prone", KEY_X)
	_add_key_input("cycle_weapon", KEY_Q)
	_add_key_input("aim", KEY_V)
	_add_key_input("aim_alt", KEY_G)
	_add_key_input("enter_vehicle", KEY_P)
	
func _add_key_input(action: String, keycode: int):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	
	InputMap.action_erase_events(action)
	var event = InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action, event)
	
	if action == "fire":
		var mouse_event = InputEventMouseButton.new()
		mouse_event.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(action, mouse_event)
	elif action == "aim" or action == "aim_alt":
		var mouse_event = InputEventMouseButton.new()
		mouse_event.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action, mouse_event)

func _setup_audio_nodes():
	# Skip audio setup for headless servers
	if is_headless_server:
		return
		
	if not has_node("WalkSound"):
		walk_sound = AudioStreamPlayer3D.new()
		walk_sound.name = "WalkSound"
		walk_sound.bus = "SFX"
		walk_sound.max_distance = 8.0
		walk_sound.unit_size = 3.0
		add_child(walk_sound)
		
		var walk_stream = load("res://assets/audio/sfx/walk.wav")
		if walk_stream:
			walk_sound.stream = walk_stream
			
	if not has_node("GunFireSound"):
		gun_fire_sound = AudioStreamPlayer3D.new()
		gun_fire_sound.name = "GunFireSound"
		gun_fire_sound.bus = "SFX"
		gun_fire_sound.max_distance = 50.0
		gun_fire_sound.unit_size = 4.0
		add_child(gun_fire_sound)
		
		var gun_fire_stream = load("res://Audios/Gun.WAV")
		if gun_fire_stream:
			gun_fire_sound.stream = gun_fire_stream
	
	if not has_node("MeleeSound"):
		melee_sound = AudioStreamPlayer3D.new()
		melee_sound.name = "MeleeSound"
		melee_sound.bus = "SFX"
		melee_sound.max_distance = 8.0
		melee_sound.unit_size = 3.0
		add_child(melee_sound)
		
		var melee_stream = load("res://Audios/Melee.WAV")
		if melee_stream:
			melee_sound.stream = melee_stream
			
	if not has_node("RunSound"):
		run_sound = AudioStreamPlayer3D.new()
		run_sound.name = "RunSound"
		run_sound.bus = "SFX"
		run_sound.max_distance = 10.0
		run_sound.unit_size = 3.0
		add_child(run_sound)
		
		var run_stream = load("res://assets/audio/sfx/run.wav")
		if run_stream:
			run_sound.stream = run_stream
	
	if not has_node("JumpSound"):
		jump_sound = AudioStreamPlayer3D.new()
		jump_sound.name = "JumpSound"
		jump_sound.bus = "SFX"
		jump_sound.max_distance = 10.0
		jump_sound.unit_size = 2.0
		add_child(jump_sound)
		
		var jump_stream = load("res://assets/audio/sfx/jump.wav")
		if jump_stream:
			jump_sound.stream = jump_stream

func _setup_3d_audio_for_others():
	# Skip audio setup for headless servers
	if is_headless_server:
		return
		
	if walk_sound:
		walk_sound.max_distance = 8.0
	if run_sound:
		run_sound.max_distance = 10.0
	if jump_sound:
		jump_sound.max_distance = 5.0
	if gun_fire_sound:
		gun_fire_sound.max_distance = 50.0
	if melee_sound:
		melee_sound.max_distance = 8.0

# ============ COLLISION SHAPE MANAGEMENT ============

func _apply_collision_shape(stance: String):
	if not normal_collision or not crouch_collision or not prone_collision:
		push_error("Collision shapes not properly assigned!")
		return
	
	match stance:
		"normal":
			normal_collision_disabled = false
			crouch_collision_disabled = true
			prone_collision_disabled = true
		"crouch":
			normal_collision_disabled = true
			crouch_collision_disabled = false
			prone_collision_disabled = true
		"prone":
			normal_collision_disabled = true
			crouch_collision_disabled = true
			prone_collision_disabled = false
		_:
			normal_collision_disabled = false
			crouch_collision_disabled = true
			prone_collision_disabled = true
	
	normal_collision.disabled = normal_collision_disabled
	crouch_collision.disabled = crouch_collision_disabled
	prone_collision.disabled = prone_collision_disabled

func _sync_collision_from_exports():
	if not normal_collision or not crouch_collision or not prone_collision:
		return
	
	normal_collision.disabled = normal_collision_disabled
	crouch_collision.disabled = crouch_collision_disabled
	prone_collision.disabled = prone_collision_disabled

func _sync_collision_shapes():
	if not is_multiplayer_authority():
		_sync_collision_from_exports()
		
		if sync_stance != last_sync_stance and not is_headless_server:
			last_sync_stance = sync_stance
			print("Remote player ", name, " collision synced to: ", sync_stance)

# ============ INPUT HANDLING ============
func _input(event):
	# Skip all input for headless servers
	if is_headless_server:
		return
		
	if event.is_action_pressed("return_to_lobby"):  # Define this in input map
		return_to_lobby()
	if event.is_action_pressed("enter_vehicle") and is_passenger:
		print("Exit Pressed")
		_exit_as_passenger()
	# Skip all input if driver (car handles input)
	if is_driver:
		return
	
	# Passenger can look around but not move/shoot
	if is_passenger:
		if event is InputEventKey and event.keycode == KEY_M and event.pressed:
			mouse_locked = !mouse_locked
			if mouse_locked:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
		
	if not is_multiplayer_authority() or is_spectator:
		if event.is_action_pressed("toggle_chat"):
			pass
		elif event.is_action_pressed("cycle_weapon"):
			_switch_spectator_camera()
		elif event is InputEventKey and event.keycode == KEY_M and event.pressed:
			mouse_locked = !mouse_locked
			if mouse_locked:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			return
		return
			
	if event is InputEventKey and event.keycode == KEY_M and event.pressed:
		mouse_locked = !mouse_locked
		if mouse_locked:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			
	if event.is_action_pressed("aim") or event.is_action_pressed("aim_alt"):
		if current_weapon == WeaponType.GUN:
			is_aiming = true
	if event.is_action_released("aim") or event.is_action_released("aim_alt"):
		is_aiming = false
	
	if event.is_action_pressed("toggle_run"):
		_toggle_run()
	
	if event.is_action_pressed("crouch"):
		_toggle_crouch()
	
	if event.is_action_pressed("prone"):
		_toggle_prone()
	
	if event.is_action_pressed("cycle_weapon"):
		_cycle_weapon()
	
	if event.is_action_pressed("fire") and mouse_locked:
		if current_weapon == WeaponType.GUN:
			is_firing_held = true
			is_firing_sync = true
		elif current_weapon == WeaponType.MELEE:
			_melee_attack()
	
	if event.is_action_released("fire"):
		is_firing_held = false
		is_firing_sync = false
	
	if event.is_action_pressed("aim") or event.is_action_pressed("aim_alt"):
		is_aiming = true
	if event.is_action_released("aim") or event.is_action_released("aim_alt"):
		is_aiming = false
	
	if event.is_action_pressed("melee_attack") and mouse_locked:
		if current_weapon == WeaponType.MELEE:
			_melee_attack()
	
	# ============ VEHICLE ENTRY - DRIVER ============
	if event.is_action_pressed("enter_vehicle"):
		if nearby_car and not nearby_car.is_driver_occupied and not nearby_car.is_processing_entry:
			print("Player entering as DRIVER")
			nearby_car.start_entry_sequence(self)
			# Set driver flags immediately
			is_in_vehicle = true
			is_driver = true
			set_process_input(false)
			set_physics_process(false)
			can_shoot = false
			can_melee = false
			can_switch_weapon = false
			if gun_node:
				gun_node.visible = false
			if melee_node:
				melee_node.visible = false
			if camera:
				camera.current = false
			return
		
		# ============ VEHICLE ENTRY - PASSENGER ============
		if nearby_passenger_car and not nearby_passenger_car.is_passenger_occupied and not nearby_passenger_car.is_processing_passenger_entry:
			print("Player entering as PASSENGER")
			current_passenger_car = nearby_passenger_car
			nearby_passenger_car.start_passenger_entry_sequence(self)
			# Set passenger flags immediately
			is_in_vehicle = true
			is_passenger = true
			set_physics_process(false)
			can_shoot = false
			can_melee = false
			can_switch_weapon = false
			if gun_node:
				gun_node.visible = false
			if melee_node:
				melee_node.visible = false
			# Keep camera active for looking around
			return

# ============ PASSENGER EXIT FUNCTION ============

func _exit_as_passenger():
	if not is_passenger or not current_passenger_car:
		return
	
	print("=== PASSENGER EXITING ===")
	
	var car = current_passenger_car 
	
	# Step 1: Teleport to passenger enter area
	if car.passenger_enter_area:
		global_position = car.passenger_enter_area.global_position
		print("Passenger teleported to exit position")
	
	# Step 2: Restore rotation from saved transform
	if car.passenger_original_transform:
		var original_rotation = car.passenger_original_transform.basis.get_euler()
		global_rotation = original_rotation
		if _body:
			_body.rotation = Vector3.ZERO
		print("Passenger rotation restored")
	
	# Step 3: Re-enable player controls
	set_physics_process(true)
	can_shoot = true
	can_melee = true
	can_switch_weapon = true
	
	# Step 4: Restore weapon visibility
	_update_weapon_visibility()
	
	# Step 5: Re-enable collision
	_setup_collision()
	
	# Step 6: Reset animation
	if _body:
		_body.is_in_car = false
		if _body.animation_player:
			_body.animation_player.stop()
			if _body.animation_player.has_animation("RifleIdle"):
				_body.animation_player.play("RifleIdle")
	
	# Step 7: Reset stance
	current_stance = "normal"
	_apply_collision_shape(current_stance)
	
	# Step 8: Clear flags
	is_in_vehicle = false
	is_passenger = false
	
	# Step 9: Tell car to clear passenger seat
	car.clear_passenger_seat()
	current_passenger_car = null
	# Step 10: Ensure mouse is captured
	if is_multiplayer_authority():
		mouse_locked = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	print("=== PASSENGER EXIT COMPLETE ===")

func _manual_unstuck():
	if not is_multiplayer_authority() or is_spectator:
		return
	print("Manual unstuck triggered")
	velocity.y = 3.0
	position.y += 1.0
	stuck_duration = 0.0
	is_currently_stuck = false
	last_position = global_position

func _check_stuck(delta):
	if is_spectator:
		return
		
	var input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var is_trying_to_move = input_vector.length() > 0.1
	
	stuck_timer += delta
	
	if stuck_timer >= stuck_check_interval:
		var distance_moved = global_position.distance_to(last_position)
		var is_moving = distance_moved > stuck_distance_threshold
				
		if is_trying_to_move and not is_moving:
			stuck_duration += stuck_check_interval
			is_currently_stuck = true
			
			if stuck_duration >= stuck_trigger_duration:
				_manual_unstuck()
		else:
			stuck_duration = 0.0
			is_currently_stuck = false
		
		stuck_timer = 0.0
		last_position = global_position

func _physics_process(delta):
	# Skip physics for headless server players (they don't move)
	if is_headless_server:
		return
		
	if is_spectator:
		return
	if is_driver:
		return
	if is_passenger:
		return
	if sync_is_dead:
		if not is_multiplayer_authority():
			queue_free()
			return
		return
	
	if is_multiplayer_authority():
		_apply_collision_shape(current_stance)
	else:
		_sync_collision_from_exports()
	
	var allow_controls = is_multiplayer_authority()
	
	if not allow_controls:
		return
	
	if current_weapon == WeaponType.MELEE and is_aiming:
		is_aiming = false
		
	var current_scene = get_tree().get_current_scene()
	if current_scene and current_scene.has_method("is_chat_visible") and current_scene.is_chat_visible() and is_on_floor():
		freeze()
		_stop_footstep_sounds()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if is_on_floor() and current_stance == "normal":
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			jump_counter += 1
			_play_jump_sound()

	sync_velocity = velocity
	sync_stance = current_stance
	
	_check_stuck(delta)
	
	if (is_firing_held or is_aiming) and current_weapon == WeaponType.GUN:
		_update_look_target()
	else:
		has_look_target = false
	
	if is_firing_held and can_shoot and mouse_locked and current_weapon == WeaponType.GUN:
		_fire()
	
	_move()
	move_and_slide()
	
	if _body:
		var firing_state = false
		if current_weapon == WeaponType.GUN:
			firing_state = is_firing_held if is_multiplayer_authority() else is_firing_sync
		
		var should_look_at = has_look_target and (firing_state or is_aiming) and current_weapon == WeaponType.GUN
		_body.animate(velocity, current_stance, firing_state, is_aiming, look_target if should_look_at else Vector3.ZERO)
	
	_update_footstep_audio(delta)

func _update_look_target():
	if not raycast:
		has_look_target = false
		return
	
	raycast.force_raycast_update()
	
	if raycast.is_colliding():
		look_target = raycast.get_collision_point()
		has_look_target = true
	else:
		var forward = -camera.global_transform.basis.z
		look_target = camera.global_position + forward * 100.0
		has_look_target = true

func _update_footstep_audio(delta):
	# Skip audio for headless servers
	if is_headless_server:
		return
		
	if is_spectator:
		return
	
	if current_stance == "crouch" or current_stance == "prone":
		_stop_footstep_sounds()
		footstep_timer = 0.0
		return
	
	var is_moving = velocity.length() > 0.1 and is_on_floor()
	
	if is_moving:
		footstep_timer += delta
		var current_interval = run_footstep_interval if is_running_mode else walk_footstep_interval
		
		if footstep_timer >= current_interval:
			footstep_type = "run" if is_running_mode else "walk"
			footstep_counter += 1
			_play_footstep_sound(footstep_type)
			footstep_timer = 0.0
	else:
		_stop_footstep_sounds()
		footstep_timer = 0.0

func _check_remote_audio():
	# Skip audio for headless servers
	if is_headless_server:
		return
		
	if footstep_counter != last_footstep_counter:
		_play_footstep_sound(footstep_type)
		last_footstep_counter = footstep_counter
	
	if jump_counter != last_jump_counter:
		_play_jump_sound()
		last_jump_counter = jump_counter
	
	if melee_counter != last_melee_counter:
		if _body and _body.has_method("play_melee_animation"):
			_body.play_melee_animation()
		last_melee_counter = melee_counter
		
	if gun_fire_counter != last_gun_fire_counter:
		_play_gun_fire_sound()
		last_gun_fire_counter = gun_fire_counter
	
	if melee_sound_counter != last_melee_sound_counter:
		_play_melee_sound()
		last_melee_sound_counter = melee_sound_counter

func _play_footstep_sound(step_type: String):
	_stop_footstep_sounds()
	match step_type:
		"walk":
			if walk_sound and walk_sound.stream:
				walk_sound.play()
		"run":
			if run_sound and run_sound.stream:
				run_sound.play()
				
func _play_gun_fire_sound():
	if gun_fire_sound and gun_fire_sound.stream:
		gun_fire_sound.play()

func _play_melee_sound():
	if melee_sound and melee_sound.stream:
		melee_sound.play()
		
func _play_jump_sound():
	if jump_sound and jump_sound.stream:
		if not jump_sound.playing:
			jump_sound.play()

func _stop_footstep_sounds():
	if walk_sound and walk_sound.playing:
		walk_sound.stop()
	if run_sound and run_sound.playing:
		run_sound.stop()

func _process(_delta):
	# Skip processing for headless server players
	if is_headless_server:
		return
		
	if is_spectator and is_multiplayer_authority():
		return
		
	if sync_is_dead:
		if not is_multiplayer_authority():
			queue_free()
		return
	
	if not is_multiplayer_authority():
		_sync_collision_from_exports()
		_check_remote_audio()
		_check_remote_audio_stop()
		_sync_visibility_from_export()
		_check_remote_melee()

func _check_remote_melee():
	if melee_counter != last_melee_counter:
		if _body and _body.has_method("play_melee_animation"):
			_body.play_melee_animation()
		last_melee_counter = melee_counter
		
func _check_remote_audio_stop():
	if is_multiplayer_authority():
		return
	
	var is_stopped_now = sync_velocity.length() < 0.1
	
	if is_stopped_now:
		velocity_stopped_frames += 1
	else:
		velocity_stopped_frames = 0
		last_sync_velocity = sync_velocity
	
	if velocity_stopped_frames >= required_stopped_frames:
		_stop_remote_footstep_sounds()
		velocity_stopped_frames = required_stopped_frames

func _stop_remote_footstep_sounds():
	if walk_sound and walk_sound.playing:
		walk_sound.stop()
	if run_sound and run_sound.playing:
		run_sound.stop()

func freeze():
	velocity.x = 0
	velocity.z = 0
	_current_speed = 0
	if _body:
		_body.animate(Vector3.ZERO, current_stance, false, false, Vector3.ZERO)
	_stop_footstep_sounds()
	
	if is_spectator:
		velocity.y = 0

func _move() -> void:
	if is_spectator:
		return
	
	var _input_direction: Vector2 = Vector2.ZERO
	if is_multiplayer_authority():
		_input_direction = Input.get_vector(
			"move_left", "move_right",
			"move_forward", "move_backward"
		)

	if current_stance == "prone" and is_firing_held:
		_input_direction = Vector2.ZERO

	var _direction: Vector3 = transform.basis * Vector3(_input_direction.x, 0, _input_direction.y).normalized()

	_update_speed()
	_direction = _direction.rotated(Vector3.UP, _spring_arm_offset.rotation.y)

	if _direction:
		velocity.x = _direction.x * _current_speed
		velocity.z = _direction.z * _current_speed
		if _body:
			_body.apply_rotation(velocity)
		return

	velocity.x = move_toward(velocity.x, 0, _current_speed)
	velocity.z = move_toward(velocity.z, 0, _current_speed)

func _update_speed():
	match current_stance:
		"crouch":
			_current_speed = CROUCH_SPEED
		"prone":
			_current_speed = PRONE_SPEED
		_:
			if is_running_mode:
				_current_speed = SPRINT_SPEED
			else:
				_current_speed = NORMAL_SPEED

func is_running() -> bool:
	return is_running_mode
	
func _toggle_run():
	if is_spectator or current_stance == "crouch":
		return
	if current_stance == "prone":
		return
	is_running_mode = !is_running_mode

func _toggle_crouch():
	if is_spectator:
		return
	
	if not is_headless_server:
		print("Previous stance: ", current_stance)
	
	if current_stance == "crouch":
		current_stance = "normal"
		is_running_mode = false
	elif current_stance == "normal":
		current_stance = "crouch"
		is_running_mode = false
	elif current_stance == "prone":
		current_stance = "crouch"
		is_running_mode = false
	
	_apply_collision_shape(current_stance)

func _toggle_prone():
	if is_spectator:
		return
	
	if not is_headless_server:
		print("Previous stance: ", current_stance)
	
	if current_stance == "prone":
		current_stance = "normal"
	elif current_stance == "normal":
		current_stance = "prone"
		is_running_mode = false
	elif current_stance == "crouch":
		current_stance = "prone"
		is_running_mode = false
	
	_apply_collision_shape(current_stance)

func _cycle_weapon():
	if is_spectator or not can_switch_weapon:
		return
	
	match current_weapon:
		WeaponType.GUN:
			current_weapon = WeaponType.MELEE
		WeaponType.MELEE:
			current_weapon = WeaponType.GUN
	
	if is_multiplayer_authority():
		rpc("sync_weapon_change", current_weapon)
		
	_update_weapon_visibility()
	
	if not is_headless_server:
		print("Switched to weapon: ", current_weapon)

func _update_weapon_visibility():
	# Skip weapon visibility for headless servers
	if is_headless_server:
		return
		
	if gun_node:
		gun_node.visible = (current_weapon == WeaponType.GUN) and not is_spectator
	if melee_node:
		melee_node.visible = (current_weapon == WeaponType.MELEE) and not is_spectator
	sync_weapon_visibility = !sync_weapon_visibility
	
@rpc("any_peer", "call_local", "reliable")
func sync_weapon_change(weapon_index: int):
	current_weapon = weapon_index
	_update_weapon_visibility()

# ============ SPECTATOR METHODS ============

func set_spectator(value: bool):
	is_spectator = value
	if is_spectator:
		if gun_node:
			gun_node.visible = false
		if melee_node:
			melee_node.visible = false
		
		collision_layer = 0
		collision_mask = 0
		
		if detection_area:
			detection_area.monitoring = false
		
		freeze()
		_stop_footstep_sounds()
		
		if raycast:
			raycast.enabled = false
		
		if not is_headless_server:
			print("Player is now spectator")
	else:
		_update_weapon_visibility()
		_setup_collision()
		
		if detection_area:
			detection_area.monitoring = true
		
		if raycast:
			raycast.enabled = true
		
		if has_node("SpringArmOffset/SpringArm3D/Camera3D"):
			$SpringArmOffset/SpringArm3D/Camera3D.current = is_multiplayer_authority()
		
		if not is_headless_server:
			print("Player is no longer spectator")

func _switch_spectator_camera():
	if not is_spectator or not is_multiplayer_authority():
		return
	
	var lobby = get_tree().get_current_scene()
	if lobby and lobby.has_method("switch_spectator_camera"):
		lobby.switch_spectator_camera.rpc_id(1, int(name))
		print("Requesting camera switch for spectator")

@rpc("any_peer", "call_local", "reliable")
func _spectator_camera_changed(player_nick: String):
	if is_spectator and is_multiplayer_authority():
		print("Now spectating: ", player_nick)

# ============ COMBAT FUNCTIONS ============

func _fire():
	if is_spectator or current_weapon != WeaponType.GUN:
		return
	
	can_shoot = false
	
	if not is_headless_server:
		_play_gun_fire_sound()
	gun_fire_counter += 1
	
	if raycast and raycast.is_colliding():
		var collider = raycast.get_collider()
		var hit_point = raycast.get_collision_point()
		var hit_normal = raycast.get_collision_normal()
		
		if collider and collider.is_in_group("player"):
			if collider != self and friendly_fire_enabled:
				if collider.has_method("take_damage"):
					collider.take_damage(PLAYER_DAMAGE, int(name), "gun")
					if not is_headless_server:
						_spawn_impact_effect(hit_point, hit_normal, true)
		elif collider and collider.is_in_group("zombie"):
			if collider.has_method("take_damage"):
				collider.take_damage(PLAYER_DAMAGE)
				if not is_headless_server:
					_spawn_impact_effect(hit_point, hit_normal, true)
		elif collider and collider.is_in_group("ranged"):
			if collider.has_method("take_damage"):
				collider.take_damage(PLAYER_DAMAGE)
				if not is_headless_server:
					_spawn_impact_effect(hit_point, hit_normal, true)
		elif collider and collider.has_method("take_damage"):
			collider.take_damage(PLAYER_DAMAGE)
			if not is_headless_server:
				_spawn_impact_effect(hit_point, hit_normal, true)
		else:
			if not is_headless_server:
				_spawn_impact_effect(hit_point, hit_normal, false)
	
	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true

func _spawn_impact_effect(position: Vector3, normal: Vector3, is_enemy: bool):
	# Skip visual effects for headless servers
	if is_headless_server:
		return
		
	var effect = Node3D.new()
	get_tree().root.add_child(effect)
	effect.global_position = position
	effect.look_at(position + normal, Vector3.UP)
	
	if is_enemy:
		_create_red_scatter(effect)
	else:
		_create_black_dot(effect)
	
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(effect):
		effect.queue_free()

func _create_red_scatter(parent: Node3D):
	var damage_label = Label.new()
	damage_label.text = str(PLAYER_DAMAGE)
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	damage_label.add_theme_font_size_override("font_size", 26)
	damage_label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0, 1.0))
	damage_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.0))
	damage_label.add_theme_constant_override("outline_size", 5)
	
	var canvas_layer = CanvasLayer.new()
	get_tree().root.add_child(canvas_layer)
	canvas_layer.add_child(damage_label)
	
	damage_label.position = get_viewport().get_visible_rect().size * 0.5 - damage_label.size * 0.5
	
	var label_tween = create_tween()
	label_tween.set_parallel(true)
	label_tween.tween_property(damage_label, "position:y", damage_label.position.y - 50, 0.5)
	label_tween.tween_property(damage_label, "modulate:a", 0.0, 0.5)
	label_tween.tween_callback(canvas_layer.queue_free).set_delay(0.5)
	
	for i in range(red_particle_count):
		var particle = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = red_particle_size
		sphere.height = red_particle_size * 2
		particle.mesh = sphere
		
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.8, 0.1, 0.1, 1.0)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.0, 0.0, 1.0)
		material.emission_energy = 2.0
		particle.material_override = material
		
		parent.add_child(particle)
		
		var random_dir = Vector3(
			randf_range(-1, 1),
			randf_range(-0.5, 1),
			randf_range(-1, 1)
		).normalized()
		
		particle.position = random_dir * randf_range(0.05, 0.15)
		
		var tween = create_tween()
		tween.set_parallel(true)
		var end_pos = particle.position + random_dir * 0.3
		tween.tween_property(particle, "position", end_pos, 0.5)
		tween.tween_property(particle, "scale", Vector3.ZERO, 0.5)

func _create_black_dot(parent: Node3D):
	var dot = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = black_dot_size
	sphere.height = black_dot_size * 0.3
	dot.mesh = sphere
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.1, 0.1, 1.0)
	dot.material_override = material
	
	parent.add_child(dot)
	dot.position = Vector3(0, 0.01, 0)

func _melee_attack():
	if is_spectator or not can_melee or is_melee_attacking or not mouse_locked:
		return
	
	if current_weapon != WeaponType.MELEE:
		return
	
	can_melee = false
	is_melee_attacking = true
	sync_is_melee_attacking = true
	melee_counter += 1
	
	if not is_headless_server:
		_play_melee_sound()
	melee_sound_counter += 1
	
	if not is_headless_server:
		print("🗡️ Player melee attack!")
	
	if _body and _body.has_method("play_melee_animation"):
		_body.play_melee_animation()
	
	await get_tree().create_timer(0.2).timeout
	
	if is_instance_valid(self) and melee_hitbox:
		melee_hitbox.monitoring = true
		if not is_headless_server:
			print("Melee hitbox active")
	
	await get_tree().create_timer(0.5).timeout
	
	if is_instance_valid(self) and melee_hitbox:
		melee_hitbox.monitoring = false
		if not is_headless_server:
			print("Melee hitbox disabled")
	
	await get_tree().create_timer(0.5).timeout
	
	if is_instance_valid(self):
		is_melee_attacking = false
		can_melee = true
		sync_is_melee_attacking = false
		if not is_headless_server:
			print("Melee ready again!")

func _on_melee_hitbox_body_entered(body: Node):
	if not is_melee_attacking:
		return
	
	if not is_headless_server:
		print("Melee hit: ", body.name)
	
	if body.is_in_group("player"):
		if body != self and friendly_fire_enabled:
			if body.has_method("take_damage"):
				body.take_damage(melee_damage, int(name), "melee")
				if not is_headless_server:
					print("✓ Melee hit player ", body.name, " for ", melee_damage, " damage!")
				melee_hitbox.set_deferred("monitoring", false)
		return
	
	if body.is_in_group("zombie") or body.is_in_group("ranged"):
		if body.has_method("take_damage"):
			body.take_damage(melee_damage)
			if not is_headless_server:
				print("✓ Melee hit enemy ", body.name, " for ", melee_damage, " damage!")
			melee_hitbox.set_deferred("monitoring", false)
		return
	
	if body.has_method("take_damage"):
		body.take_damage(melee_damage)
		if not is_headless_server:
			print("✓ Melee hit ", body.name, " for ", melee_damage, " damage!")
		melee_hitbox.set_deferred("monitoring", false)

# ============ DAMAGE AND DEATH ============

func take_damage(damage: int, source_id: int = -1, weapon_type: String = ""):
	if is_spectator or sync_is_dead or god_mode:
		return
	
	if not is_multiplayer_authority():
		rpc_id(int(name), "_take_damage_local", damage, source_id, weapon_type)
		return
	
	_take_damage_local(damage, source_id, weapon_type)

@rpc("any_peer", "call_local", "reliable")
func _take_damage_local(damage: int, source_id: int = -1, weapon_type: String = ""):
	if sync_is_dead:
		return
	
	if source_id != -1:
		last_damage_source = source_id
		last_damage_weapon = weapon_type
	
	current_health -= damage
	current_health = max(0, current_health)
	
	if not is_headless_server:
		_update_health_ui()
	
	if not is_headless_server:
		print("Player took ", damage, " damage. Health: ", current_health)
	
	if current_health <= 0:
		sync_is_dead = true
		_die()

func _update_health_ui():
	if health_label:
		health_label.text = "Health: " + str(current_health)

func _die():
	if is_spectator or (sync_is_dead and not is_multiplayer_authority()):
		return
	
	var killer_id = last_damage_source
	var weapon_type = last_damage_weapon
	
	var lobby = get_tree().get_current_scene()
	if lobby and lobby.has_method("report_kill"):
		if multiplayer.is_server():
			lobby.report_kill(killer_id, int(name), weapon_type)
		else:
			rpc_id(1, "_report_player_kill_to_lobby", killer_id, int(name), weapon_type)
	
	if not is_headless_server:
		print("Player died! Killer ID: ", killer_id, " Weapon: ", weapon_type)
		
	if lobby and lobby.has_method("report_player_death"):
		if not is_headless_server:
			print("Reporting death to lobby - Player ID: ", int(name))
		lobby.report_player_death.rpc_id(1, int(name))
	
	if not is_headless_server:
		print("Player died!")
	sync_is_dead = true
	
	if _body and _body.has_method("play_death_animation"):
		_body.play_death_animation(current_stance)
	
	collision_layer = 0
	collision_mask = 0
		
	if not is_headless_server:
		_stop_footstep_sounds()
	
	if detection_area:
		detection_area.monitoring = false
	
	if is_multiplayer_authority() and not is_headless_server:
		_switch_to_spectator_camera()
		
	if is_multiplayer_authority():
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(self):
			queue_free()

@rpc("any_peer", "call_remote", "reliable")
func _report_player_kill_to_lobby(killer_id: int, victim_id: int, weapon_type: String):
	if multiplayer.is_server():
		var lobby = get_tree().get_current_scene()
		if lobby and lobby.has_method("report_kill"):
			lobby.report_kill(killer_id, victim_id, weapon_type)
			
func set_god_mode(enabled: bool):
	god_mode = enabled
	if not is_headless_server:
		print("God mode ", "enabled" if enabled else "disabled")

func play_victory_dance():
	if not _body or not _body.animation_player:
		return
	
	is_victory_dancing = true
	god_mode = true
	
	freeze()
	
	if _body.has_method("play_victory_dance"):
		await _body.play_victory_dance()
	
	is_victory_dancing = false

# ============ VEHICLE HELPER FUNCTIONS ============

func _sync_visibility_from_export():
	"""Sync visibility state from MPSync export variable"""
	if visible != sync_visible:
		visible = sync_visible
		if sync_visible:
			show()
		else:
			hide()

func _switch_to_spectator_camera():
	"""Switch camera to another alive player when this player dies"""
	if not is_multiplayer_authority() or is_headless_server:
		return
	
	if camera:
		camera.current = false
	
	var all_players = get_tree().get_nodes_in_group("player")
	
	var alive_players = []
	for player in all_players:
		if player != self and player.has_method("is_alive") and player.is_alive():
			alive_players.append(player)
		elif player != self and not player.sync_is_dead:
			alive_players.append(player)
	
	if alive_players.size() > 0:
		var target_player = alive_players[0]
		if target_player.has_node("SpringArmOffset/SpringArm3D/Camera3D"):
			var target_camera = target_player.get_node("SpringArmOffset/SpringArm3D/Camera3D")
			target_camera.current = true
			print("Switched camera to player: ", target_player.name)
	else:
		print("No alive players to spectate")

func _enable_after_vehicle_exit():
	"""Called by car.gd after driver exit sequence completes"""
	if is_headless_server:
		return
		
	print("=== ENABLING PLAYER AFTER DRIVER EXIT ===")
	
	set_process_input(true)
	set_physics_process(true)
	
	can_shoot = true
	can_melee = true
	can_switch_weapon = true
	is_firing_held = false
	is_firing_sync = false
	is_aiming = false
	
	_update_weapon_visibility()
	
	_setup_collision()
	
	mouse_locked = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if camera:
		camera.current = true
	
	current_stance = "normal"
	_apply_collision_shape(current_stance)
	
	print("Player fully enabled after driver exit")

# REMOVED: return_to_lobby() function completely
