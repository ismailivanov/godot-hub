class_name HttpUrlPrep
extends RefCounted
## Rewrites request URLs to dial a resolved IPv4 address directly.
##
## Godot's HTTP stack dials the first resolved address, which is IPv6 on
## dual-stack networks. When IPv6 connectivity is broken (black-holed route),
## every request stalls until the kernel gives up on the IPv6 SYN (~60s) before
## falling back to IPv4. Some requests never complete at all.
##
## Dialing a resolved IPv4 address fixes this, but the request must then keep
## identifying itself as the real host: a "Host" header for HTTP routing and a
## TLSOptions common_name override for SNI + certificate verification
## (HTTPRequest has no tls_options property in Godot 4.7, but set_tls_options()
## is bound as a method).


## Maximum number of redirects followed manually by callers.
const MAX_REDIRECTS := 8


## Redirect response codes handled per RFC 7231.
static func is_redirect_code(code: int) -> bool:
	return code in [301, 302, 303, 307, 308]


## Prepares a request. Returns:
##   {
##     "url": String,          - url with host possibly replaced by IPv4
##     "headers": PackedStringArray, - headers plus a "Host:" override when rewritten
##     "tls_host": String,     - hostname for TLSOptions; empty when no override needed
##   }
## The proxy case must be handled by the caller: when an HTTP(S) proxy is in
## use, hostname resolution belongs to the proxy, so callers skip this rewrite.
static func prepare(url: String, headers: PackedStringArray) -> Dictionary:
	var parsed := _parse(url)
	if parsed.is_empty():
		return {"url": url, "headers": headers, "tls_host": ""}
	var host: String = parsed["host"]
	var port: String = parsed["port"]

	var ipv4 := IP.resolve_hostname(host, IP.TYPE_IPV4)
	if ipv4.is_empty():
		return {"url": url, "headers": headers, "tls_host": ""}

	var host_and_port := host if port.is_empty() else "%s:%s" % [host, port]
	var out_headers := PackedStringArray()
	for h: String in headers:
		if h.strip_edges().to_lower().begins_with("host:"):
			continue
		out_headers.append(h)
	out_headers.append("Host: " + host_and_port)

	var new_url := "%s://%s%s%s" % [
		parsed["scheme"],
		ipv4,
		"" if port.is_empty() else ":" + port,
		parsed["path_and_query"],
	]
	return {"url": new_url, "headers": out_headers, "tls_host": host}


## Returns the absolute redirect target for a response, or "" when the
## response is not a redirect we follow.
static func redirect_target(response: Array, base_url: String) -> String:
	var code: int = response[1]
	if not is_redirect_code(code):
		return ""
	var headers: PackedStringArray = response[2]
	var location := ""
	for h: String in headers:
		if h.strip_edges().to_lower().begins_with("location:"):
			location = h.substr(h.find(":") + 1).strip_edges()
			break
	if location.is_empty():
		return ""
	if location.contains("://"):
		return location
	var parsed := _parse(base_url)
	if parsed.is_empty():
		return ""
	var r_scheme: String = parsed["scheme"]
	var r_host: String = parsed["host"]
	var r_port: String = parsed["port"]
	var origin := "%s://%s%s" % [
		r_scheme,
		r_host,
		"" if r_port.is_empty() else ":" + r_port,
	]
	if location.begins_with("/"):
		return origin + location
	var dir: String = (parsed["path_and_query"] as String).get_base_dir()
	return origin + dir + "/" + location


## Splits "scheme://host[:port]/path?query". Returns {} when the url is not
## http(s), the host is already an address literal, or it cannot be parsed.
static func _parse(url: String) -> Dictionary:
	var scheme_end := url.find("://")
	if scheme_end < 0:
		return {}
	var scheme: String = url.substr(0, scheme_end).to_lower()
	if scheme != "http" and scheme != "https":
		return {}
	var rest := url.substr(scheme_end + 3)
	var path_start := rest.find("/")
	var authority: String = rest if path_start < 0 else rest.substr(0, path_start)
	var path_and_query: String = "/" if path_start < 0 else rest.substr(path_start)
	if authority.is_empty() or authority.contains("@"):
		return {}
	var host := authority
	var port := ""
	var last_colon := authority.rfind(":")
	if last_colon > 0 and not authority.begins_with("["):
		var maybe_port := authority.substr(last_colon + 1)
		if maybe_port.is_valid_int():
			host = authority.substr(0, last_colon)
			port = maybe_port
	if host.is_valid_ip_address() or host.contains(":"):
		return {}
	return {
		"scheme": scheme,
		"host": host,
		"port": port,
		"path_and_query": path_and_query,
	}
