import 'dart:async';
import 'dart:convert';

import 'package:flutter_js_runtime/javascript_runtime.dart';
import 'package:flutter_js_runtime/src/runtime_lifecycle.dart';
import 'package:http/http.dart' as http;

/*
 * Based on bits and pieces from different OSS sources
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// ignore: non_constant_identifier_names
var _XHR_DEBUG = false;

setXhrDebug(bool value) => _XHR_DEBUG = value;

const HTTP_GET = "get";
const HTTP_POST = "post";
const HTTP_PATCH = "patch";
const HTTP_DELETE = "delete";
const HTTP_PUT = "put";
const HTTP_HEAD = "head";

enum HttpMethod { put, get, post, delete, patch, head }

String _debugSendNativeCallback() {
  if (_XHR_DEBUG) {
    return """console.log("XMLHttpRequest._send_native_callback");
      console.log("arguments");
      console.log(arguments);
      console.log(responseInfo);
      console.log(responseText);
      console.log(error);""";
  } else
    return "";
}

final String xhrJsCode = """
function XMLHttpRequest() {
  this._send_native = XMLHttpRequestExtension_send_native;
  this._httpMethod = null;
  this._url = null;
  this._requestHeaders = [];
  this._responseHeaders = [];
  this.response = null;
  this.responseText = null;
  this.responseXML = null;
  this.responseType = "";
  this.onreadystatechange = null;
  this.onloadstart = null;
  this.onprogress = null;
  this.onabort = null;
  this.onerror = null;
  this.onload = null;
  this.onloadend = null;
  this.ontimeout = null;
  this.readyState = 0;
  this.status = 0;
  this.statusText = "";
  this.withCredentials = null;
};
// readystate enum
XMLHttpRequest.UNSENT = 0;
XMLHttpRequest.OPENED = 1;
XMLHttpRequest.HEADERS = 2;
XMLHttpRequest.LOADING = 3;
XMLHttpRequest.DONE = 4;
XMLHttpRequest.prototype.constructor = XMLHttpRequest;
XMLHttpRequest.prototype.open = function(httpMethod, url) {
  this._httpMethod = httpMethod == null ? httpMethod : String(httpMethod);
  this._url = url == null ? url : String(url);
  // Headers of a previous response must not show on a reused request.
  this._responseHeaders = [];
  this.readyState = XMLHttpRequest.OPENED;
  if (typeof this.onreadystatechange === "function") {
    //console.log("Calling onreadystatechange(OPENED)...");
    this.onreadystatechange();
  }
};
XMLHttpRequest.prototype.send = function(data) {
  this.readyState = XMLHttpRequest.LOADING;
  if (typeof this.onreadystatechange === "function") {
    //console.log("Calling onreadystatechange(LOADING)...");
    this.onreadystatechange();
  }
  if (typeof this.onloadstart === "function") {
    //console.log("Calling onloadstart()...");
    this.onloadstart();
  }
  var that = this;
  if (typeof ArrayBuffer !== "undefined" && data && (data instanceof ArrayBuffer || ArrayBuffer.isView(data))) {
    // Bodies are passed to Dart as text; sending the bytes as their string
    // form would silently upload the wrong data.
    setTimeout(function() {
      that._send_native_callback({ statusCode: 0, statusText: "" }, null, "XHR binary request bodies are not supported");
    }, 0);
    return;
  }
  // As in browsers, other bodies that are not strings are sent as String(body).
  var body = (data === undefined || data === null || data === "") ? null : String(data);
  this._send_native(this._httpMethod, this._url, this._requestHeaders, body, function(responseInfo, responseText, error) {
    that._send_native_callback(responseInfo, responseText, error);
  }, this);
};
XMLHttpRequest.prototype.abort = function() {
  this.readyState = XMLHttpRequest.UNSENT;
  // Note: this.onreadystatechange() is not supposed to be called according to the XHR specs
}
// responseInfo: {statusCode, statusText, responseHeaders}
XMLHttpRequest.prototype._send_native_callback = function(responseInfo, responseText, error) {
  ${_debugSendNativeCallback()}
  if (this.readyState === XMLHttpRequest.UNSENT) {
    console.log("XHR native callback ignored because the request has been aborted");
    if (typeof this.onabort === "function") {
      //console.log("Calling onabort()...");
      this.onabort();
    }
    return;
  }
  if (this.readyState != XMLHttpRequest.LOADING) {
    // Request was not expected
    console.log("XHR native callback ignored because the current state is not LOADING");
    return;
  }
  // Response info
  // TODO: responseXML?
  this.responseURL = this._url;
  this.status = responseInfo.statusCode;
  this.statusText = responseInfo.statusText;
  // Stored as [lower-cased name, value] pairs; anything else is ignored.
  this._responseHeaders = [];
  var rawHeaders = responseInfo.responseHeaders;
  if (Array.isArray(rawHeaders)) {
    for (var h = 0; h < rawHeaders.length; h++) {
      var pair = rawHeaders[h];
      if (!Array.isArray(pair) || pair.length < 2) continue;
      this._responseHeaders.push([String(pair[0]).toLowerCase(), String(pair[1])]);
    }
  }
  this.readyState = XMLHttpRequest.DONE;
  // Response
  this.response = null;
  this.responseText = null;
  this.responseXML = null;
  if (error) {
    this.responseText = error;
  } else {
    this.responseText = responseText;
    //console.log('RESPONSE TEXT: ' + responseText);
    switch (this.responseType) {
      case "":
      case "text":
        this.response = this.responseText;
        break;
      case "arraybuffer":
        error = "XHR arraybuffer response is not supported!";
        break;
      case "document":
        this.response = this.responseText;
        this.responseXML = this.responseText;
        break;
      case "json":
        try {
            this.response = JSON.parse(responseText);
        }
        catch (e) {
            error = "Could not parse JSON response: " + responseText;
        }
        break;
      default:
        error = "Unsupported responseType: " + responseInfo.responseType;
    }
  }
  this.readyState = XMLHttpRequest.DONE;
  if (typeof this.onreadystatechange === "function") {
    //console.log("Calling onreadystatechange(DONE)...");
    this.onreadystatechange();
  }
  if (error === "timeout") {
    // Timeout
    console.warn("Got XHR timeout");
    if (typeof this.ontimeout === "function") {
      //console.log("Calling ontimeout()...");
      this.ontimeout();
    }
  } else if (error) {
    // Error
    console.warn("Got XHR error:", error);
    if (typeof this.onerror === "function") {
      //console.log("Calling onerror()...");
      this.onerror();
    }
  } else {
    // Success
    //console.log("XHR success: response =", this.response);
    if (typeof this.onload === "function") {
      //console.log("Calling onload()...");
      this.onload();
    }
  }
  if (typeof this.onloadend === "function") {
    //console.log("Calling onloadend()...");
    this.onloadend();
  }
};
XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
  this._requestHeaders.push([String(header), String(value)]);
};
// As in browsers: lower-cased names sorted by their upper-cased form, one
// "name: value" line per name (repeated names combined with ", "), each line
// ending in CRLF.
XMLHttpRequest.prototype.getAllResponseHeaders = function() {
  var items = [];
  var i;
  for (i = 0; i < this._responseHeaders.length; i++) {
    var keyValue = this._responseHeaders[i];
    items.push({ name: keyValue[0], key: keyValue[0].toUpperCase(), value: keyValue[1], index: i });
  }
  // Ties go to the name first, so equal names always end up adjacent.
  items.sort(function(a, b) {
    if (a.key !== b.key) return a.key < b.key ? -1 : 1;
    if (a.name !== b.name) return a.name < b.name ? -1 : 1;
    return a.index - b.index;
  });
  var ret = "";
  for (i = 0; i < items.length; i++) {
    var value = items[i].value;
    while (i + 1 < items.length && items[i + 1].name === items[i].name) {
      i++;
      value += ", " + items[i].value;
    }
    ret += items[i].name + ": " + value + "\\r\\n";
  }
  return ret;
};
// The name is matched case-insensitively. Returns null when the response
// has no such header (an empty header value is returned as "").
XMLHttpRequest.prototype.getResponseHeader = function(name) {
  var wanted = String(name).toLowerCase();
  var ret = null;
  for (var i = 0; i < this._responseHeaders.length; i++) {
    var keyValue = this._responseHeaders[i];
    if (keyValue[0] !== wanted) continue;
    ret = ret === null ? keyValue[1] : ret + ", " + keyValue[1];
  }
  return ret;
};
// XMLHttpRequest.prototype.overrideMimeType = function() {
//   // TODO
// };
this.XMLHttpRequest = XMLHttpRequest;""";

RegExp regexpHeader = RegExp("^([\\w-])+:(?!\\s*\$).+\$");

class XhrPendingCall {
  int? idRequest;
  String? method;
  String? url;
  Map<String, String> headers;
  String? body;

  XhrPendingCall({
    required this.idRequest,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });
}

const XHR_PENDING_CALLS_KEY = "xhrPendingCalls";

http.Client? httpClient;

xhrSetHttpClient(http.Client client) {
  httpClient = client;
}

extension JavascriptRuntimeXhrExtension on JavascriptRuntime {
  List<dynamic>? getPendingXhrCalls() {
    return dartContext[XHR_PENDING_CALLS_KEY];
  }

  bool hasPendingXhrCalls() => getPendingXhrCalls()!.length > 0;
  void clearXhrPendingCalls() {
    dartContext[XHR_PENDING_CALLS_KEY] = [];
  }

  /// Sends the result of a pending XHR call back to the JavaScript callback.
  /// Values are passed as JSON literals so the response body is never
  /// interpreted as JavaScript source.
  void _sendXhrResult(int? idRequest, XmlHttpRequestResponse result) {
    // A response that arrives after dispose() has nowhere to go.
    if (isRuntimeDisposed(this)) return;
    final responseInfo = jsonEncode(result.responseInfo);
    final responseText = jsonEncode(result.responseText);
    final error = jsonEncode(result.error);
    this.evaluate(
      "globalThis.xhrRequests[$idRequest].callback($responseInfo, $responseText, $error);",
    );
  }

  JavascriptRuntime enableXhr() {
    httpClient = httpClient ?? http.Client();
    dartContext[XHR_PENDING_CALLS_KEY] = [];

    ownRuntimeTimer(this, Timer.periodic(Duration(milliseconds: 40), (timer) {
      // exits if there is no pending call to remote
      if (!hasPendingXhrCalls()) return;

      // collect the pending calls into a local variable making copies
      List<dynamic> pendingCalls = List<dynamic>.from(getPendingXhrCalls()!);
      // clear the global pending calls list
      clearXhrPendingCalls();

      // for each pending call, calls the remote http service
      pendingCalls.forEach((element) async {
        XhrPendingCall pendingCall = element as XhrPendingCall;
        late http.Response response;
        try {
          final methodName = '${pendingCall.method}'.toLowerCase();
          final knownMethods =
              HttpMethod.values.where((e) => e.name == methodName);
          switch (knownMethods.isEmpty ? null : knownMethods.first) {
            case null:
              // Any other method (OPTIONS, ...) is sent as it is.
              final request = http.Request(
                methodName == 'options' ? 'OPTIONS' : pendingCall.method!,
                Uri.parse(pendingCall.url!),
              )..headers.addAll(pendingCall.headers);
              final body = pendingCall.body;
              if (body != null) request.body = body;
              response = await http.Response.fromStream(
                await httpClient!.send(request),
              );
              break;
            case HttpMethod.head:
              response = await httpClient!.head(
                Uri.parse(pendingCall.url!),
                headers: pendingCall.headers,
              );
              break;
            case HttpMethod.get:
              response = await httpClient!.get(
                Uri.parse(pendingCall.url!),
                headers: pendingCall.headers,
              );
              break;
            case HttpMethod.post:
              response = await httpClient!.post(
                Uri.parse(pendingCall.url!),
                // null sends no body (jsonEncode(null) would send "null").
                body: pendingCall.body,
                headers: pendingCall.headers,
              );
              break;
            case HttpMethod.put:
              response = await httpClient!.put(
                Uri.parse(pendingCall.url!),
                // null sends no body (jsonEncode(null) would send "null").
                body: pendingCall.body,
                headers: pendingCall.headers,
              );
              break;
            case HttpMethod.patch:
              response = await httpClient!.patch(
                Uri.parse(pendingCall.url!),
                // null sends no body (jsonEncode(null) would send "null").
                body: pendingCall.body,
                headers: pendingCall.headers,
              );
              break;
            case HttpMethod.delete:
              response = await httpClient!.delete(
                Uri.parse(pendingCall.url!),
                headers: pendingCall.headers,
              );
              break;
          }
        } catch (e) {
          // Network failure (connection refused, DNS, TLS, ...): report it
          // so the JavaScript side calls onerror instead of waiting forever.
          _sendXhrResult(
            pendingCall.idRequest,
            XmlHttpRequestResponse(
              responseText: null,
              responseInfo: XhtmlHttpResponseInfo(statusCode: 0, statusText: ''),
              error: e.toString(),
            ),
          );
          return;
        }
        // Malformed UTF-8 is replaced with U+FFFD instead of throwing.
        final responseText =
            utf8.decode(response.bodyBytes, allowMalformed: true);
        final responseInfo = XhtmlHttpResponseInfo(
          statusCode: response.statusCode,
          statusText: response.reasonPhrase ?? '',
        );
        // Copied as received; the JavaScript side normalizes the names.
        response.headers.forEach(responseInfo.addResponseHeaders);
        _sendXhrResult(
          pendingCall.idRequest,
          XmlHttpRequestResponse(
            responseText: responseText,
            responseInfo: responseInfo,
          ),
        );
      });
    }));

    final evalXhrSendNative = this.evaluate("""
    var xhrRequests = {};
    var idRequest = -1;
    function XMLHttpRequestExtension_send_native() {
      idRequest += 1;
      var id = idRequest;
      var cb = arguments[4];
      var context = arguments[5];
      xhrRequests[id] = {
        callback: function(responseInfo, responseText, error) {
          // A request is answered once; do not keep it (and its response).
          delete xhrRequests[id];
          cb(responseInfo, responseText, error);
        }
      };
      var args = [];
      args[0] = arguments[0];
      args[1] = arguments[1];
      args[2] = arguments[2];
      args[3] = arguments[3];
      args[4] = idRequest;
      sendMessage('SendNative', JSON.stringify(args));
    }
    """);

    final evalXhrResult = this.evaluate(xhrJsCode);
    localContext['enableXhr'] = evalXhrResult.rawResult;
    localContext['xhrSendNative'] = evalXhrSendNative.rawResult;
    if (_XHR_DEBUG) print('RESULT evalXhrResult: $evalXhrResult');

    this.onMessage('SendNative', (arguments) {
      try {
        String? method = arguments[0];
        String? url = arguments[1];
        dynamic headersList = arguments[2];
        String? body = arguments[3]?.toString();
        int? idRequest = arguments[4];

        Map<String, String> headers = {};
        headersList.forEach((header) {
          // final headerMatch = regexpHeader.allMatches(value).first;
          // String? headerName = headerMatch.group(0);
          // String? headerValue = headerMatch.group(1);
          // if (headerName != null) {
          //   headers[headerName] = headerValue ?? '';
          // }
          String headerKey = '${header[0]}';
          headers[headerKey] = '${header[1]}';
        });
        (dartContext[XHR_PENDING_CALLS_KEY] as List<dynamic>).add(
          XhrPendingCall(
            idRequest: idRequest,
            method: method,
            url: url,
            headers: headers,
            body: body,
          ),
        );
      } catch (e) {
        if (_XHR_DEBUG) print('ERROR calling sendNative on Dart: >>>> $e');
        // Report the failure, or the request would never settle. Not from
        // inside this handler: JavaScript is still running send().
        final id = arguments is List && arguments.length > 4
            ? arguments[4]
            : null;
        if (id is int) {
          Timer.run(
            () => _sendXhrResult(
              id,
              XmlHttpRequestResponse(
                responseInfo:
                    XhtmlHttpResponseInfo(statusCode: 0, statusText: ''),
                error: e.toString(),
              ),
            ),
          );
        }
      }
    });
    return this;
  }
}

class XhtmlHttpResponseInfo {
  final int? statusCode;
  final String? statusText;
  final List<List<String>> responseHeaders = [];

  XhtmlHttpResponseInfo({
    this.statusCode,
    this.statusText,
  });

  void addResponseHeaders(String name, String value) {
    responseHeaders.add([name, value]);
  }

  Map<String, Object?> toJson() {
    return {
      "statusCode": statusCode,
      "statusText": statusText,
      "responseHeaders": responseHeaders
    };
  }
}

class XmlHttpRequestResponse {
  final String? responseText;
  final String? error; // should be timeout in case of timeout
  final XhtmlHttpResponseInfo? responseInfo;

  XmlHttpRequestResponse({this.responseText, this.responseInfo, this.error});

  Map<String, Object?> toJson() {
    return {
      'responseText': responseText,
      'responseInfo': responseInfo!.toJson(),
      'error': error
    };
  }
}
