extends CSGCombiner3D
@export var center_position : Vector3 = Vector3(0,5,0)

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass


func _on_goal_detector_body_entered(body: Node3D) -> void:
	#Verify if the ball entered in the net

	if body.name == "Ball":
		print("Goool right net")

		#reposition the ball on the center of the pitch
		body.global_position = center_position

		#Stoping the ball, so it doesn´t move when relocated
		body.linear_velocity =Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

		#further scorinng system will be here
