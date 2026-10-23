package com.example.magicai_mobile

import android.app.Activity
import java.io.ByteArrayOutputStream
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private var authReturn: Map<String, String>? = null
    private var voiceResult: MethodChannel.Result? = null
    private var saveImageResult: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null
    private var imageResult: MethodChannel.Result? = null
    private var fileLimit = 10 * 1024 * 1024
    private var editorFiles: android.webkit.ValueCallback<Array<Uri>>? = null
    private var editorDownload: Pair<String, String>? = null
    private val imageRequestCode = 7301
    private val keyAlias = "magicai_secure_v1"
    private val secureExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(keyAlias, null) as? SecretKey
        if (existing != null) return existing
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory("com.magicai.mobile/visual", VisualEditorFactory(
            flutterEngine.dartExecutor.binaryMessenger,
            { params, callback ->
                editorFiles?.onReceiveValue(null)
                editorFiles = callback
                try {
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        type = "*/*"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*", "audio/*"))
                        addCategory(Intent.CATEGORY_OPENABLE)
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.mode == android.webkit.WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE)
                    }, 7305)
                } catch (_: Exception) { editorFiles = null; callback.onReceiveValue(null) }
            },
            { url ->
                if (editorDownload == null) {
                    editorDownload = Pair(url, android.webkit.CookieManager.getInstance().getCookie(url).orEmpty())
                    try {
                        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            type = "video/mp4"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_TITLE, "magicai-export.mp4")
                        }, 7306)
                    } catch (_: Exception) { editorDownload = null }
                }
            }
        ))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.magicai.mobile/secure").setMethodCallHandler { call, result ->
            if (call.method in listOf("read", "write", "delete")) {
                secureExecutor.execute { handleSecureStorage(call, result) }
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "consumeAuthReturn" -> {
                        result.success(authReturn)
                        authReturn = null
                    }
                    "createLoginProof" -> {
                        val bytes = ByteArray(32).apply { java.security.SecureRandom().nextBytes(this) }
                        val verifier = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
                        val challenge = Base64.encodeToString(java.security.MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
                        result.success(mapOf("verifier" to verifier, "challenge" to challenge))
                    }
                    "clearWebSession" -> {
                        android.webkit.CookieManager.getInstance().removeAllCookies(null)
                        android.webkit.WebStorage.getInstance().deleteAllData()
                        result.success(null)
                    }
                    "voiceInput" -> {
                        check(voiceResult == null)
                        voiceResult = result
                        startActivityForResult(Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "Message your assistant")
                        }, 7303)
                    }
                    "contactAction" -> {
                        val scheme = call.argument<String>("scheme") ?: ""
                        val value = call.argument<String>("value") ?: ""
                        require(scheme in listOf("tel", "mailto") && value.length <= 255 && !value.contains("\n") && !value.contains("\r"))
                        startActivity(Intent(if (scheme == "tel") Intent.ACTION_DIAL else Intent.ACTION_SENDTO, Uri.fromParts(scheme, value, null)))
                        result.success(null)
                    }
                    "saveImageToGallery" -> {
                        val bytes = call.argument<ByteArray>("bytes") ?: error("Missing image")
                        require(bytes.isNotEmpty() && bytes.size <= 50 * 1024 * 1024)
                        if (android.os.Build.VERSION.SDK_INT < 29) {
                            result.error("gallery", "Gallery export requires Android 10 or newer.", null)
                        } else {
                            secureExecutor.execute {
                                var uri: Uri? = null
                                try {
                                    val options = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                                    android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                                    require(options.outWidth > 0 && options.outHeight > 0)
                                    val mime = options.outMimeType ?: "image/png"
                                    val extension = when (mime) { "image/jpeg" -> "jpg"; "image/webp" -> "webp"; else -> "png" }
                                    val values = android.content.ContentValues().apply {
                                        put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, "magicai-${System.currentTimeMillis()}.$extension")
                                        put(android.provider.MediaStore.Images.Media.MIME_TYPE, mime)
                                        put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, "Pictures/MagicAI")
                                        put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
                                    }
                                    uri = contentResolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("Gallery unavailable")
                                    contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("Unable to save image")
                                    values.clear()
                                    values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
                                    contentResolver.update(uri, values, null, null)
                                    mainHandler.post { result.success(null) }
                                } catch (_: Exception) {
                                    uri?.let { contentResolver.delete(it, null, null) }
                                    mainHandler.post { result.error("gallery", "Unable to save the image to your gallery.", null) }
                                }
                            }
                        }
                    }
                    "saveImage" -> {
                        check(saveImageResult == null)
                        val bytes = call.argument<ByteArray>("bytes") ?: error("Missing image")
                        require(bytes.size <= 20 * 1024 * 1024)
                        saveImageResult = result
                        exportBytes = bytes
                        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            type = "image/png"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_TITLE, "magicai-design.png")
                        }, 7304)
                    }
                    "pickImage", "pickFile" -> {
                        check(imageResult == null)
                        imageResult = result
                        fileLimit = if (call.method == "pickFile") 50 * 1024 * 1024 else 10 * 1024 * 1024
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            val accepted = call.argument<String>("accept") ?: if (call.method == "pickImage") "image/*" else "*/*"
                            val types = accepted.split(',').map { it.trim() }.filter { it.matches(Regex("[a-zA-Z0-9.+-]+/[a-zA-Z0-9.*+-]+")) }
                            type = if (types.size == 1) types.first() else "*/*"
                            if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }, imageRequestCode)
                    }
                    "previewMedia" -> {
                        val url = Uri.parse(call.argument<String>("url") ?: "")
                        require(url.scheme == "https" && !url.host.isNullOrBlank() && url.userInfo == null)
                        val dialog = android.app.Dialog(this)
                        val layout = android.widget.LinearLayout(this).apply {
                            orientation = android.widget.LinearLayout.VERTICAL
                            setBackgroundColor(android.graphics.Color.BLACK)
                        }
                        val close = android.widget.Button(this).apply { text = "Close preview"; setOnClickListener { dialog.dismiss() } }
                        val video = android.widget.VideoView(this)
                        val controls = android.widget.MediaController(this)
                        controls.setAnchorView(video)
                        video.setMediaController(controls)
                        layout.addView(video, android.widget.LinearLayout.LayoutParams(-1, 0, 1f))
                        layout.addView(close, android.widget.LinearLayout.LayoutParams(-1, -2))
                        dialog.setContentView(layout)
                        dialog.setOnDismissListener { video.stopPlayback() }
                        video.setOnErrorListener { _, _, _ ->
                            android.widget.Toast.makeText(this, "Unable to play this video. Refresh the result and retry.", android.widget.Toast.LENGTH_LONG).show()
                            dialog.dismiss()
                            true
                        }
                        video.setOnPreparedListener { video.start() }
                        dialog.show()
                        dialog.window?.setLayout(-1, -1)
                        video.setVideoURI(url)
                        result.success(null)
                    }
                    "openUrl" -> {
                        val url = Uri.parse(call.argument<String>("url") ?: "")
                        require(url.scheme == "https" && !url.host.isNullOrBlank())
                        startActivity(Intent(Intent.ACTION_VIEW, url))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (exception: Exception) {
                if (call.method in listOf("pickImage", "pickFile")) imageResult = null
                if (call.method == "voiceInput") voiceResult = null
                if (call.method == "saveImage") { saveImageResult = null; exportBytes = null }
                result.error("secure_storage_error", "Secure device storage is unavailable.", null)
            }
        }
    }
    private fun handleSecureStorage(call: MethodCall, result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences("magicai_secure_v1", MODE_PRIVATE)
            val key = call.argument<String>("key") ?: ""
            when (call.method) {
                "read" -> {
                    val saved = prefs.getString(key, null)
                    if (saved == null) mainHandler.post { result.success(null) } else {
                        val parts = saved.split(":", limit = 2)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                        val value = String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
                        mainHandler.post { result.success(value) }
                    }
                }
                "write" -> {
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, secretKey())
                    val encrypted = cipher.doFinal((call.argument<String>("value") ?: "").toByteArray(Charsets.UTF_8))
                    val saved = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(encrypted, Base64.NO_WRAP)
                    check(prefs.edit().putString(key, saved).commit())
                    mainHandler.post { result.success(null) }
                }
                "delete" -> { check(prefs.edit().remove(key).commit()); mainHandler.post { result.success(null) } }
            }
        } catch (exception: Exception) {
            android.util.Log.w("MagicAISecureStore", "Device storage operation ${call.method} failed (${exception.javaClass.simpleName}).")
            mainHandler.post { result.error("secure_storage_error", "Secure device storage is unavailable.", exception.javaClass.simpleName) }
        }
    }

    override fun onDestroy() {
        secureExecutor.shutdown()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uri = intent.data
        if (uri?.scheme == "magicai" && uri.host == "auth" && uri.path == "/complete") {
            val code = uri.getQueryParameter("code") ?: ""
            val flow = uri.getQueryParameter("flow") ?: ""
            if (code.matches(Regex("[A-Za-z0-9]{64}")) && flow.matches(Regex("[A-Za-z0-9]{64}"))) {
                authReturn = mapOf("code" to code, "flow" to flow)
            }
            intent.data = null
        }
        setIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 7305) {
            val callback = editorFiles
            editorFiles = null
            callback?.onReceiveValue(android.webkit.WebChromeClient.FileChooserParams.parseResult(resultCode, data))
            return
        }
        if (requestCode == 7306) {
            val download = editorDownload
            editorDownload = null
            val destination = data?.data
            if (resultCode == Activity.RESULT_OK && download != null && destination != null) {
                Thread {
                    try {
                        val connection = java.net.URL(download.first).openConnection() as javax.net.ssl.HttpsURLConnection
                        connection.instanceFollowRedirects = false
                        connection.connectTimeout = 15000
                        connection.readTimeout = 60000
                        connection.setRequestProperty("Cookie", download.second)
                        try {
                            check(connection.responseCode == 200)
                            check(connection.contentType?.substringBefore(';') in listOf("video/mp4", "application/octet-stream"))
                            contentResolver.openOutputStream(destination)!!.use { output ->
                                connection.inputStream.use { input ->
                                    val buffer = ByteArray(32768)
                                    var total = 0L
                                    while (true) {
                                        val count = input.read(buffer)
                                        if (count < 0) break
                                        total += count
                                        check(total <= 250L * 1024 * 1024)
                                        output.write(buffer, 0, count)
                                    }
                                }
                            }
                        } finally { connection.disconnect() }
                        runOnUiThread { android.widget.Toast.makeText(this, "Export saved", android.widget.Toast.LENGTH_SHORT).show() }
                    } catch (_: Exception) {
                        runOnUiThread { android.widget.Toast.makeText(this, "Unable to save export. Reopen the editor and retry.", android.widget.Toast.LENGTH_LONG).show() }
                    }
                }.start()
            }
            return
        }
        if (requestCode == 7303) {
            val result = voiceResult
            voiceResult = null
            result?.success(if (resultCode == Activity.RESULT_OK) data?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() else null)
            return
        }
        if (requestCode == 7304) {
            val result = saveImageResult
            saveImageResult = null
            try {
                val bytes = exportBytes
                if (resultCode == Activity.RESULT_OK && data?.data != null && bytes != null) {
                    contentResolver.openOutputStream(data.data!!)?.use { it.write(bytes) } ?: error("Unable to save image")
                }
                result?.success(null)
            } catch (exception: Exception) { result?.error("export_error", "Unable to save the image.", null) }
            finally { exportBytes = null }
            return
        }
        if (requestCode != imageRequestCode) return
        val result = imageResult ?: return
        imageResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { result.success(null); return }
        val uri = data.data!!
        val limit = fileLimit
        Thread {
            try {
                var name: String? = null
                contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) name = cursor.getString(0)
                }
                val mime = contentResolver.getType(uri) ?: "application/octet-stream"
                val buffer = ByteArrayOutputStream()
                contentResolver.openInputStream(uri)?.use { input ->
                    val bytes = ByteArray(16384)
                    while (true) {
                        val count = input.read(bytes)
                        if (count < 0) break
                        require(buffer.size() + count <= limit)
                        buffer.write(bytes, 0, count)
                    }
                } ?: error("Unable to read file")
                require(buffer.size() > 0)
                val extension = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "bin"
                val safeName = name?.substringAfterLast('/')?.substringAfterLast('\\')?.replace(Regex("[\\r\\n\"]"), "_")?.takeIf { it.isNotBlank() } ?: "selected-file.$extension"
                mainHandler.post { result.success(mapOf("bytes" to buffer.toByteArray(), "name" to safeName, "mimeType" to mime)) }
            } catch (_: SecurityException) {
                mainHandler.post { result.error("file_access", "Access to this file expired. Choose it again from this device.", null) }
            } catch (_: Exception) {
                mainHandler.post { result.error("file_error", "Choose a readable file no larger than ${limit / (1024 * 1024)} MB.", null) }
            }
        }.start()
    }

}
