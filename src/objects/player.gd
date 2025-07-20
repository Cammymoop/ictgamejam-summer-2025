class_name Player
extends CharacterBody3D

@export var bike_anim_player: AnimationPlayer = null
var anim_played: bool = false

@onready var ground_detector: RayCast3D = find_child("GroundDetector")

@onready var tentacle_root: Node3D = find_child("Tentacles")
@onready var find_pos: Marker3D = find_child("FindPos")

@onready var new_tentacle_front_raycast: Node3D = find_child("NewTentacleFrontRaycast")
@onready var new_tentacle_raycast: RayCast3D = find_child("NewTentacleRaycast")
@onready var new_tentacle_raycast2: RayCast3D = find_child("NewTentacleRaycast2")
@onready var next_new := new_tentacle_raycast

@onready var only_face_forward: Node3D = find_child("OnlyFaceForward")

@export var movement_speed: float = 8.0
@export var movement_interp: float = 6.0

@export var facing_interp: float = 7.0

@export var raise_speed: float = 3.2
@export var raise_interp: float = 4.0

@export var drag_factor: float = 0.93

@export var tentacle_extend_time: float = 0.1
@export_exp_easing() var tentacle_extend_ease: float = 0.41

@export var attach_dist: float = 3.8
@export var attach_float_time: float = 0.5
var attach_f_timeleft: float = 0.0
@export var attach_snap_time: float = 0.35
var attach_snap_timeleft: float = 0.0
@export var attach_float_up: float = 0.5

@export_exp_easing() var attach_orientation_ease: float = 1
@export_exp_easing() var attach_snap_ease: float = 3

@export var detach_impulse_up_angle: float = PI / 6.0
@export var detach_impulse_strength: float = 8.6

@export var jump_impulse_strength: float = 8.6

@export var jump_min_delay: float = 0.4
var jump_delay_timeleft: float = 0.0

@export var lerp_to_horiz_time: float = 0.6
var attach_blacklist: Array[Node3D] = []

var look_vec: Vector3 = Vector3.FORWARD

var snapping_from_global_pos: Vector3 = Vector3.ZERO

var is_lerping_to_horiz: bool = false
var lerp_to_horiz_timeleft: float = 0.0

var is_attaching: bool = false
var is_fully_attached: bool = false
var attach_target: Node3D = null

var tentacle_extended: Array[bool] = []

var max_tentacle_dist: float = 3.2

var is_above_floor: bool = false
var was_above_floor: bool = false
var cur_floor_distance: float = 0.0
var was_floor_distance: float = 0.0
var floor_target_distance: float = 1.3

var want_extended: int = 7

var camera_node: Camera3D = null

var hold: bool = false

func _ready() -> void:
    camera_node = get_viewport().get_camera_3d()
    if not camera_node:
        print_debug("No camera found for player, unable to use relative movement")
    
    find_tentacles()
    
    look_vec = -global_basis.z
    
    #hold = true

func find_tentacles() -> void:
    for tentacle in tentacle_root.get_children():
        tentacle_extended.append(false)

func attach_float_update(delta: float) -> void:
    if not attach_target:
        print("A")
        break_off_attach()
        return
    if attach_f_timeleft <= 0:
        attach_snap_update(delta)
        return

    velocity.y = attach_float_up
    attach_f_timeleft -= delta
    if attach_f_timeleft <= 0.0:
        snapping_from_global_pos = global_position
        velocity.y = 0.0
        attach_snap_timeleft = attach_snap_time
        return
    
    var progress: float = 1.0 - (attach_f_timeleft / attach_float_time)
    var target_basis: = attach_target.global_basis
    target_basis = target_basis.orthonormalized()
    global_basis = lerp(global_basis, target_basis, ease(progress, attach_orientation_ease))
    attach_tentacles_to_target(attach_target.global_transform, progress)

func attach_snap_update(delta: float) -> void:
    attach_snap_timeleft -= delta
    var target_xform: = attach_target.global_transform
    attach_tentacles_to_target(target_xform, 1.0)
    if attach_snap_timeleft <= 0.0:
        fully_attached()
        global_transform = target_xform
        return
    
    var progress: float = 1.0 - (attach_snap_timeleft / attach_snap_time)
    var target_basis: = attach_target.global_basis
    target_basis = target_basis.orthonormalized()
    global_basis = lerp(global_basis, target_basis, ease(progress, attach_orientation_ease))
    var lerped_pos: Vector3 = lerp(snapping_from_global_pos, target_xform.origin, ease(progress, attach_snap_ease))
    var diff_wanted: = lerped_pos - global_position
    velocity = diff_wanted / delta
    #global_transform = global_transform.interpolate_with(target_xform, ease(progress, attach_snap_ease))

