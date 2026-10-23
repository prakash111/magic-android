package com.example.magicai_mobile

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.net.http.SslError
import android.view.View
import android.webkit.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject

class VisualEditorFactory(
    private val messenger: BinaryMessenger,
    private val chooseFiles: (WebChromeClient.FileChooserParams, ValueCallback<Array<Uri>>) -> Unit,
    private val download: (String) -> Unit
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        VisualEditorView(context, viewId, messenger, args as Map<*, *>, chooseFiles, download)
}

class VisualEditorView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    arguments: Map<*, *>,
    chooseFiles: (WebChromeClient.FileChooserParams, ValueCallback<Array<Uri>>) -> Unit,
    download: (String) -> Unit
) : PlatformView {
    private val widget = WebView(context)
    private val channel = MethodChannel(messenger, "com.magicai.mobile/visual/$viewId")
    private val ticket = Uri.parse(arguments["url"] as String)
    private val entry = Uri.parse(arguments["entry"] as String)
    private val nonce = arguments["nonce"] as String
    private var port: WebMessagePort? = null
    private var disposed = false

    private fun sameOrigin(uri: Uri): Boolean = uri.scheme == "https" && uri.host == entry.host &&
        (uri.port == -1 || uri.port == 443) && uri.userInfo == null && uri.fragment == null

    private fun allowedPage(uri: Uri): Boolean = sameOrigin(uri) &&
        (uri.path == entry.path || uri == ticket)

    private fun event(type: String, message: String) {
        if (!disposed) channel.invokeMethod("message", JSONObject().put("version", 1).put("nonce", nonce)
            .put("type", type).put("payload", JSONObject().put("message", message)).toString())
    }

    init {
        require(sameOrigin(ticket) && entry.path?.startsWith("/dashboard/user/") == true &&
            ticket.path?.matches(Regex("/(?:magicai-mobile|mobile)/open/[A-Za-z0-9]{64}")) == true &&
            nonce.matches(Regex("[A-Za-z0-9]{64}")))
        widget.setBackgroundColor(Color.rgb(19, 22, 32))
        widget.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            mediaPlaybackRequiresUserGesture = true
            if (android.os.Build.VERSION.SDK_INT >= 26) safeBrowsingEnabled = true
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(widget, false)
        widget.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (!request.isForMainFrame) return true
                if (allowedPage(request.url)) return false
                event("error", "Use the app navigation to open other tools.")
                return true
            }

            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                port?.close()
                port = null
                if (url == null || !allowedPage(Uri.parse(url))) { view.stopLoading(); event("error", "This editor destination is not allowed.") }
            }

            override fun onPageFinished(view: WebView, url: String?) {
                if (disposed || port != null || url == null || !sameOrigin(Uri.parse(url)) || Uri.parse(url).path != entry.path || view.url != url) return
                val ports = view.createWebMessageChannel()
                port?.close()
                port = ports[0]
                port!!.setWebMessageCallback(object : WebMessagePort.WebMessageCallback() {
                    override fun onMessage(receivingPort: WebMessagePort, message: WebMessage?) {
                        if (disposed || receivingPort !== port || view.url == null || !allowedPage(Uri.parse(view.url))) return
                        val raw = message?.data ?: return
                        if (raw.length > 28 * 1024 * 1024) return
                        try {
                            val data = JSONObject(raw)
                            if (data.optInt("version") != 1 || data.optString("nonce") != nonce ||
                                data.optString("type") !in setOf("ready", "dirty", "saved", "error", "export") ||
                                data.optJSONObject("payload") == null) return
                            channel.invokeMethod("message", raw)
                        } catch (_: Exception) { }
                    }
                })
                view.postWebMessage(WebMessage("magicai-widget:$nonce", arrayOf(ports[1])), Uri.parse("https://${entry.host}"))
            }

            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                handler.cancel()
                event("error", "The editor connection could not be verified.")
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) event("error", "Unable to load the editor. Check your connection and retry.")
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (request.isForMainFrame) event("error", "The editor session expired or is unavailable. Reopen it to retry.")
            }
        }
        widget.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                if (view.url != null && sameOrigin(Uri.parse(view.url))) chooseFiles(params, callback)
                else callback.onReceiveValue(null)
                return true
            }
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onJsAlert(view: WebView, url: String, message: String, result: JsResult): Boolean {
                event("error", message.take(500)); result.confirm(); return true
            }
        }
        widget.setDownloadListener { url, _, _, _, _ ->
            val uri = Uri.parse(url)
            val downloadPath = entry.path.orEmpty().split('/').take(4).joinToString("/") + "/"
            if (sameOrigin(uri) && uri.path.orEmpty().startsWith(downloadPath)) download(url)
            else event("error", "This download is unavailable in the editor. Export a PNG or use the saved project.")
        }
        channel.setMethodCallHandler { call, result ->
            val type = call.argument<String>("type")
            if (call.method != "command" || call.argument<String>("nonce") != nonce || type !in setOf("save", "export") || port == null) {
                result.error("invalid_editor_action", "The editor is not ready.", null)
            } else {
                port!!.postMessage(WebMessage(JSONObject().put("version", 1).put("nonce", nonce).put("type", type).toString()))
                result.success(null)
            }
        }
        widget.loadUrl(ticket.toString())
    }

    override fun getView(): View = widget
    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        port?.close()
        port = null
        widget.stopLoading()
        widget.webViewClient = WebViewClient()
        widget.webChromeClient = null
        widget.destroy()
    }
}
