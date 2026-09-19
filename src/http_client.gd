extends Node


const HttpUrlPrep = preload("res://src/services/http_url_prep.gd")

## Default request timeout in seconds. Without it a black-holed route (e.g.
## broken IPv6) leaves requests pending forever.
const DEFAULT_TIMEOUT := 30.0


func async_http_get(url: String, headers := PackedStringArray(), download_file:="") -> Array:
	var http_request := HTTPRequest.new()
	add_child(http_request)
	var response := await async_http_get_using(http_request, url, headers, download_file)
	http_request.queue_free()
	return response


func async_http_get_using(http_request: HTTPRequest, url: String, headers := PackedStringArray(), download_file:="") -> Array:
	url = url.strip_edges()
	var proxy_host := (Config.HTTP_PROXY_HOST.ret() as String).strip_edges()
	if not proxy_host.is_empty():
		http_request.set_http_proxy(
			proxy_host,
			Config.HTTP_PROXY_PORT.ret() as int
		)
		http_request.set_https_proxy(
			proxy_host,
			Config.HTTP_PROXY_PORT.ret() as int
		)
	var default_headers := PackedStringArray([Config.AGENT_HEADER])
	default_headers.append_array(headers)
	if download_file:
		http_request.download_file = download_file
	http_request.timeout = DEFAULT_TIMEOUT
	http_request.max_redirects = 0
	return await _get_following_redirects(
		http_request, url, default_headers, not proxy_host.is_empty()
	)


## GET with manual redirect following so every hop gets the IPv4 dialing fix.
## Auto-redirects (max_redirects > 0) would bypass it on the redirect target.
func _get_following_redirects(
	http_request: HTTPRequest, url: String, headers: PackedStringArray, skip_ipv4_rewrite: bool
) -> Array:
	var current_url := url
	var response: Array = []
	for i: int in range(HttpUrlPrep.MAX_REDIRECTS + 1):
		var request_url := current_url
		var request_headers := headers
		if not skip_ipv4_rewrite:
			var prepared := HttpUrlPrep.prepare(current_url, headers)
			request_url = prepared["url"]
			request_headers = prepared["headers"]
			var tls_host: String = prepared["tls_host"]
			if not tls_host.is_empty():
				http_request.set_tls_options(TLSOptions.client(null, tls_host))
			else:
				http_request.set_tls_options(TLSOptions.client())
		var err := http_request.request(request_url, request_headers, HTTPClient.METHOD_GET)
		if err != OK:
			return [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]
		response = await http_request.request_completed
		var next := HttpUrlPrep.redirect_target(response, current_url)
		if next.is_empty():
			return response
		current_url = next
	return response


class Response:
	var _resp: Array
	
	var result: int:
		get: return _resp[0]
	
	var code: int:
		get: return _resp[1]

	var headers: PackedStringArray:
		get: return _resp[2]

	var body: PackedByteArray:
		get: return _resp[3]

	func _init(resp: Array) -> void:
		_resp = resp
	
	func to_json(safe:=true) -> Variant:
		return utils.response_to_json(_resp, safe)
	
	func get_string_from_utf8() -> String:
		return body.get_string_from_utf8()
	
	func _to_string() -> String:
		return "[Response] Result: %s; Code: %s; Headers: %s" % [result, code, headers]
	
	func to_response_info(host: String, download_file:="") -> ResponseInfo:
		var error_text := ""
		var status := ""
		
		match result:
			HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH, HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
				error_text = tr("Connection error, prease try again.")
				status = tr("Can't connect")
			HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
				error_text = tr("Can't connect to host") + ": " + host
				status = tr("Can't connect")
			HTTPRequest.RESULT_NO_RESPONSE:
				error_text = tr("No response from host") + ": " + host
				status = tr("No response")
			HTTPRequest.RESULT_CANT_RESOLVE:
				error_text = tr("Can't resolve hostname") + ": " + host
				status = tr("Can't resolve.")
			HTTPRequest.RESULT_REQUEST_FAILED:
				error_text = tr("Request failed, return code") + ": " + str(code)
				status = tr("Request failed.")
			HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
				error_text = tr("Cannot save response to") + ": " + download_file
				status = tr("Write error.")
			HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
				error_text = tr("Request failed, too many redirects")
				status = tr("Redirect loop.")
			HTTPRequest.RESULT_TIMEOUT:
				error_text = tr("Request failed, timeout")
				status = tr("Timeout.")
			_:
				if code != 200:
					error_text = tr("Request failed, return code") + ": " + str(code)
					status = tr("Failed") + ": " + str(code)
		
		var info := ResponseInfo.new()
		info.error_text = error_text
		info.status = status
		return info


class ResponseInfo:
	var status: String
	var error_text: String
