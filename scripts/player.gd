extends CharacterBody3D

# --- CONTROL Y ESTADOS ---
@export var is_player_controlled: bool = false
enum PlayerState { USER_CONTROL, SUPPORT_ATTACK, DEFEND, WAIT_FOR_PASS }
var current_state: PlayerState = PlayerState.SUPPORT_ATTACK

# --- MOVIMIENTO ---
@export var based_speed: float = 10.0
@export var speed_with_ball: float = 15.0
@export var push_force: float = 3.0
const JUMP_VELOCITY = 4.5

# --- BALÓN Y CONDUCCIÓN ---
@export var dribble_speed: float = 25.0
@export var max_dribble_distance: float = 2.5
@onready var dribble_pos: Marker3D = $DribblePos
var ball: RigidBody3D = null

# --- DISPARO Y PASE ---
@export var min_kick_force: float = 25.0
@export var max_kick_force: float = 50.0
@export var min_kick_up_force: float = 1.0
@export var max_kick_up_force: float = 6.0
@export var max_charge_time: float = 1.0
var charge_time: float = 0.0
var is_charging: bool = false

@export var pass_force: float = 20.0
@export var max_pass_angle: float = 45.0

# --- IA (ZONAS Y SEPARACIÓN) ---
@export var ai_speed: float = 8.0
@export var zone_radius: float = 8.0     # Qué tanto pueden alejarse de su posición original
@export var personal_space: float = 2.5  # El radio que nadie más puede pisar
var initial_position: Vector3

func _ready() -> void:
	initial_position = global_position
	if is_player_controlled:
		current_state = PlayerState.USER_CONTROL
	else:
		current_state = PlayerState.SUPPORT_ATTACK

