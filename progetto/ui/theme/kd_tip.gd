class_name KDTip
extends PanelContainer
## A box whose tooltip is written in BBCode and shown as rich text: a title, two columns of reasons and
## numbers coloured by sign (Phase 18: the top bar said "Legname" and nothing else). The helpers below write
## the BBCode, so every tooltip of the interface reads the same way.

const GOOD := "#A6DF74"
const BAD := "#FF9A78"
const WARN := "#FFD79A"
const DIM := "#CDBF9E"
const HEAD := "#EFC96F"
const WIDTH := 320.0


func _make_custom_tooltip(for_text: String) -> Object:
	return rich(for_text)


## The label a rich tooltip is drawn with (the TooltipPanel of the theme frames it).
static func rich(bbcode: String, width: float = WIDTH) -> Control:
	if bbcode == "":
		return null
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(width, 0)
	rt.add_theme_font_override("normal_font", KDFonts.serif())
	rt.add_theme_font_override("bold_font", KDFonts.serif_bold())
	rt.add_theme_font_override("italics_font", KDFonts.serif_italic())
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_font_size_override("bold_font_size", 14)
	rt.add_theme_font_size_override("italics_font_size", 14)
	rt.add_theme_color_override("default_color", KDTheme.TEXT_LIGHT)
	rt.add_theme_constant_override("table_h_separation", 18)
	rt.text = bbcode
	# measured now, at its real width: left to itself the label learns its height a frame late and the frame
	# around it cut the last row (the total)
	rt.size = Vector2(width, 0)
	rt.custom_minimum_size.y = rt.get_content_height() + 4.0
	return rt


static func head(text: String) -> String:
	return "[font_size=16][color=%s][b]%s[/b][/color][/font_size]\n" % [HEAD, text]


static func sub(text: String) -> String:
	return "[color=%s]%s[/color]\n" % [DIM, text]


static func note(text: String) -> String:
	return "[i][color=%s]%s[/color][/i]\n" % [DIM, text]


static func colored(text: String, hex: String) -> String:
	return "[color=%s]%s[/color]" % [hex, text]


## A signed number, green when it helps and red when it hurts ("−" is a real minus sign).
static func signed(v: float, decimals: int = 0, good_when_positive: bool = true) -> String:
	var text := ("%+." + str(decimals) + "f") % v
	text = text.replace("-", "−")
	if absf(v) < pow(10.0, -decimals) * 0.5:
		return colored(text.replace("+", "±").replace("−", "±"), DIM)
	return colored(text, GOOD if (v > 0.0) == good_when_positive else BAD)


## Rows of [label, value text]; a row whose label starts with "=" is a total, in bold.
static func rows(list: Array) -> String:
	if list.is_empty():
		return ""
	var out := "[table=2]"
	for row: Array in list:
		var label := String(row[0])
		var value := String(row[1])
		if label.begins_with("="):
			out += "[cell][b]%s[/b][/cell][cell][b]%s[/b][/cell]" % [label.substr(1), value]
		else:
			out += "[cell]%s[/cell][cell]%s[/cell]" % [label, value]
	return out + "[/table]\n"

