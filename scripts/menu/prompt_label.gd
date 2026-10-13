class_name PromptLabel
extends Label
## A label whose text names buttons: each {action} in the template becomes that action's button
## (HudStyle.binding_text), and the text is redone when ButtonPrompts switches between keyboard
## and pad (card #45). Example: "press {menu_confirm} to join".

var template: String = "":
	set(value):
		template = value
		refresh()


func _init(template_text: String = "", font_size: int = 24, color: Color = HudStyle.TEXT) -> void:
	label_settings = HudStyle.label_settings(font_size, color)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	template = template_text


func _ready() -> void:
	ButtonPrompts.listen(refresh)


func refresh() -> void:
	text = PromptLabel.fill(template)


## The template with every {action} replaced by that action's button.
static func fill(template_text: String) -> String:
	var out := template_text
	var from := 0
	while true:
		var open := out.find("{", from)
		if open < 0:
			break
		var close := out.find("}", open)
		if close < 0:
			break
		var action := out.substr(open + 1, close - open - 1)
		var button := HudStyle.binding_text(StringName(action))
		out = out.substr(0, open) + button + out.substr(close + 1)
		from = open + button.length()
	return out