func attach_tentacles_to_target(target_xform: Transform3D, tentacle_ratio: float) -> void:
    var tentacle_count: int = floori(tentacle_extended.size() * tentacle_ratio)
    for i in min(tentacle_count + 1, tentacle_extended.size()):
        var tentacle: MeshInstance3D = tentacle_root.get_child(i)
        if i < tentacle_count:
            tentacle_extended[i] = true
            var tenta_local: = tentacle.global_position - global_position
            print("now attaching ", i, " ", target_xform.origin + tenta_local)
            tentacle.set_instance_shader_parameter("tentatarget", target_xform.origin + tenta_local)
        else:
            print("now detaching ", i)
            tentacle_extended[i] = false

func fully_attached() -> void:
    is_fully_attached = true
    look_vec = global_basis.y
    look_vec.y = 0.0
    look_vec = look_vec.normalized()
    for i in tentacle_extended.size():
        var tentacle: MeshInstance3D = tentacle_root.get_child(i)
        tentacle.set_instance_shader_parameter("extended", 0.0)
        tentacle_extended[i] = false

func _physics_process(delta: float) -> void:
    if hold:
        return
    
    # Add the gravity.
    detect_floor()
    if is_attaching and not is_fully_attached:
        attach_float_update(delta)
    elif is_fully_attached:
        if not attach_target:
            break_off_attach()
    elif not is_above_floor:
        velocity += get_gravity() * delta
    elif velocity.y < (jump_impulse_strength * 0.2):
        var target_y_vel := 0.0
        if cur_floor_distance < floor_target_distance:
            target_y_vel = raise_speed
        else:
            target_y_vel = get_gravity().y * 0.2
        velocity.y = lerp(velocity.y, target_y_vel, delta * raise_interp)

    if not is_attaching:
        velocity = regular_movement(delta)
    else:
        var vel: = velocity
        vel.y = 0.0
        vel *= 0.9
        vel.y = velocity.y
        velocity = vel

    if not is_fully_attached:
        move_and_slide()
    
    attach_check()

func regular_movement(delta: float) -> Vector3:
    var current_vel := velocity

    var input_dir := Input.get_vector("left", "right", "forward", "back")
    var camera_forward: = Vector3.FORWARD
    if camera_node:
        camera_forward = -camera_node.global_basis.z
        camera_forward.y = 0.0
    var direction := (Basis.looking_at(camera_forward, Vector3.UP) * Vector3(input_dir.x, 0, input_dir.y)).normalized()

    var y_vel := current_vel.y
    current_vel.y = 0

    if direction:
        current_vel = lerp(current_vel, direction * movement_speed, delta * movement_interp)
        
        global_basis = lerp(global_basis, Basis.looking_at(direction, Vector3.UP), delta * facing_interp)
    else:
        current_vel *= drag_factor
    
    if current_vel.length_squared() > 0.001:
        look_vec = current_vel.normalized()

    current_vel.y = y_vel
    return current_vel

func attach_check() -> void:
    if is_attaching:
        if not attach_target:
            print_debug("No attach target found, breaking off attach")
            break_off_attach()
            return
        var dist_to_target: float = to_local(attach_target.global_position).length()
        if dist_to_target > (attach_dist * 1.3):
            print_debug("Breaking off attach, target is too far away")
            attach_target = null
            break_off_attach()
        return

    var all_attachables: Array[Node] = get_tree().get_nodes_in_group("attachable")
    var target_dist_sq: float = attach_dist * attach_dist
    for attachable in all_attachables:
        if not attachable is Node3D:
            print_debug("Attachable ", attachable.get_path(), " is not a Node3D, skipping")
            continue
        var dist_sq: float = to_local(attachable.global_position).length_squared()
        if dist_sq > target_dist_sq:
            if attachable in attach_blacklist and to_local(attachable.global_position).length() > (attach_dist * 1.5):
                print("removing from blacklist")
                attach_blacklist.erase(attachable)
            continue
        elif attachable in attach_blacklist:
            continue
        start_attaching(attachable)
        if is_attaching:
            break

func break_off_attach() -> void:
    is_attaching = false
    is_fully_attached = false
    attach_target = null
    
    if not is_lerping_to_horiz:
        lerp_to_horiz_timeleft = lerp_to_horiz_time
        is_lerping_to_horiz = true

