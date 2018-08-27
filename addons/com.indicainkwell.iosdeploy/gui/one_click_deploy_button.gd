# one_click_deploy_button.gd
tool
extends Button


signal presenting_hover_menu(this)
signal settings_button_pressed(this)
signal devices_list_edited(this)


const stc = preload('../scripts/static.gd')

# ------------------------------------------------------------------------------
#                                    Mouse Hover
# ------------------------------------------------------------------------------

# Godotv2 InputEventMouseMotion Constant
const MOUSE_MOTION = 2

# Create timers in script to save time from having to set timeout in both Godot
# v2 and v3 editor.
# Start enter timer when mouse enters self
var _hover_enter_timer
# Start exit timer after hover panel is shown and mouse no longer hovers them
var _hover_exit_timer


func _ready():
	_hover_enter_timer = Timer.new()
	_hover_enter_timer.set_one_shot(true)
	_hover_enter_timer.set_wait_time(0.75)
	_hover_enter_timer.connect('timeout', self, '_on_hover_enter_timer_timeout')

	_hover_exit_timer = Timer.new()
	_hover_exit_timer.set_one_shot(true)
	_hover_exit_timer.set_wait_time(0.25)
	_hover_exit_timer.connect('timeout', self, '_on_hover_exit_timer_timeout')

	add_child(_hover_enter_timer)
	add_child(_hover_exit_timer)

	set_process_input(false)


func _on_mouse_entered():
	"""
	Connect to mouse entered to save processing time that would be spent in
	_input() by kicking off the hover enter timer and process_input() here
	and turning it off when not hovering anymore.
	"""
	if is_processing_input():
		return
	_hover_enter_timer.start()
	set_process_input(true)


func _input(event):
	var event_is_InputEventMouseMotion
	if stc.get_version().is2():
		event_is_InputEventMouseMotion = event.type == MOUSE_MOTION
	else:
		event_is_InputEventMouseMotion = event.get_class() == 'InputEventMouseMotion'
	
	if event_is_InputEventMouseMotion:
		var event_pos
		if stc.get_version().is2():
			event_pos = event.pos
		else:
			event_pos = event.position

		# - When mouse is NOT hovering self and hp is hidden stop enter
		# timer
		# - When mouse is hovering self or hp stop exit timer
		# - When mouse is NOT hovering self or hp and hp is visible then
		# start exit timer
		var hp = get_node('hover_panel')
		var hp_hidden = check_is_hidden(hp)

		# grow self rect because tool buttons border is larger then rect
		# and will highlight when rect does not have point
		var self_has_point = get_rect().grow(4.0).has_point(event_pos)
		var hp_has_point

		if hp_hidden:
			if not self_has_point:
				_hover_enter_timer.stop()
				set_process_input(false)
		else:
			hp_has_point = hp.get_rect().has_point(event_pos)
			if self_has_point or hp_has_point:
				_hover_exit_timer.stop()
			else:
				_hover_exit_timer.start()


func _on_hover_enter_timer_timeout():
	emit_signal('presenting_hover_menu', self)

	var hover_panel = get_node('hover_panel')
	hover_panel.set_as_toplevel(true)
	_place_panel(hover_panel)
	hover_panel.show()


func _on_hover_exit_timer_timeout():
	set_process_input(false)
	get_node('hover_panel').hide()


func get_devices_list():
	return get_node("hover_panel/devices_group/devices_list")


func devices_list_populate(devices):
	get_devices_list().populate(devices)


func devices_list_set_active(devices):
	get_devices_list().set_active(devices)


func _on_devices_list_item_edited():
	emit_signal("devices_list_edited", self)



func check_is_hidden(canvas_item):
	if stc.get_version().is2():
		return canvas_item.is_hidden()
	else:
		return not canvas_item.is_visible()


func _place_panel(panel):
	# have panel popup to the left of button so it isn't clipped
	# offscreen.
	if stc.get_version().is2():
		var newpos = get_global_pos()
		newpos.x -= panel.get_size().x - get_size().x
		newpos.y = panel.get_pos().y
		panel.set_pos(newpos)
	else:
		var newpos = self.rect_global_position
		newpos.x -= panel.rect_size.x - self.rect_size.x
		newpos.y = panel.rect_position.y
		panel.rect_position = newpos


func update_build_progress(percent, status=null, finished=false):
	var tween = get_node('build_progress_tweener')
	var bar = get_node('build_progress_bar')
	bar.share(get_node('hover_panel/build_progress_bar'))

	if status != null:
		set_build_status(status)

	tween.stop_all()
	if finished:
		bar.set_value(0.0)
		bar.hide()
	else:
		tween.interpolate_method(bar, 'set_value', bar.get_value(), percent * 100.0, 0.5, 0, 0)
		tween.start()


func set_build_status(status):
	get_node('hover_panel/build_progress_bar/HBoxContainer/build_status').set_text(status)


func set_project_valid(valid):
	get_node('hover_panel/HBoxContainer/project_valid').set_pressed(valid)


func _draw_build_progress_overlay():
	var bar = get_node('build_progress_bar')

	var r = get_rect()
	if stc.get_version().is2():
		r.size.x *= bar.get_unit_value()
		r.pos = Vector2()
	else:
		r.size.x *= bar.ratio
		r.position = Vector2()

	var c = ColorN('white')
	c.a = 0.4
	draw_rect(r, c)


func _draw():
	_draw_build_progress_overlay()


func _on_build_progress_bar_changed():
	update()


func _on_settings_button_pressed():
	emit_signal('settings_button_pressed', self)
