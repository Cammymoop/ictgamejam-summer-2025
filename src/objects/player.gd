extends CharacterBody3D

@onready var ground_detector: RayCast3D = find_child("GroundDetector")

@onready var tentacle_root: Node3D = find_child("Tentacles")
@onready var find_pos: Marker3D = find_child("FindPos")

@onready var new_tentacle_front_raycast: Node3D = find_child("NewTentacleFrontRaycast")
@onready var new_tentacle_raycast: RayCast3D = find_child("NewTentacleRaycast")
@onready var new_tentacle_raycast2: RayCast3D = find_child("NewTentacleRaycast2")
@onready var next_new := new_tentacle_raycast

@export var movement_speed: float = 5.0
@export var movement_interp: float = 6.0

@export var facing_interp: float = 7.0

@export var raise_speed: float = 3.2
@export var raise_interp: float = 4.0

@export var drag_factor: float = 0.93

@export var tentacle_extend_time: float = 0.1
@export_exp_easing() var tentacle_extend_ease: float = 0.41

var tentacle_extended: Array[bool] = []

var max_tentacle_dist: float = 3.2

var is_above_floor: bool = false
var was_above_floor: bool = false
var cur_floor_distance: float = 0.0
var floor_target_distance: float = 1.3

var want_extended: int = 7

var camera_node: Camera3D = null

var hold: bool = false

func _ready() -> void:
    camera_node = get_viewport().get_camera_3d()
    if not camera_node:
        print_debug("No camera found for player, unable to use relative movement")
    
    find_tentacles()
    
    hold = true

func find_tentacles() -> void:
    for tentacle in tentacle_root.get_children():
        tentacle_extended.append(false)

func _physics_process(delta: float) -> void:
    if hold:
        return
    
    # Add the gravity.
    detect_floor()
    if not is_above_floor:
        velocity += get_gravity() * delta
    else:
        var target_y_vel := 0.0
        if cur_floor_distance < floor_target_distance:
            target_y_vel = raise_speed
        else:
            target_y_vel = get_gravity().y * 0.2
        velocity.y = lerp(velocity.y, target_y_vel, delta * raise_interp)

    var input_dir := Input.get_vector("left", "right", "forward", "back")
    var camera_forward: = Vector3.FORWARD
    if camera_node:
        camera_forward = camera_node.global_basis.z
        camera_forward.y = 0.0
    var direction := (camera_forward * Vector3(input_dir.x, 0, input_dir.y)).normalized()

    var current_vel := velocity
    var y_vel := current_vel.y
    current_vel.y = 0

    if direction:
        current_vel = lerp(current_vel, direction * movement_speed, delta * movement_interp)
        
        global_basis = lerp(global_basis, Basis.looking_at(direction, Vector3.UP), delta * facing_interp)
    else:
        current_vel *= drag_factor

    current_vel.y = y_vel
    velocity = current_vel
    move_and_slide()

func _process(delta: float) -> void:
    process_tentacles(delta)
    was_above_floor = is_above_floor
    
    if Input.is_action_just_pressed("action"):
        hold = not hold

func detect_floor() -> void:
    is_above_floor = ground_detector.is_colliding()
    if is_above_floor:
        cur_floor_distance = abs(to_local(ground_detector.get_collision_point()).length())
    else:
        cur_floor_distance = 0.0

func extend_standing_tentacles() -> void:
    if not is_above_floor:
        return
    
    var extended_count: int = 0
    for i in tentacle_extended.size():
        extended_count += 1 if tentacle_extended[i] else 0
    
    var extend_more: int = want_extended - extended_count
    if extend_more > 0:
        var unextended_indexes: Array[int] = []
        for i in tentacle_extended.size():
            if not tentacle_extended[i]:
                unextended_indexes.append(i)
        unextended_indexes.shuffle()
        
        for i in extend_more:
            var index: int = unextended_indexes.pop_front()
            tentacle_extended[index] = true

            var tentacle: MeshInstance3D = tentacle_root.get_child(index)
            var tentacle_forward: Vector3 = tentacle.position
            tentacle_forward.y = 0.0
            
            var rc := new_tentacle_front_raycast
            var old_raycast_transform: = rc.transform
            rc.transform = Transform3D(Basis.looking_at(tentacle_forward, Vector3.UP), Vector3.ZERO) * rc.transform
            rc.force_raycast_update()
            if rc.is_colliding():
                var col_pos: Vector3 = rc.get_collision_point()
                tentacle.set_instance_shader_parameter("tentatarget", col_pos)
            else:
                tentacle_extended[index] = false
            rc.transform = old_raycast_transform
            rc.force_raycast_update()


func process_tentacles(delta: float) -> void:
    extend_standing_tentacles()
    for i in tentacle_root.get_child_count():
        if not is_above_floor:
            tentacle_extended[i] = false
            continue
        
        var tentacle: MeshInstance3D = tentacle_root.get_child(i)
        var cur_extent: float = tentacle.get_instance_shader_parameter("extended")
        if tentacle_extended[i]:
            tentacle.set_instance_shader_parameter("extended", extend_lerp(cur_extent, 1.0, delta))
            var local_tip_pos: Vector3 = to_local(tentacle.get_instance_shader_parameter("tentatarget"))
            if local_tip_pos.length() > max_tentacle_dist:
                try_extend_next_tentacle()
                tentacle_extended[i] = false
    
    for i in tentacle_extended.size():
        if not tentacle_extended[i]:
            var tentacle: MeshInstance3D = tentacle_root.get_child(i)
            var cur_extent: float = tentacle.get_instance_shader_parameter("extended")
            if cur_extent > 0.001:
                tentacle.set_instance_shader_parameter("extended", extend_lerp(cur_extent, 0.0, delta))

func extend_lerp(cur: float, target: float, delta: float) -> float:
    var cur_time: float = absf((1 - target) - cur)
    var next_time_linear: float = ease(cur_time, 1/tentacle_extend_ease) + (delta / tentacle_extend_time)
    return lerp(cur, target, ease(next_time_linear, tentacle_extend_ease))

func try_extend_next_tentacle() -> void:
    if not is_above_floor:
        return
    
    if not new_tentacle_raycast.is_colliding() and not new_tentacle_raycast2.is_colliding():
        return
    
    var unextended_indexes: Array[int] = []
    for i in tentacle_extended.size():
        if not tentacle_extended[i]:
            unextended_indexes.append(i)
    unextended_indexes.shuffle()
    
    var raycast: = next_new
    if new_tentacle_raycast.is_colliding() and new_tentacle_raycast2.is_colliding():
        next_new = new_tentacle_raycast2 if next_new == new_tentacle_raycast else new_tentacle_raycast
    elif new_tentacle_raycast.is_colliding():
        raycast = new_tentacle_raycast
    else:
        raycast = new_tentacle_raycast2
    
    var col_pos: Vector3 = raycast.get_collision_point()
    var t_index: int = unextended_indexes.pop_front()
    tentacle_extended[t_index] = true

    var tentacle: MeshInstance3D = tentacle_root.get_child(t_index)
    tentacle.set_instance_shader_parameter("extended", 0.0)
    tentacle.set_instance_shader_parameter("tentatarget", col_pos)
