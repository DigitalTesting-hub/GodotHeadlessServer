extends Node3D

const LERP_VELOCITY: float = 0.15
const LOOK_LERP_VELOCITY: float = 0.2

@export_category("Objects")
@export var _character: CharacterBody3D = null
@export var animation_player: AnimationPlayer = null

@export_category("Animation Settings")
@export var idle_speed: float = 1.0
@export var walk_speed: float = 1.0
@export var run_speed: float = 1.0
@export var jump_speed: float = 1.0
@export var crouch_speed: float = 0.8
@export var prone_speed: float = 0.6
@export var melee_speed: float = 1.5
@export var firing_speed: float = 1.0
@export var aim_speed: float = 1.0
@export var victory_dance_speed: float = 1

# Animation state
var is_melee_attacking: bool = false
var is_dancing: bool = false
var is_in_car: bool = false

# Headless server flag
var is_headless_server: bool = false

func _ready():
	# Check for headless server
	is_headless_server = OS.has_feature("dedicated_server")
	
	# Skip animation setup for headless servers
	if is_headless_server:
		set_process(false)
		set_physics_process(false)

func apply_rotation(_velocity: Vector3) -> void:
	# Skip rotation for headless servers
	if is_headless_server:
		return
		
	if _velocity.length() < 0.1:
		return
	var new_rotation_y = lerp_angle(rotation.y, atan2(-_velocity.x, -_velocity.z), LERP_VELOCITY)
	rotation.y = new_rotation_y

func apply_look_rotation(target_position: Vector3) -> void:
	# Skip rotation for headless servers
	if is_headless_server:
		return
		
	var direction = (target_position - global_position).normalized()
	var target_rotation_y = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation_y, LOOK_LERP_VELOCITY)

func play_melee_animation():
	# Skip animations for headless servers
	if is_headless_server or not animation_player:
		return
		
	if animation_player.has_animation("Attack2"):
		is_melee_attacking = true
		animation_player.play("Attack2")
		animation_player.speed_scale = melee_speed
		await animation_player.animation_finished
		is_melee_attacking = false

func play_victory_dance():
	# Skip animations for headless servers
	if is_headless_server or not animation_player:
		return
		
	if animation_player.has_animation("Dance"):
		is_dancing = true
		animation_player.play("Dance")
		animation_player.speed_scale = victory_dance_speed
		await animation_player.animation_finished
		is_dancing = false

func animate(_velocity: Vector3, stance: String, is_firing: bool = false, is_aiming: bool = false, look_target: Vector3 = Vector3.ZERO) -> void:
	# Skip all animations for headless servers
	if is_headless_server or not animation_player or not _character:
		return
	
	# Skip all animations if in car
	if is_in_car:
		return
	
	# Don't change animations during melee attack
	if is_melee_attacking:
		return
	
	# Don't change animations during dance
	if is_dancing:
		return
	
	var should_look_at_target = (is_firing or is_aiming) and look_target != Vector3.ZERO and _character.current_weapon == _character.WeaponType.GUN
	
	if should_look_at_target:
		apply_look_rotation(look_target)
	elif _velocity.length() > 0.1:
		apply_rotation(_velocity)
	
	var anim_to_play = ""
	var anim_speed = 1.0
	var is_moving = _velocity.length() > 0.1
	var is_running = _character.is_running() if _character.has_method("is_running") else false
	var is_on_ground = _character.is_on_floor()
	
	match stance:
		"normal":
			if not is_on_ground:
				anim_to_play = "RifleJump"
				anim_speed = jump_speed
			elif is_aiming and _character.current_weapon == _character.WeaponType.GUN:
				anim_to_play = "RifleAim"
				anim_speed = aim_speed
			elif is_firing:
				if is_running and is_moving:
					anim_to_play = "RunFire"
					anim_speed = run_speed
				elif is_moving:
					anim_to_play = "WalkFire"
					anim_speed = walk_speed
				else:
					anim_to_play = "Firing"
					anim_speed = firing_speed
			elif is_moving:
				if is_running:
					anim_to_play = "GunRun"
					anim_speed = run_speed
				else:
					anim_to_play = "GunWalk"
					anim_speed = walk_speed
			else:
				anim_to_play = "RifleIdle"
				anim_speed = idle_speed
		
		"crouch":
			if is_aiming and _character.current_weapon == _character.WeaponType.GUN:
				anim_to_play = "IdleCrAim"
				anim_speed = aim_speed
			elif is_firing:
				if is_moving:
					anim_to_play = "CrWFire"
					anim_speed = crouch_speed
				else:
					anim_to_play = "CrFire"
					anim_speed = firing_speed
			elif is_moving:
				anim_to_play = "CrWalk"
				anim_speed = crouch_speed
			else:
				anim_to_play = "CrIdle"
				anim_speed = idle_speed
		
		"prone":
			if is_firing:
				anim_to_play = "ProneFire"
				anim_speed = firing_speed
			elif is_moving:
				anim_to_play = "ProneForward"
				anim_speed = prone_speed
			else:
				anim_to_play = "ProneIdle"
				anim_speed = idle_speed
	
	if animation_player.has_animation(anim_to_play):
		if animation_player.current_animation != anim_to_play:
			animation_player.play(anim_to_play)
			animation_player.speed_scale = anim_speed
		else:
			animation_player.speed_scale = anim_speed

func play_death_animation(stance: String):
	# Skip animations for headless servers
	if is_headless_server or not animation_player:
		return
		
	var death_anim = ""
	match stance:
		"crouch":
			death_anim = "CrDeath"
		"prone":
			death_anim = "ProneDeath"
		_:
			death_anim = "Death"
	if animation_player.has_animation(death_anim):
		animation_player.play(death_anim)
		animation_player.speed_scale = 1.0

# Headless server helper functions
func is_headless() -> bool:
	return is_headless_server

func disable_animations():
	"""Disable all animations for headless server"""
	is_headless_server = true
	set_process(false)
	set_physics_process(false)
	if animation_player:
		animation_player.stop()
		animation_player.set_process(false)
