class_name HttpRangeSource
extends RangeSource
## Reads byte ranges of a remote file with HTTP Range requests, following redirects
## like [AssetDownload] (GitHub release files redirect to a CDN).
##
## A server that answers a Range request with the whole file fails the read instead
## of downloading it: export template archives are over a gigabyte. Only
## [method async_download] gets the whole file, streamed to disk. A read or download
## that gets no data for [member stall_timeout_sec] (up to twice that) fails as timed
## out.


## Emitted when the running request completes or is canceled.
signal _request_done

## Error of a server that does not answer Range requests with 206 Partial Content,
## before translation (see [member RangeSource.Result.range_ignored]).
const NO_RANGE_ERROR := "the server does not support partial downloads"
## Default of [member stall_timeout_sec].
const STALL_TIMEOUT_SEC := 30.0
## Bytes read per frame, as requests are polled on the main thread.
const DOWNLOAD_CHUNK_SIZE := 1 << 20
## Bytes read per frame by [method async_download]: the Hub draws a frame every 100 ms
## in the background, which capped a download of a whole archive at 10 MB/s with
## [constant DOWNLOAD_CHUNK_SIZE].
const WHOLE_DOWNLOAD_CHUNK_SIZE := 8 << 20
## HttpUrlPrep constant.
const HttpUrlPrep = preload("res://src/services/http_url_prep.gd")

## Seconds a read may go without data before it fails.
var stall_timeout_sec := STALL_TIMEOUT_SEC

var _url: String
var _known_size: int
var _http: HTTPRequest
var _response: Array = []
var _cancelled := false
## Fails a read whose downloaded bytes stop growing.
var _watchdog: Timer
var _watched_bytes := -1
var _stalled := false


## Reads [param url] with [param http], which must be in the scene tree. A
## [param known_size] above 0 (e.g. from the GitHub release json) saves a request.
func _init(url: String, http: HTTPRequest, known_size := 0) -> void:
	_url = url.strip_edges()
	_known_size = known_size
	_http = http
	# Not threaded: cancel_request() waits for a threaded request's next chunk, which
	# froze the Hub on a stalled connection. A big chunk per frame (set per request)
	# keeps reads fast.
	_http.use_threads = false
	_http.max_redirects = 0
	# Byte ranges of the file as stored, not of a compressed answer.
	_http.accept_gzip = false
	_http.request_completed.connect(_on_request_completed)
	_watchdog = Timer.new()
	_watchdog.timeout.connect(_on_watchdog_timeout)
	_http.add_child(_watchdog)


func async_size() -> RangeSource.Result:
	if _known_size > 0:
		var result := RangeSource.Result.new()
		result.total_size = _known_size
		return result
	return await super()


func async_read(start: int, end: int, target_path := "") -> RangeSource.Result:
	var result := RangeSource.Result.new()
	# A 200 answer with the whole file declares its size up front and fails here,
	# before its body is read; redirect bodies are tiny.
	var response := await _async_request(
		PackedStringArray(["Range: bytes=%d-%d" % [start, end]]),
		maxi(end - start + 1, 64 * 1024),
		DOWNLOAD_CHUNK_SIZE,
		target_path,
		result,
	)
	if response.is_empty():
		return result

	var request_result := response[0] as int
	var code := response[1] as int
	if request_result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED or (
		request_result == HTTPRequest.RESULT_SUCCESS and code == HTTPClient.RESPONSE_OK
	):
		result.error = tr(NO_RANGE_ERROR)
		result.range_ignored = true
		return result
	if request_result != HTTPRequest.RESULT_SUCCESS:
		_fail(result, request_result)
		return result
	if code != HTTPClient.RESPONSE_PARTIAL_CONTENT:
		result.error = tr("HTTP %d") % code
		return result
	result.total_size = _content_range_total(response[2] as PackedStringArray)
	if target_path.is_empty():
		result.bytes = response[3] as PackedByteArray
		if result.bytes.size() != end - start + 1:
			result.error = tr("got %d bytes instead of %d") % [
				result.bytes.size(), end - start + 1,
			]
	return result


func async_download(target_path: String) -> RangeSource.Result:
	var result := RangeSource.Result.new()
	var response := await _async_request(
		PackedStringArray(), -1, WHOLE_DOWNLOAD_CHUNK_SIZE, target_path, result
	)
	if response.is_empty():
		return result
	var request_result := response[0] as int
	var code := response[1] as int
	if request_result != HTTPRequest.RESULT_SUCCESS:
		_fail(result, request_result)
	elif code != HTTPClient.RESPONSE_OK:
		result.error = tr("HTTP %d") % code
	return result