func _physics_process(delta: float) -> void:


	var direction = Vector3.ZERO

	#Indicador visual de a quien controla el jugador
	$Indicator.visible = is_player_controlled

	if not is_on_floor():
		velocity += get_gravity() * delta

	if not is_on_floor():
		velocity += get_gravity() * delta

	# --- MÁQUINA DE ESTADOS ---
	match current_state:
		PlayerState.USER_CONTROL:
			var input_dir = Input.get_vector("left", "right", "forward", "back")
			direction = Vector3(input_dir.x, 0, input_dir.y).normalized()
			
			if Input.is_action_just_pressed("ui_accept") and is_on_floor() and not is_charging:
				velocity.y = JUMP_VELOCITY

			#Cambio manual si no tenemos el balon
			if ball == null and Input.is_action_just_pressed("switch_player"):
				manual_switch()
				
		PlayerState.SUPPORT_ATTACK:
			is_charging = false
			var ball_nodes = get_tree().get_nodes_in_group("game_ball")
			if ball_nodes.size() > 0:
				var game_ball = ball_nodes[0]
				var steering = Vector3.ZERO 
				
				var teammates = get_tree().get_nodes_in_group("team_player")
				
				# Verificar si ALGUIEN del equipo ya tiene el balón controlado
				var team_has_ball = false
				for t in teammates:
					if t.ball != null:
						team_has_ball = true
						break
				
				# 1. FUERZA DE FORMACIÓN (CORREGIDA PARA TU CANCHA)
				# El Eje X es el largo (ataque/defensa). El Eje Z es el ancho (carril).
				# initial_position.x * 0.5 asegura que los delanteros se adelanten y los defensas se queden atrás
				var target_x = game_ball.global_position.x + (initial_position.x * 0.5)
				var formation_target = Vector3(target_x, global_position.y, initial_position.z)
				var vector_to_formation = formation_target - global_position
				
				if vector_to_formation.length() > 0.5:
					steering += vector_to_formation.normalized() * 1.0 
				
				# 2. FUERZA "ON DUTY" (Ir por el balón solo si está suelto)
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
						# Peso de 2.5 para que la urgencia del balón rompa la formación
						steering += seek_force * 2.5 
				
				
			# 3. FUERZA DE SEPARACIÓN (Corregida para que actúe como un imán suave)
				var separation = Vector3.ZERO
				for t in teammates:
					if t != self:
						var dist = global_position.distance_to(t.global_position)
						if dist < personal_space and dist > 0.1:
							# Cambiamos '/ dist' por '* (personal_space - dist)'
							# Esto hace que la fuerza se desvanezca a CERO suavemente antes de chocar
							separation += (global_position - t.global_position).normalized() * (personal_space - dist)
							
				steering += separation * 4.0 
				
				# --- APLICAR LA SUMA TOTAL DE FUERZAS ---
				steering.y = 0 
				if steering.length() > 0.1:
					# Si el empuje es pequeño, caminan despacio. Si es muy grande, se limitan a correr (1.0)
					if steering.length() > 1.0:
						direction = steering.normalized()
					else:
						direction = steering

		PlayerState.WAIT_FOR_PASS:
			direction = Vector3.ZERO
			is_charging = false

	# Detener movimiento si estamos cargando un tiro
	if is_charging:
		direction = Vector3.ZERO

	# Calcular velocidad actual
	var current_speed = based_speed
	if current_state != PlayerState.USER_CONTROL:
		current_speed = ai_speed
	elif ball != null:
		current_speed = speed_with_ball

	# --- APLICAR MOVIMIENTO Y ROTACIÓN (SIN TEMBLORES) ---
	if direction != Vector3.ZERO:
		# Usamos "lerpf" para acelerar de forma suave y humana, evitando tirones robóticos
		velocity.x = lerpf(velocity.x, direction.x * current_speed, 10.0 * delta)
		velocity.z = lerpf(velocity.z, direction.z * current_speed, 10.0 * delta)
		
		# SOLO rotamos la mirada si el jugador realmente se está moviendo con fuerza
		# (Esto es lo que elimina que tiemblen cuando están casi parados)
		var move_intensity = Vector2(velocity.x, velocity.z).length()
		if move_intensity > 0.5:
			look_at(global_position + direction, Vector3.UP)
	else:
		# Frenado suave (derrape ligero)
		velocity.x = lerpf(velocity.x, 0, 15.0 * delta)
		velocity.z = lerpf(velocity.z, 0, 15.0 * delta)

	

	move_and_slide()

	# --- COLISIONES Y CAMBIO DE JUGADOR AUTOMÁTICO ---
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()

		if collider is RigidBody3D and ball == null:
			ball = collider
			add_collision_exception_with(ball)
			
			if current_state == PlayerState.WAIT_FOR_PASS or current_state == PlayerState.SUPPORT_ATTACK:
				become_active_player()

	# --- CONDUCCIÓN, PASE Y DISPARO ---
	if ball:
		var dist = global_position.distance_to(ball.global_position)

		if dist > max_dribble_distance:
			remove_collision_exception_with(ball)
			ball = null
			is_charging = false
			charge_time = 0.0
		else:
			if current_state == PlayerState.USER_CONTROL:
				if Input.is_physical_key_pressed(KEY_F):
					pass_ball()
				elif Input.is_physical_key_pressed(KEY_E):
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
		var pass_dir = (best_teammate.global_position - global_position).normalized()
		remove_collision_exception_with(ball)
		
		var impulse = (pass_dir * pass_force)
		ball.apply_central_impulse(impulse)
		
		self.is_player_controlled = false
		self.is_charging = false
		self.current_state = PlayerState.SUPPORT_ATTACK
		
		best_teammate.is_player_controlled = false 
		best_teammate.current_state = PlayerState.WAIT_FOR_PASS
		
		ball = null


# --- CAMBIO MANUAL DE JUGADOR ---
func manual_switch() -> void:
	var ball_nodes = get_tree().get_nodes_in_group("game_ball")
	if ball_nodes.size() == 0:
		return
		
	var game_ball = ball_nodes[0]
	var teammates = get_tree().get_nodes_in_group("team_player")
	
	var best_teammate = null
	var min_dist = INF # Usamos Infinito para que cualquier distancia sea menor en la primera revisión
	
	# Buscar al compañero (que no seas tú) que esté más cerca de la pelota
	for t in teammates:
		if t == self:
			continue
			
		var dist = t.global_position.distance_to(game_ball.global_position)
		if dist < min_dist:
			min_dist = dist
			best_teammate = t
			
	# Si encontramos a alguien
	if best_teammate:
		# 1. Te quitas el control a ti mismo y pasas a ser IA (Apoyo)
		self.is_player_controlled = false
		self.current_state = PlayerState.SUPPORT_ATTACK
		self.is_charging = false
		
		# 2. Le transfieres el control absoluto al compañero elegido
		best_teammate.is_player_controlled = true
		best_teammate.current_state = PlayerState.USER_CONTROL
