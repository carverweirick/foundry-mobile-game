class_name MenuLayout

## Keeps menu scroll lists from jumping while the player is trying to tap
## (user report, 2026-10-03: "when text is updating and it wraps around to
## create a new line the menu's scroll will jump up and down causing the
## user to miss tap inputs"). Two separate causes, two tools - see CLAUDE.md
## UI rule 5:
##
## 1. watch(): a polled text change (a countdown, a status line) re-wraps a
##    Label onto one more or one fewer line, or a button's longer text makes
##    an HFlowContainer wrap differently, and every row below moves. Watched
##    controls may GROW but never SHRINK while they exist, so nothing can
##    oscillate under the player's finger. Applied to every autowrapping
##    Label and every FlowContainer inside a ScrollContainer, now and when
##    added later - menus get it without remembering to.
##
## 2. remove_and_free() / clear(): queue_free() doesn't take a node out of
##    its parent until the end of the frame, so a list rebuilt by
##    "queue_free the old rows, add new rows" holds BOTH for one frame - the
##    list's height spikes, then drops. Always detach first.


static func watch(root: Control) -> void:
	_apply_recursive(root)
	root.get_tree().node_added.connect(func(node: Node):
		if is_instance_valid(root) and root.is_ancestor_of(node):
			_apply(node))


static func remove_and_free(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


static func clear(list: Node) -> void:
	for child in list.get_children():
		remove_and_free(child)


static func _apply_recursive(node: Node) -> void:
	_apply(node)
	for child in node.get_children():
		_apply_recursive(child)


static func _apply(node: Node) -> void:
	var grows_with_text: bool = (node is Label and node.autowrap_mode != TextServer.AUTOWRAP_OFF) or node is FlowContainer
	if not grows_with_text or node.has_meta("_menu_layout_floor") or not _inside_scroll(node):
		return
	node.set_meta("_menu_layout_floor", true)
	var control: Control = node
	control.minimum_size_changed.connect(func():
		var needed := control.get_minimum_size().y
		if needed > control.custom_minimum_size.y:
			control.custom_minimum_size.y = needed)


static func _inside_scroll(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false