func start_attaching(attachable: Node3D) -> void:
    print_debug("Starting to attach to ", attachable.get_path())
    attach_blacklist.append(attachable)
    attach_target = attachable.get_node_or_null("AttachPoint")
    if not attach_target:
        print_debug("No attach point found for attachable ", attachable.name, " removing from attachable group")
        attachable.remove_from_group("attachable")
    else:
        is_attaching = true
        attach_f_timeleft = attach_float_time
    

func _process(delta: float) -> void:
    if Input.is_action_just_pressed("quit"):
        get_tree().quit()
    if Input.is_action_just_pressed("restart") or global_position.y < -18:
        get_tree().reload_current_scene()

    if jump_delay_timeleft > 0.0:
        jump_delay_timeleft -= delta
    update_face_forward()

    if not is_attaching:
        process_tentacles(delta)
    else:
        interp_tentacles(delta)
    was_above_floor = is_above_floor
    
    if is_lerping_to_horiz:
        if is_attaching:
            is_lerping_to_horiz = false
        else:
            lerp_to_horiz_timeleft -= delta
            var progress: float = 1.0 - (lerp_to_horiz_timeleft / lerp_to_horiz_time)
            if lerp_to_horiz_timeleft <= 0.0:
                progress = 1.0
                is_lerping_to_horiz = false
            var forward_vec: = -global_basis.z
            forward_vec.y = 0.0
            if forward_vec.length_squared() == 0:
                forward_vec = global_basis.y
                forward_vec.y = 0.0
            var target_basis: = Basis.looking_at(forward_vec, Vector3.UP)
            target_basis = target_basis.orthonormalized()
            global_basis = lerp(global_basis, target_basis, progress)
    
    if Input.is_action_just_pressed("action"):
        #hold = not hold
        if is_fully_attached:
            attach_pop_off()
        elif jumpable():
            jump()
    
    if is_fully_attached:
        global_transform = attach_target.global_transform
        if bike_anim_player and Input.is_action_just_pressed("forward"):
            if not anim_played:
                bike_anim_player.play("bike_move")
                anim_played = true

func jump() -> void:
    velocity.y = jump_impulse_strength
    jump_delay_timeleft = jump_min_delay

func jumpable() -> bool:
    if jump_delay_timeleft > 0.0:
        return false
    var is_floor: = is_above_floor or was_above_floor
    var floor_dist: float = min(cur_floor_distance, was_floor_distance)
    return is_floor and floor_dist < (floor_target_distance + 0.4)

func attach_pop_off() -> void:
    break_off_attach()
    velocity = Vector3.ZERO
    var forward_vec: = global_basis.y
    forward_vec.y = 0.0
    if forward_vec.length_squared() == 0:
        forward_vec = -global_basis.z
        forward_vec.y = 0.0
    forward_vec = forward_vec.normalized()
    var sideways_vec: = forward_vec.cross(Vector3.UP)
    var pop_vec: = forward_vec.rotated(sideways_vec, detach_impulse_up_angle)
    
    velocity = pop_vec * detach_impulse_strength


func update_face_forward() -> void:
    var forward_vec: = -global_basis.z
    forward_vec.y = 0.0
    if forward_vec.length_squared() == 0:
        if velocity.x > 0 or velocity.z > 0:
            forward_vec = velocity
            forward_vec.y = 0.0
        else:
            forward_vec = Vector3.FORWARD
    only_face_forward.global_basis = Basis.looking_at(forward_vec, Vector3.UP)

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
        if tentacle_extended[i]:
            var local_tip_pos: Vector3 = to_local(tentacle.get_instance_shader_parameter("tentatarget"))
            if local_tip_pos.length() > max_tentacle_dist:
                try_extend_next_tentacle()
                tentacle_extended[i] = false
    interp_tentacles(delta)
    
func interp_tentacles(delta: float) -> void:
    for i in tentacle_extended.size():
        var tentacle: MeshInstance3D = tentacle_root.get_child(i)
        var cur_extent: float = tentacle.get_instance_shader_parameter("extended")
        if not tentacle_extended[i]:
            if cur_extent > 0.001:
                tentacle.set_instance_shader_parameter("extended", extend_lerp(cur_extent, 0.0, delta))
        else:
            tentacle.set_instance_shader_parameter("extended", extend_lerp(cur_extent, 1.0, delta))

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

func get_look_vec() -> Vector3:
    return look_vec