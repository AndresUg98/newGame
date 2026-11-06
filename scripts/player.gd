extends CharacterBody3D

# Player control and state.
@export var is_player_controlled: bool = false
enum PlayerState { USER_CONTROL, SUPPORT_ATTACK, DEFEND, WAIT_FOR_PASS }
var current_state: PlayerState = PlayerState.SUPPORT_ATTACK

# Movement settings.
@export var based_speed: float = 10.0
@export var speed_with_ball: float = 15.0
const JUMP_VELOCITY = 4.5

# Ball possession and dribbling.
@export var dribble_speed: float = 25.0
@export var max_dribble_distance: float = 2.5
@export var ball_pickup_radius: float = 1.6
@onready var dribble_pos: Marker3D = $DribblePos
var ball: RigidBody3D = null
var pickup_lockout: float = 0.0
var receive_direction: Vector3 = Vector3.ZERO

# Shooting and passing.
@export var min_kick_force: float = 25.0
@export var max_kick_force: float = 50.0
@export var min_kick_up_force: float = 1.0
@export var max_kick_up_force: float = 6.0
@export var max_charge_time: float = 1.0
var charge_time: float = 0.0
var is_charging: bool = false

@export var pass_force: float = 20.0
@export var max_pass_angle: float = 45.0

# Teammate AI settings.
@export var ai_speed: float = 8.0
@export var personal_space: float = 2.5  # Minimum space between teammates.
@export var support_distance: float = 5.0
@export var lane_follow: float = 0.4
var initial_position: Vector3

func _ready() -> void:
	initial_position = global_position
	if is_player_controlled:
		current_state = PlayerState.USER_CONTROL
	else:
		current_state = PlayerState.SUPPORT_ATTACK

