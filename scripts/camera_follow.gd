extends Camera3D

@export var target: Node3D
@export var offset: Vector3 = Vector3(0,8,10) # Altura (Y) y distancia (Z) respecto a la pelota
@export var smooth_speed: float = 5.0


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if target:
		# Calcula la posición deseada sin importar cuánto gire la pelota
		var target_position = target.global_position + offset
		
		# Desplaza la cámara suavemente hacia la nueva posición
		global_position = global_position.lerp(target_position, smooth_speed * delta)
		
		# Apunta la cámara directamente a la pelota
		look_at(target.global_position, Vector3.UP)
