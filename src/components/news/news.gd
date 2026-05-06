class_name NewsControl
extends VBoxContainer

const ROUNDED_THUMB_SHADER := preload("res://src/components/news/rounded_thumbnail.gdshader")

const HOUR = 60 * 60
const NEWS_CACHE_LIFETIME_SEC = 12 * HOUR

@onready var _refresh_button := %RefreshButton as Button
@onready var _news_list := %NewsList as VBoxContainer
@onready var _search_box := %SearchBox as LineEdit

var _http_request: HTTPRequest
var _downloading := false
var _data_loaded := false

func _init() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)


func _ready() -> void:
	_refresh_button.icon = get_theme_icon("Reload", "EditorIcons")
	_refresh_button.flat = true
	_refresh_button.text = ""
	_refresh_button.tooltip_text = tr("Refresh News")
	_refresh_button.pressed.connect(func() -> void:
		_update_cache(true)
	)
	
	_search_box.right_icon = get_theme_icon("Search", "EditorIcons")
	_search_box.text_changed.connect(_on_search_changed)


func _notification(what: int) -> void:
	if NOTIFICATION_VISIBILITY_CHANGED == what:
		if visible and not _data_loaded:
			_check_for_updates()
	elif NOTIFICATION_APPLICATION_FOCUS_IN == what:
		if visible:
			_check_for_updates()


func _check_for_updates() -> void:
	if _downloading: 
		return
	var last_checked_unix:int = Cache.get_value("news_feed", "last_checked", 0)
	if int(Time.get_unix_time_from_system()) - last_checked_unix > NEWS_CACHE_LIFETIME_SEC:
		await _update_cache()
	else:
		_load_from_cache()


func _update_cache(force:=false) -> void:
	if _downloading:
		return
	_downloading = true
	_refresh_button.disabled = true
	var response := await _http_get("https://godotengine.org/rss.xml")
	_downloading = false
	_refresh_button.disabled = false
	
	if response[1] != 200:
		return
		
	var body := XML.parse_buffer(response[3] as PackedByteArray)
	var items := []
	
	var all_items := exml.smart(body.root).o.children
	for child: XMLNode in all_items:
		if child.name == "channel":
			for channel_child: XMLNode in child.children:
				if channel_child.name == "item":
					var item_smart := exml.smart(channel_child)
					var title := item_smart.find_smart_child_recursive(exml.Filters.by_name("title"))
					var link := item_smart.find_smart_child_recursive(exml.Filters.by_name("link"))
					var pub_date := item_smart.find_smart_child_recursive(exml.Filters.by_name("pubDate"))
					var image := item_smart.find_smart_child_recursive(exml.Filters.by_name("image"))
					
					if title and link:
						items.append({
							"title": title.o.content,
							"link": link.o.content,
							"pub_date": pub_date.o.content if pub_date else "",
							"image": image.o.content if image else ""
						})
	
	if len(items) > 0:
		Cache.set_value("news_feed", "items", items)
		Cache.set_value("news_feed", "last_checked", int(Time.get_unix_time_from_system()))
		Cache.save()
		_load_from_cache()


func _load_from_cache() -> void:
	for child: Node in _news_list.get_children():
		child.queue_free()
		
	var items: Array = Cache.get_value("news_feed", "items", [])
	
	for item: Dictionary in items:
		var btn := LinkButton.new()
		var title: String = item.get("title", "Unknown")
		var pub_date: String = item.get("pub_date", "")
		var image_url: String = item.get("image", "")
		
		if pub_date:
			btn.text = "%s - %s" % [title, pub_date.substr(0, 16)]
		else:
			btn.text = title
			
		btn.uri = item.get("link", "")
		btn.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		btn.add_theme_font_override("font", get_theme_font("main_button_font", "EditorFonts"))
		btn.add_theme_font_size_override("font_size", get_theme_font_size("main_button_font_size", "EditorFonts") + 2)
		
		var panel := PanelContainer.new()
		panel.set_meta("search_text", title.to_lower())
		panel.add_theme_stylebox_override("panel", get_theme_stylebox("panel", "Tree"))
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		
		var texture_rect: TextureRect
		
		if image_url:
			texture_rect = TextureRect.new()
			texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			texture_rect.custom_minimum_size = Vector2(200, 112)
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_configure_news_thumbnail(texture_rect)
			hbox.add_child(texture_rect)
			
		hbox.add_child(btn)
		margin.add_child(hbox)
		panel.add_child(margin)
		_news_list.add_child(panel)
		
		if texture_rect and image_url:
			_download_image(image_url, texture_rect)
			call_deferred("_sync_news_thumbnail_shader", texture_rect)
			
	_data_loaded = true
	_on_search_changed(_search_box.text)


func _on_search_changed(query: String) -> void:
	var q := query.to_lower()
	for child in _news_list.get_children():
		var panel := child as PanelContainer
		if not panel:
			continue
		var search_text: String = panel.get_meta("search_text", "")
		panel.visible = q.is_empty() or search_text.contains(q)


func _download_image(url: String, rect: TextureRect) -> void:
	var http := HTTPRequest.new()
	rect.add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var img := Image.new()
			var err := ERR_CANT_RESOLVE
			var lower_url := url.to_lower()
			if lower_url.ends_with(".png"):
				err = img.load_png_from_buffer(body)
			elif lower_url.ends_with(".jpg") or lower_url.ends_with(".jpeg"):
				err = img.load_jpg_from_buffer(body)
			elif lower_url.ends_with(".webp"):
				err = img.load_webp_from_buffer(body)
			else:
				# Fallback attempts
				if img.load_jpg_from_buffer(body) != OK:
					if img.load_png_from_buffer(body) != OK:
						img.load_webp_from_buffer(body)
						
			if not img.is_empty():
				rect.texture = ImageTexture.create_from_image(img)
				_sync_news_thumbnail_shader(rect)
		http.queue_free()
	)
	http.request(url, [Config.AGENT_HEADER])


func _configure_news_thumbnail(rect: TextureRect) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = ROUNDED_THUMB_SHADER
	rect.material = mat
	rect.resized.connect(func() -> void: _sync_news_thumbnail_shader(rect))


func _sync_news_thumbnail_shader(rect: TextureRect) -> void:
	var mat := rect.material as ShaderMaterial
	if mat == null:
		return
	var sz: Vector2 = rect.size
	if sz.x < 2.0 or sz.y < 2.0:
		return
	mat.set_shader_parameter("rect_size_px", sz)
	var r := 8.0 * float(Config.EDSCALE)
	var max_corner := minf(sz.x, sz.y) * 0.25
	mat.set_shader_parameter("corner_radius_px", clampf(r, 3.0, max_corner))


func _http_get(url: String, headers:=[]) -> Array:
	var default_headers := [Config.AGENT_HEADER]
	default_headers.append_array(headers)
	_http_request.request(url, default_headers, HTTPClient.METHOD_GET)
	var response: Array = await _http_request.request_completed
	return response
