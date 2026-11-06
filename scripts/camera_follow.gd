extends Camera3D

@export var target: Node3D
@export var offset: Vector3 = Vector3(0, 8, 10) # Height and distance from the target.
@export var smooth_speed: float = 5.0

func _physics_process(delta: float) -> void:
	if target:
		var target_position = target.global_position + offset
		global_position = global_position.lerp(target_position, smooth_speed * delta)
		look_at(target.global_position, Vector3.UP)
