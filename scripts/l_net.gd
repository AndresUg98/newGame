extends CSGCombiner3D

@export var center_position: Vector3 = Vector3(0, 5, 0)

func _on_goal_detector_body_entered(body: Node3D) -> void:
	if body.name == "Ball":
		print("Goool left net")
		body.global_position = center_position
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
