extends VoxelTerrain
class_name Terrian

const AIR_TYPE := 0

var light_ = preload("res://scenes/other/block_light.tscn")
var sound_ = preload("res://scenes/other/block_sound.tscn")
var voxel_tool:VoxelTool
var plants:Array[int]
var _dirs: Array[Vector3] = [
	Vector3(-1, 0, 0),
	Vector3(1, 0, 0),
	Vector3(0, 0, -1),
	Vector3(0, 0, 1),
	Vector3(-1, 0, -1),
	Vector3(1, 0, -1),
	Vector3(-1, 0, 1),
	Vector3(1, 0, 1),
	
	Vector3(-1, 1, 0),
	Vector3(1, 1, 0),
	Vector3(0, 1, -1),
	Vector3(0, 1, 1),
	Vector3(-1, 1, -1),
	Vector3(1, 1, -1),
	Vector3(-1, 1, 1),
	Vector3(1, 1, 1),

	Vector3(-1, -1, 0),
	Vector3(1, -1, 0),
	Vector3(0, -1, -1),
	Vector3(0, -1, 1),
	Vector3(-1, -1, -1),
	Vector3(1, -1, -1),
	Vector3(-1, -1, 1),
	Vector3(1, -1, 1)
]

@export var item_library:ItemsLibrary

func _ready() -> void:
	voxel_tool = get_voxel_tool()
	plants = [mesher.library.get_model_index_default("tall_grass"),mesher.library.get_model_index_default("fern"),mesher.library.get_model_index_default("flower"),mesher.library.get_model_index_default("reeds"),mesher.library.get_model_index_default("tall_flower"),mesher.library.get_model_index_default("wheat"),mesher.library.get_model_index_default("wheat_seed")]

@rpc("reliable","call_local","any_peer")
func _place_block_server(type: StringName, voxel_position: Vector3, player_pos: Vector3 = Vector3.ZERO) -> void:
	#print("place",type)
	var item = item_library.get_item(type)
	if item:
		if item.utility:
			if item.utility.portal:
				#Globals.create_portal.emit(position)
				#open_portal_ui.rpc_id(multiplayer.get_remote_sender_id(),position)
				pass
	
	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	
	if item.light:
		spawn_light.rpc(voxel_position,item.light_colour,item.light_energy,item.light_size)
	
	if item.has_sound:
		spawn_sound.rpc(voxel_position,item.sound.get_path())
	
	if item.rotatable:
		## make the block rotation towards the player when placed
		voxel_tool.value = mesher.library.get_model_index_single_attribute(type,get_direction(player_pos,voxel_position))
	else:
		voxel_tool.value = mesher.library.get_model_index_default(type)
	
	voxel_tool.do_point(voxel_position)
	
	
@rpc("reliable","call_local","any_peer")
func _break_block_server(voxel_position: Vector3) -> void:
	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	voxel_tool.value = AIR_TYPE
	
	#print("break")
	var above_voxel:int = voxel_tool.get_voxel(voxel_position + Vector3(0,1,0))
	
	var voxel: int = voxel_tool.get_voxel(voxel_position)
	
	if plants.has(above_voxel):
		voxel_tool.do_point(voxel_position + Vector3(0,1,0))
		
	voxel_tool.do_point(voxel_position)
	
	var array = mesher.library.get_type_name_and_attributes_from_model_index(voxel)
	
	if array[0] != "air":
		var item = item_library.get_item(array[0])
		
		# if no other drop items drop itself
		if item.drop_items.is_empty():
			send_item.rpc_id(multiplayer.get_remote_sender_id(),array[0])
			
		# can drop other items not only it self
		for drop_item in item.drop_items:
			send_item.rpc_id(multiplayer.get_remote_sender_id(),drop_item)
		
		if item.light:
			destory_light.rpc(voxel_position)
			
		if item.has_sound:
			destory_sound.rpc(voxel_position)
		
		Helper.sound_manager.play_sound.rpc(array[0],voxel_position,"break")
		
		if item.utility != null:
			if item.utility.has_ui:
				voxel_tool.set_voxel_metadata(voxel_position,null)
				
			elif item.utility.portal:
				Globals.remove_portal_data.emit(voxel_position)
				
			elif item.utility.spawn_point:
				#remove_spawn_point.rpc(position)
				pass
				
	for di in len(_dirs):
		var npos := voxel_position + _dirs[di]
		var nv := voxel_tool.get_voxel(npos)
		if water(nv):
			var water_m = get_tree().get_first_node_in_group("Water Updater")
			water_m.schedule(npos)
		