func _physics_process(delta: float) -> void:
	pickup_lockout = maxf(pickup_lockout - delta, 0.0)

	var direction = Vector3.ZERO

	# Show which player is controlled.
	$Indicator.visible = is_player_controlled

	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle the current player state.
	match current_state:
		PlayerState.USER_CONTROL:
			var input_dir = Input.get_vector("left", "right", "forward", "back")
			direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
			
			if Input.is_action_just_pressed("ui_accept") and is_on_floor() and not is_charging:
				velocity.y = JUMP_VELOCITY

			# Allow switching players when not holding the ball.
			if ball == null and Input.is_action_just_pressed("switch_player"):
				manual_switch()
				
		PlayerState.SUPPORT_ATTACK:
			is_charging = false
			var ball_nodes = get_tree().get_nodes_in_group("game_ball")
			if ball_nodes.size() > 0:
				var game_ball = ball_nodes[0]
				var steering = Vector3.ZERO 
				
				var teammates = get_tree().get_nodes_in_group("team_player")
				
				# Check whether a teammate already has the ball.
				var team_has_ball = false
				for t in teammates:
					if t.ball != null:
						team_has_ball = true
						break
				
				# Shift the home position with the ball while keeping each player's lane.
				var ball_offset = game_ball.global_position - Vector3(initial_position.x, game_ball.global_position.y, initial_position.z)
				var formation_target = Vector3(
					initial_position.x + ball_offset.x * 0.65,
					global_position.y,
					initial_position.z + ball_offset.z * lane_follow
				)
				var support_target = formation_target

				# Rank AI teammates by their starting position along the attack direction.
				var attack_direction = sign(initial_position.x)
				var teammates_ahead = 0
				for teammate in teammates:
					if teammate == self or teammate.is_player_controlled:
						continue
					if (teammate.initial_position.x - initial_position.x) * attack_direction > 0.0:
						teammates_ahead += 1

				# The two most advanced AI players move forward; the others stay behind.
				if team_has_ball:
					if teammates_ahead < 2:
						var forward_target_x = game_ball.global_position.x + attack_direction * support_distance
						if attack_direction > 0.0:
							support_target.x = maxf(support_target.x, forward_target_x)
						else:
							support_target.x = minf(support_target.x, forward_target_x)
					else:
						var defensive_target_x = game_ball.global_position.x - attack_direction * support_distance
						if attack_direction > 0.0:
							support_target.x = minf(support_target.x, defensive_target_x)
						else:
							support_target.x = maxf(support_target.x, defensive_target_x)

				var vector_to_support = support_target - global_position
				if vector_to_support.length() > 0.5:
					steering += vector_to_support.normalized() * minf(vector_to_support.length() / 4.0, 1.5)
				
				# The closest teammate chases the ball when nobody has it.
				if not team_has_ball:
					var dist_to_ball = global_position.distance_to(game_ball.global_position)
					var am_i_closest = true
					
					for t in teammates:
						if t != self and t.current_state != PlayerState.USER_CONTROL:
							if t.global_position.distance_to(game_ball.global_position) < dist_to_ball:
								am_i_closest = false
								break
					
					if am_i_closest:
						var seek_force = (game_ball.global_position - global_position).normalized()
						# Prioritize chasing the ball over keeping formation.
						steering += seek_force * 2.5 
				
				
			# Keep teammates from crowding each other.
				var separation = Vector3.ZERO
				for t in teammates:
					if t != self:
						var dist = global_position.distance_to(t.global_position)
						if dist < personal_space and dist > 0.1:

							separation += (global_position - t.global_position).normalized() * (personal_space - dist)
							
				steering += separation * 4.0 
				
				# Combine the steering forces into movement.
				steering.y = 0 
				if steering.length() > 0.1:

					if steering.length() > 1.0:
						direction = steering.normalized()
					else:
						direction = steering

		PlayerState.WAIT_FOR_PASS:
			direction = Vector3.ZERO
			is_charging = false

	# Stop moving while charging a shot.
	if is_charging:
		direction = Vector3.ZERO

	# Choose a speed based on control and possession.
	var current_speed = based_speed
	if current_state != PlayerState.USER_CONTROL:
		current_speed = ai_speed
	elif ball != null:
		current_speed = speed_with_ball

	# Apply smooth movement and face the travel direction.
	if direction != Vector3.ZERO:

		velocity.x = lerpf(velocity.x, direction.x * current_speed, 10.0 * delta)
		velocity.z = lerpf(velocity.z, direction.z * current_speed, 10.0 * delta)
		

		var move_intensity = Vector2(velocity.x, velocity.z).length()
		if move_intensity > 0.5:
			look_at(global_position + direction, Vector3.UP)
	else:
		# Slow down smoothly when there is no movement input.
		velocity.x = lerpf(velocity.x, 0, 15.0 * delta)
		velocity.z = lerpf(velocity.z, 0, 15.0 * delta)


	move_and_slide()

	# Pick up the ball on contact and activate this player.
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()

		if collider is RigidBody3D and ball == null:
			claim_ball(collider)

	# Catch the ball by proximity if slide collision did not report it.
	if ball == null and pickup_lockout <= 0.0:
		var ball_nodes = get_tree().get_nodes_in_group("game_ball")
		if ball_nodes.size() > 0:
			var loose_ball = ball_nodes[0] as RigidBody3D
			var ball_is_held = false
			for teammate in get_tree().get_nodes_in_group("team_player"):
				if teammate.ball == loose_ball:
					ball_is_held = true
					break

			# Only collect a loose ball that has reached this player's catch radius.
			if not ball_is_held and global_position.distance_to(loose_ball.global_position) <= ball_pickup_radius:
				claim_ball(loose_ball)

	# Dribble, pass, or shoot while holding the ball.
	if ball:
		var dist = global_position.distance_to(ball.global_position)

		if dist > max_dribble_distance:
			remove_collision_exception_with(ball)
			ball = null
			is_charging = false
			charge_time = 0.0
		else:
			if current_state == PlayerState.USER_CONTROL:
				# Pass once per key press so a receiver cannot pass again from a held key.
				if Input.is_action_just_pressed("pass"):
					pass_ball()
				elif Input.is_action_pressed("shoot"):
					is_charging = true
					charge_time += delta
					if charge_time > max_charge_time:
						charge_time = max_charge_time
				elif is_charging:
					shoot_ball()
					is_charging = false
					charge_time = 0.0

			if ball:
				var target_pos = dribble_pos.global_position
				var to_target = target_pos - ball.global_position
				ball.linear_velocity.x = to_target.x * dribble_speed
				ball.linear_velocity.z = to_target.z * dribble_speed
