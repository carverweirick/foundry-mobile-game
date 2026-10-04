class_name UiText

## Godot's built-in tooltip never wraps, so a sentence-long tooltip became
## one line wider than the screen when hovered on desktop (user report,
## 2026-10-03). tip() breaks text at word boundaries so no line exceeds
## max_chars; existing line breaks are kept. Phones never show tooltips
## (no hover), so this is for desktop testing.
const TOOLTIP_LINE_CHARS: int = 44


static func tip(text: String, max_chars: int = TOOLTIP_LINE_CHARS) -> String:
	var out: PackedStringArray = []
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			if line != "" and line.length() + 1 + word.length() > max_chars:
				out.append(line)
				line = word
			else:
				line = word if line == "" else line + " " + word
		out.append(line)
	return "\n".join(out)
