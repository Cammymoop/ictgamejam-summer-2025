@tool
extends Marker3D

@export var enabled: bool = true
@export var mesh_node: MeshInstance3D
@export var material_slot: int = 0
@export var parameter_name: String = "tentatarget"

@onready var old_position: Vector3 = global_position

func _process(_delta: float) -> void:
    if not mesh_node or not Engine.is_editor_hint():
        if enabled:
            prints("disabling tool target", is_instance_valid(mesh_node), Engine.is_editor_hint())
            enabled = false
        return
    if not enabled:
        if is_instance_valid(mesh_node):
            old_position = global_position + Vector3.ONE
            enabled = true
        else:
            return
    if global_position == old_position:
        return

    old_position = global_position

    #var material: = mesh_node.get_surface_override_material(material_slot) as ShaderMaterial
    #if not material:
        #print("No shader material found for tool target")
        #enabled = false
        #return
    
    #material.set_shader_parameter(parameter_name, global_position)
    mesh_node.set_instance_shader_parameter(parameter_name, global_position)

    