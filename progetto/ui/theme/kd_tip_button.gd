class_name KDTipButton
extends Button
## A button whose tooltip is BBCode drawn as rich text (see KDTip).


func _make_custom_tooltip(for_text: String) -> Object:
	return KDTip.rich(for_text)