func downloaded_bytes() -> int:
	return _http.get_downloaded_bytes() if is_instance_valid(_http) else 0


func cancel() -> void:
	_cancelled = true
	_stop_request()


## Requests the file with [param headers] on top of the Hub's, following redirects,
## with a body of at most [param body_limit] bytes (-1: no limit), read
## [param chunk_size] bytes per frame and written to [param target_path], or kept in
## memory when it is empty. Returns the last answer
## ([code][result, code, headers, body][/code]), or an empty array when it was
## canceled, stalled or not sent: [param result] then says why.
func _async_request(
	headers: PackedStringArray,
	body_limit: int,
	chunk_size: int,
	target_path: String,
	result: RangeSource.Result,
) -> Array:
	_cancelled = false
	_stalled = false
	_watched_bytes = -1
	_watchdog.start(stall_timeout_sec)
	_http.body_size_limit = body_limit
	# The last request ended, so the connection is closed, as setting it needs.
	_http.download_chunk_size = chunk_size
	_http.download_file = target_path
	var current_url := _url
	var response: Array = []
	for _hop: int in HttpUrlPrep.MAX_REDIRECTS + 1:
		var request_url := current_url
		var request_headers := PackedStringArray([Config.AGENT_HEADER])
		request_headers.append_array(headers)
		var proxy_host := (Config.HTTP_PROXY_HOST.ret() as String).strip_edges()
		if proxy_host.is_empty():
			var prepared := HttpUrlPrep.prepare(current_url, request_headers)
			request_url = prepared["url"]
			request_headers = prepared["headers"]
			var tls_host: String = prepared["tls_host"]
			if tls_host.is_empty():
				_http.set_tls_options(TLSOptions.client())
			else:
				_http.set_tls_options(TLSOptions.client(null, tls_host))
		if _cancelled:
			break
		var err := _http.request(request_url, request_headers)
		if err != OK:
			_watchdog.stop()
			result.error = tr("request failed: %s") % error_string(err)
			return []
		await _request_done
		if _cancelled or _stalled:
			break
		response = _response
		var next := HttpUrlPrep.redirect_target(response, current_url)
		if next.is_empty():
			break
		current_url = next
	if is_instance_valid(_watchdog):
		_watchdog.stop()
	if is_instance_valid(_http):
		_http.download_file = ""
	if _cancelled:
		result.cancelled = true
		result.error = tr("canceled")
		return []
	if _stalled:
		result.error = tr("timed out")
		return []
	return response


## Ends the running request; the read or download sees why from [member _cancelled]
## or [member _stalled].
func _stop_request() -> void:
	if (
		not is_instance_valid(_http)
		or _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED
	):
		# Between redirects, or the answer is on its way: the read sees the flag.
		return
	_http.cancel_request()
	# cancel_request() does not emit request_completed.
	_request_done.emit()


func _on_request_completed(
	result: int, code: int, headers: PackedStringArray, body: PackedByteArray
) -> void:
	_response = [result, code, headers, body]
	_request_done.emit()


## Fails the read or download when no data came since the last check, e.g. a dropped
## connection the server never closes.
func _on_watchdog_timeout() -> void:
	var downloaded := _http.get_downloaded_bytes()
	if downloaded != _watched_bytes:
		_watched_bytes = downloaded
		return
	_stalled = true
	_watchdog.stop()
	_stop_request()


## The total of a "Content-Range: bytes 0-0/1281349702" header, or -1.
static func _content_range_total(headers: PackedStringArray) -> int:
	for header in headers:
		if header.to_lower().begins_with("content-range:"):
			var total := header.get_slice("/", 1).strip_edges()
			if total.is_valid_int():
				return total.to_int()
	return -1


## Fails [param result] with why the request ended with [param request_result], an
## [enum HTTPRequest.Result] other than success.
func _fail(result: RangeSource.Result, request_result: int) -> void:
	result.error = _result_text(request_result)
	result.write_failed = request_result in [
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR,
	]


func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return tr("could not connect")
		HTTPRequest.RESULT_CANT_RESOLVE:
			return tr("could not resolve the host name")
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return tr("TLS handshake failed")
		HTTPRequest.RESULT_NO_RESPONSE:
			return tr("no response")
		HTTPRequest.RESULT_TIMEOUT:
			return tr("timed out")
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return tr("could not write the download")
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return tr("too many redirects")
	return tr("request failed (%d)") % result