@rpc("any_peer","call_local")
func spawn_light(voxel_position: Vector3,color:Color,energy:float, size:float = 5.0) -> void:
	var light = light_.instantiate()
	light.position = voxel_position + Vector3(0.5,0.5,0.5)
	light.light_color = color
	light.light_energy = energy
	light.light_size = size
	var light_container = Helper.light_container
	light_container.add_child(light)

@rpc("any_peer","call_local")
func destory_light(voxel_position:Vector3):
	var find_pos = voxel_position + Vector3(0.5,0.5,0.5)
	var light_container = Helper.light_container
	for light in light_container.get_children():
		print("light check for ",find_pos, "light pos ",light.global_position)
		if light.global_position == find_pos:
			light.queue_free()

@rpc("any_peer","call_local")
func destory_sound(voxel_position:Vector3):
	var find_pos = voxel_position
	var sound_container = Helper.sound_container
	for sound in sound_container.get_children():
		if sound.position == find_pos:
			sound.queue_free()

@rpc("any_peer","call_local")
func spawn_sound(voxel_position:Vector3, sound:String) -> void:
	var _sound = sound_.instantiate() as AudioStreamPlayer3D
	_sound.stream = load(sound)
	_sound.position = voxel_position 
	var sound_container = Helper.sound_container
	sound_container.add_child(_sound)
	
func get_direction(player_pos:Vector3, place_pos:Vector3):
	var dir = place_pos.direction_to(player_pos)
	#print(dir)
	
	if round(dir).x != 0:
		if round(dir).x == 1:
			return VoxelBlockyAttributeDirection.DIR_NEGATIVE_X
		else:
			return VoxelBlockyAttributeDirection.DIR_POSITIVE_X
			
	elif round(dir).z != 0:
		if round(dir).z == 1:
			return VoxelBlockyAttributeDirection.DIR_NEGATIVE_Z
		else:
			return VoxelBlockyAttributeDirection.DIR_POSITIVE_Z

@rpc("any_peer","call_remote","reliable")
func send_item(type: StringName) -> void:
	var slot_manager = Helper.slot_manager
	## if the player is holding a tool it will be damaged
	if slot_manager.selected_slot != null:
		if slot_manager.selected_slot.item != null:
			if slot_manager.selected_slot.item is ItemTool:
				slot_manager.selected_slot.used()
						
	## gives the broken item to the player
	var item = item_library.get_item(type)
	if item:
	#Globals.spawn_item_inventory.emit(item)
		slot_manager.add_item_to_hotbar_or_inventory(item)

func water(v:int):
	var _is_water:bool = false
	if v == mesher.library.get_model_index_default("water_full"):
		_is_water = true
	if v ==  mesher.library.get_model_index_default("water_top"):
		_is_water = true
	return _is_water

@rpc("any_peer","call_local","reliable")
func get_voxel_meta(voxel_position:Vector3,caller_path):
	var caller = get_tree().root.get_node(caller_path)
	if caller:
		var meta = voxel_tool.get_voxel_metadata(voxel_position)
		#print("meta ", meta)
		#callable.call()
		caller.rpc_id(multiplayer.get_remote_sender_id(),"receive_meta",meta,voxel_tool.get_voxel(voxel_position),voxel_position)