func become_active_player() -> void:
	current_state = PlayerState.USER_CONTROL
	is_player_controlled = true
	
	var teammates = get_tree().get_nodes_in_group("team_player")
	for teammate in teammates:
		if teammate != self:
			teammate.is_player_controlled = false
			teammate.current_state = PlayerState.SUPPORT_ATTACK
			teammate.is_charging = false

func shoot_ball() -> void:
	var power_ratio = charge_time / max_charge_time
	var current_kick_force = lerpf(min_kick_force, max_kick_force, power_ratio)
	var current_kick_up_force = lerpf(min_kick_up_force, max_kick_up_force, power_ratio)

	var shoot_dir = -global_transform.basis.z.normalized()
	remove_collision_exception_with(ball)
	
	var impulse = (shoot_dir * current_kick_force) + (Vector3.UP * current_kick_up_force)
	ball.apply_central_impulse(impulse)
	ball = null

func pass_ball() -> void:
	var teammates = get_tree().get_nodes_in_group("team_player")
	if teammates.size() <= 1:
		return

	var best_teammate = null
	var smallest_angle = max_pass_angle
	
	var player_forward = -global_transform.basis.z
	player_forward.y = 0 
	player_forward = player_forward.normalized()

	for teammate in teammates:
		if teammate == self:
			continue

		var direction_to_teammate = teammate.global_position - global_position
		direction_to_teammate.y = 0
		direction_to_teammate = direction_to_teammate.normalized()

		var angle_to_teammate = rad_to_deg(player_forward.angle_to(direction_to_teammate))

		if angle_to_teammate < smallest_angle:
			smallest_angle = angle_to_teammate
			best_teammate = teammate

	if best_teammate:
		# Keep the pass level and aim at the teammate's ground position.
		var pass_dir = best_teammate.global_position - global_position
		pass_dir.y = 0.0
		pass_dir = pass_dir.normalized()
		remove_collision_exception_with(ball)
		
		var impulse = (pass_dir * pass_force)
		ball.apply_central_impulse(impulse)
		# Give the passer time to move away before it can collect the ball again.
		pickup_lockout = 0.4
		# Save the pass direction so the receiver can face the play on contact.
		best_teammate.receive_direction = pass_dir
		
		self.is_player_controlled = false
		self.is_charging = false
		self.current_state = PlayerState.SUPPORT_ATTACK
		
		best_teammate.is_player_controlled = false 
		best_teammate.current_state = PlayerState.WAIT_FOR_PASS
		
		ball = null

func claim_ball(target_ball: RigidBody3D) -> void:
	# Face the pass direction when available, or the ball's travel direction.
	var incoming_direction = receive_direction
	if incoming_direction.length() <= 0.1:
		incoming_direction = target_ball.linear_velocity
	incoming_direction.y = 0.0
	if incoming_direction.length() > 0.1:
		look_at(global_position + incoming_direction.normalized(), Vector3.UP)
	receive_direction = Vector3.ZERO

	# Take possession and cancel any bounce or spin.
	ball = target_ball
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	add_collision_exception_with(ball)

	# Activate an AI teammate as soon as it receives the ball.
	if current_state == PlayerState.WAIT_FOR_PASS or current_state == PlayerState.SUPPORT_ATTACK:
		become_active_player()


# Switch control to the closest teammate.
func manual_switch() -> void:
	var ball_nodes = get_tree().get_nodes_in_group("game_ball")
	if ball_nodes.size() == 0:
		return
		
	var game_ball = ball_nodes[0]
	var teammates = get_tree().get_nodes_in_group("team_player")
	
	var best_teammate = null
	var min_dist = INF
	
	# Find the teammate closest to the ball.
	for t in teammates:
		if t == self:
			continue
			
		var dist = t.global_position.distance_to(game_ball.global_position)
		if dist < min_dist:
			min_dist = dist
			best_teammate = t
			

	if best_teammate:
		# Return this player to AI support.
		self.is_player_controlled = false
		self.current_state = PlayerState.SUPPORT_ATTACK
		self.is_charging = false
		
		# Give control to the selected teammate.
		best_teammate.is_player_controlled = true
		best_teammate.current_state = PlayerState.USER_CONTROL
