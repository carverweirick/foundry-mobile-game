class_name TouchScroll

## Lets a touch drag that STARTS on a button inside a ScrollContainer scroll
## the list (user report, 2026-10-03: "I can't scroll over the contracts").
## A Button's default MOUSE_FILTER_STOP swallows the press, so the
## ScrollContainer behind it never sees the drag begin - on a phone, a list
## of rows full of buttons could only be scrolled from the gaps between
## them. PASS still lets the button take the tap, but the press also reaches
## the ScrollContainer. (The Contract Offers rows had the same bug with a
## tappable PanelContainer and got the same fix.)
##
## watch() applies this to every BaseButton under root that sits inside a
## ScrollContainer - now, and to any added later (list rows are built and
## rebuilt at runtime), so new menus get it without remembering to.


static func watch(root: Control) -> void:
	_apply_recursive(root)
	root.get_tree().node_added.connect(func(node: Node):
		if node is BaseButton and is_instance_valid(root) and root.is_ancestor_of(node):
			_apply(node))


static func _apply_recursive(node: Node) -> void:
	if node is BaseButton:
		_apply(node)
	for child in node.get_children():
		_apply_recursive(child)


## The press has to survive the WHOLE way up to the ScrollContainer: any
## STOP control in between (a row's PanelContainer box, by default) swallows
## it just as surely as the button would, so those are opened up too.
static func _apply(button: BaseButton) -> void:
	var path: Array[Control] = [button]
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			for control in path:
				if control.mouse_filter == Control.MOUSE_FILTER_STOP:
					control.mouse_filter = Control.MOUSE_FILTER_PASS
			return
		if parent is Control:
			path.append(parent)
		parent = parent.get_parent()
