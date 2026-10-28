package com.choisangjin.txtviewer

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import android.net.Uri
import android.os.CancellationSignal
import android.util.AtomicFile
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var pendingPick: MethodChannel.Result? = null
    private var reading = false
    private val io = Executors.newSingleThreadExecutor()
    private val pickRequest = 4201
    private val folderRequest = 4202
    private var folderScan: CancellationSignal? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "txt_viewer/storage")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setReading" -> { reading = call.arguments == true; result.success(null) }
                "pickBook" -> {
                    if (pendingPick != null) {
                        result.error("BUSY", "파일 선택기가 이미 열려 있습니다.", null)
                    } else {
                        pendingPick = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "application/octet-stream"))
                            }, pickRequest)
                        } catch (e: Exception) {
                            pendingPick = null
                            result.error("PICKER", "문서 선택기를 열 수 없습니다.", null)
                        }
                    }
                }
                "pickFolder" -> {
                    if (pendingPick != null) {
                        result.error("BUSY", "선택기가 이미 열려 있습니다.", null)
                    } else {
                        pendingPick = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }, folderRequest)
                        } catch (e: Exception) {
                            pendingPick = null
                            result.error("PICKER", "폴더 선택기를 열 수 없습니다.", null)
                        }
                    }
                }
                "listFolder" -> {
                    folderScan?.cancel()
                    val signal = CancellationSignal()
                    folderScan = signal
                    val args = call.arguments as Map<*, *>
                    background(result) {
                        FolderStorage(contentResolver).list(
                            Uri.parse(args["treeUri"] as String),
                            (args["parentUri"] as String?)?.let { Uri.parse(it) },
                            args["query"] as String? ?: "", signal
                        )
                    }
                }
                "cancelFolderScan" -> { folderScan?.cancel(); result.success(null) }
                "releaseFolder" -> background(result) {
                    try {
                        contentResolver.releasePersistableUriPermission(
                            Uri.parse(call.arguments as String), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: SecurityException) { /* Already revoked by the user/provider. */ }
                    null
                }
                "importDocument" -> background(result) {
                    importDocument(Uri.parse(call.arguments as String))
                }
                "readBook" -> background(result) {
                    val id = call.arguments as String
                    require(id.matches(Regex("[a-f0-9-]{36}"))) { "잘못된 파일 ID" }
                    File(filesDir, "books/$id.txt").readText(Charsets.UTF_8)
                }
                "loadState" -> background(result) {
                    val file = AtomicFile(File(filesDir, "library.json"))
                    try { file.openRead().bufferedReader(Charsets.UTF_8).use { it.readText() } }
                    catch (e: java.io.FileNotFoundException) { null }
                }
                "saveState" -> background(result) {
                    val file = AtomicFile(File(filesDir, "library.json"))
                    val stream = file.startWrite()
                    try {
                        stream.write((call.arguments as String).toByteArray(Charsets.UTF_8))
                        file.finishWrite(stream)
                    } catch (e: Exception) { file.failWrite(stream); throw e }
                    null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try { val value = block(); runOnUiThread { result.success(value) } }
            catch (e: Exception) {
                runOnUiThread { result.error("FILE_ERROR", e.message ?: "파일 처리 실패", null) }
            }
        }
    }

    @Deprecated("Activity result API required by FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest && requestCode != folderRequest) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        background(result) {
            if (requestCode == folderRequest) {
                val flags = ((data?.flags ?: 0) and Intent.FLAG_GRANT_READ_URI_PERMISSION)
                require(flags != 0) { "폴더 읽기 권한을 허용해 주세요." }
                contentResolver.takePersistableUriPermission(uri, flags)
                val document = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
                val name = displayName(document, "즐겨찾기 폴더")
                mapOf("uri" to uri.toString(), "name" to name)
            } else {
                importDocument(uri)
            }
        }
    }

    private fun displayName(uri: Uri, fallback: String): String {
        return contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) ?: fallback else fallback
        } ?: fallback
    }

    private fun importDocument(uri: Uri): Map<String, Any> {
        val name = displayName(uri, "이름 없는 이야기.txt")
        require(name.endsWith(".txt", ignoreCase = true)) { "TXT 파일을 선택해 주세요." }
        val text = contentResolver.openInputStream(uri)?.use { TextDecoder.read(it) }
            ?: error("파일을 읽을 수 없습니다.")
        // Stable identity keeps the book's reading position on repeated imports.
        val id = UUID.nameUUIDFromBytes(uri.toString().toByteArray(Charsets.UTF_8)).toString()
        val folder = File(filesDir, "books").apply { mkdirs() }
        val file = AtomicFile(File(folder, "$id.txt"))
        val stream = file.startWrite()
        try {
            stream.write(text.toByteArray(Charsets.UTF_8)); file.finishWrite(stream)
        } catch (e: Exception) { file.failWrite(stream); throw e }
        return mapOf("id" to id, "name" to name, "text" to text, "sourceUri" to uri.toString())
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (reading && (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || event.keyCode == KeyEvent.KEYCODE_VOLUME_UP)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                channel.invokeMethod("volume", if (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) "next" else "previous")
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
