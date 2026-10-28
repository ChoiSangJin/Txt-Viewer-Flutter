package com.choisangjin.txtviewer

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Process
import android.net.Uri
import android.os.CancellationSignal
import android.provider.DocumentsContract

/** Uses only the persisted SAF tree grant chosen by the user. */
class FolderStorage(private val context: Context) {
    private val resolver = context.contentResolver
    private fun writable(uri: Uri) = context.checkUriPermission(uri, Process.myPid(), Process.myUid(),
        Intent.FLAG_GRANT_WRITE_URI_PERMISSION) == PackageManager.PERMISSION_GRANTED
    fun list(tree: Uri, parent: Uri?, query: String, signal: CancellationSignal): Map<String, Any> {
        require(DocumentsContract.isTreeUri(tree)) { "폴더를 다시 선택해 주세요." }
        val rootId = parent?.let { DocumentsContract.getDocumentId(it) }
            ?: DocumentsContract.getTreeDocumentId(tree)
        val result = FolderIndex().scan(rootId, query, { id, remaining ->
            val nodes = mutableListOf<FolderIndex.Node>()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                DocumentsContract.Document.COLUMN_FLAGS
            )
            val cursor = resolver.query(children, projection, null, null, null, signal)
                ?: error("폴더 내용을 읽을 수 없습니다. 폴더를 다시 선택해 주세요.")
            cursor.use {
                // One sentinel beyond the remaining budget detects incomplete scans.
                while (nodes.size <= remaining && it.moveToNext()) {
                    signal.throwIfCanceled()
                    nodes.add(FolderIndex.Node(it.getString(0) ?: error("폴더의 문서 정보를 읽지 못했습니다."),
                        it.getString(1) ?: "이름 없는 파일",
                        it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR,
                        if (it.isNull(3)) 0L else it.getLong(3),
                        !it.isNull(2) && it.getString(2) != DocumentsContract.Document.MIME_TYPE_DIR &&
                        !it.isNull(4) && (it.getInt(4) and DocumentsContract.Document.FLAG_SUPPORTS_DELETE) != 0))
                }
            }
            nodes
        }, signal::throwIfCanceled)
        val treeWrite = resolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission } && writable(tree)
        return mapOf("entries" to result.entries.map {
            val uri = DocumentsContract.buildDocumentUriUsingTree(tree, it.node.id)
            mapOf("uri" to uri.toString(),
                "name" to it.node.name, "path" to it.path, "isDirectory" to it.node.directory,
                "modified" to it.node.modified,
                "supportsDelete" to it.node.deletable,
                "canDelete" to (!it.node.directory && it.node.deletable && treeWrite))
        }, "truncated" to result.truncated)
    }
    fun delete(tree: Uri, document: Uri, expectedName: String) {
        require(tree.scheme == "content" && document.scheme == "content" &&
            DocumentsContract.isTreeUri(tree) && DocumentsContract.isTreeUri(document)) { "잘못된 파일 위치입니다." }
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val id = DocumentsContract.getDocumentId(document)
        val sameTree = tree.authority == document.authority &&
            rootId == DocumentsContract.getTreeDocumentId(document)
        require(sameTree && id != rootId) { "선택한 폴더 안의 파일만 삭제할 수 있습니다." }
        val persistedWrite = resolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }
        val columns = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_FLAGS)
        resolver.query(document, columns, null, null, null)?.use {
            check(it.moveToFirst()) { "파일을 찾을 수 없습니다. 새로고침해 주세요." }
            DeletePolicy.requireAllowed(sameTree, id == rootId,
                it.isNull(1) || it.getString(1) == DocumentsContract.Document.MIME_TYPE_DIR,
                it.getString(0) ?: "", expectedName,
                (!it.isNull(2) && (it.getInt(2) and DocumentsContract.Document.FLAG_SUPPORTS_DELETE) != 0),
                persistedWrite && writable(document))
        } ?: error("파일 상태를 읽을 수 없습니다.")
        // The provider enforces tree membership as well as its delete capability.
        check(DocumentsContract.deleteDocument(resolver, document)) { "파일 삭제를 완료하지 못했습니다." }
    }

}
