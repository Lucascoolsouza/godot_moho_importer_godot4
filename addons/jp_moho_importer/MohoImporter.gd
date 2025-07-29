@tool
# Importer for Moho project animations. It handles import options and resource saving. Convertions
# and scene initialization is handled by a MohoProjectHelper node, created for each source file.
extends EditorImportPlugin

### Member Variables and Dependencies -------------------------------------------------------------
#--- signals --------------------------------------------------------------------------------------

#--- enums ----------------------------------------------------------------------------------------

enum Presets { DEFAULT, NPC }

#--- constants ------------------------------------------------------------------------------------

const MohoSkeletonBaseScene = preload("res://addons/jp_moho_importer/components/MohoSkeletonBaseScene.tscn")

#--- public variables - order: export > normal var > onready --------------------------------------

var editor_plugin : EditorPlugin

#--- private variables - order: export > normal var > onready -------------------------------------

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _get_importer_name() -> String:
	return "jp_moho_importer"


func _get_visible_name() -> String:
	return "Moho Animation"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["mohoproj"])


func _get_save_extension() -> String:
	return ""


func _get_resource_type() -> String:
	return "PackedScene"


func _get_preset_count() -> int:
	return Presets.size()


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_preset_name(preset: int) -> String:
	var preset_name: = "Unknown"
	
	match preset:
		Presets.DEFAULT:
			preset_name = "Default"
		Presets.NPC:
			preset_name = "Aliquest NPC"
	
	return preset_name


func get_import_options(preset: int) -> Array:
	var options: = []
	var preset_name = _get_preset_name(preset)
	options.append_array(_get_import_options(preset_name, preset))
	return options


func get_option_visibility(option: String, options: Dictionary) -> bool:
	return true


func _import(
		source_file: String, 
		save_path: String, 
		options: Dictionary, 
		platform_variants: Array, 
		gen_files: Array
) -> int:
	var success: int = OK
	
	# Read and validate source file
	var file := FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		push_error("Couldn't open file at: %s" % source_file)
		return ERR_CANT_OPEN
	
	var test_json_conv = JSON.new()
	test_json_conv.parse(file.get_as_text())
	var project_info = test_json_conv.get_data()
	success = _validate_project_info(project_info)
	if success != OK:
		push_error("Error %s | File is invalid: %s"%[success, source_file])
		return success
	
	if options.image_folder.is_empty():
		options.image_folder = _get_images_folder(source_file)
	options.source_file = source_file
	
	# Initialize MohoProjectHelper
	var project_helper := MohoProjectHelper.new()
	editor_plugin.add_helper(project_helper, options.verbose)
	project_helper.initialize(project_info, options)
	
	# Create scene
	var skeleton_scene_instance = MohoSkeletonBaseScene.instantiate()
	skeleton_scene_instance.name = MohoProjectHelper.get_proper_file_name(source_file)
	project_helper.initialize_scene(skeleton_scene_instance)
	
	var mask_files := project_helper.set_images_from_folder()
	gen_files.append_array(mask_files)
	
	# Save shapes as curves
	if options.save_shapes_as_curves:
		var curves_folder = _get_curves_folder(source_file)
		var directory := DirAccess.open(curves_folder)
		if directory == null:
			DirAccess.make_dir_recursive_absolute(curves_folder)
		
		for s_idx in project_helper.sprites.size():
			var sprite : MohoSprite = project_helper.sprites[s_idx]
			var curves : Array = sprite.get_shapes_as_curves()
			for c_idx in curves.size():
				var curve : Curve2D = curves[c_idx]
				var curve_path = _get_curve_path(source_file, sprite.name, c_idx)
				var curve_resource: Resource = curve
				ResourceSaver.save(curve_resource, curve_path)
				gen_files.append(curve_path)
				print("Saved curve at: %s" % [curve_path])
	
	# Save animations
	var animator : AnimationPlayer = skeleton_scene_instance.get_node("AnimationPlayer")
	for animation_name in animator.get_animation_list():
		var animation = animator.get_animation(animation_name)
		var animation_path = _get_animation_path(source_file, animation_name)
		ResourceSaver.save(animation, animation_path)
		animation.take_over_path(animation_path)
		gen_files.append(animation_path)
		print("Saved animation at: %s" % [animation_path])
	
	# Pack and save scene
	var skeleton_scene = PackedScene.new()
	skeleton_scene.pack(skeleton_scene_instance)
	var scene_path = MohoProjectHelper.get_default_file_path(source_file, "tscn")
	ResourceSaver.save(skeleton_scene, scene_path)
	gen_files.append(scene_path)
	print("Saved rig scene at: %s" % [scene_path])
	
	editor_plugin.remove_helper(project_helper, options.verbose)
	project_helper = null
	
	return success

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _validate_project_info(value) -> int:
	var is_valid = (
		OK
		if value is Dictionary
		else FAILED
	)
	return is_valid


func _get_skeleton_node(main_scene: Node2D) -> Skeleton2D:
	var skeleton_node : Skeleton2D
	
	var main_skeleton : Skeleton2D = main_scene.get_node_or_null("Skeleton2D")
	if main_skeleton == null or main_skeleton.get_child_count() > 0:
		var new_skeleton_node = Skeleton2D.new()
		main_scene.add_child(new_skeleton_node)
		new_skeleton_node.owner = main_scene
		skeleton_node = new_skeleton_node
	else:
		skeleton_node = main_skeleton
	
	return skeleton_node


func _get_animation_path(moho_file_path: String, animation_name: String) -> String:
	var animation_path = "%s/%s_anim.tres" % [
		moho_file_path.get_base_dir(),
		animation_name.to_lower()
	]
	return animation_path


func _get_curve_path(moho_file_path: String, sprite_name: String, curve_idx: int) -> String:
	var curve_path = "%s%s_curve_%02d.tres" % [
		_get_curves_folder(moho_file_path),
		sprite_name.to_lower().replace(" ", "_"),
		curve_idx
	]
	return curve_path


func _get_images_folder(moho_file_path: String) -> String:
	return moho_file_path.get_base_dir() + "/images/"


func _get_curves_folder(moho_file_path: String) -> String:
	return moho_file_path.get_base_dir() + "/curves/"


func _get_import_options(preset: String, preset_index: int) -> Array[Dictionary]:
	# You can use the preset or preset_index to customize options if needed
	return [
		{
			"name": "loop_animation",
			"default_value": false,
			"property_hint": PROPERTY_HINT_NONE,
			"hint_string": "bool",
		},
		{
			"name": "image_folder",
			"default_value": "",
			"property_hint": PROPERTY_HINT_DIR,
		},
		{
			"name": "mask_layer",
			"default_value": 1,
			"property_hint": PROPERTY_HINT_LAYERS_2D_RENDER,
		},
		{
			"name": "ik_preference",
			"default_value": "None",
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "None,Clockwise,Counter_Clockwise"
		},
		{
			"name": "save_shapes_as_curves",
			"default_value": false,
			"property_hint": PROPERTY_HINT_NONE,
			"hint_string": "bool",
		},
		{
			"name": "verbose",
			"default_value": false,
			"property_hint": PROPERTY_HINT_NONE,
			"hint_string": "bool",
		},
	]

### -----------------------------------------------------------------------------------------------
