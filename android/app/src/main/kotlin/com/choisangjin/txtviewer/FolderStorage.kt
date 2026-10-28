package com.choisangjin.txtviewer

import android.content.ContentResolver
import android.net.Uri
import android.os.CancellationSignal
import android.provider.DocumentsContract

/** Uses only the persisted SAF tree grant chosen by the user. */
class FolderStorage(private val resolver: ContentResolver) {
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
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
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
                        if (it.isNull(3)) 0L else it.getLong(3)))
                }
            }
            nodes
        }, signal::throwIfCanceled)
        return mapOf("entries" to result.entries.map {
            mapOf("uri" to DocumentsContract.buildDocumentUriUsingTree(tree, it.node.id).toString(),
                "name" to it.node.name, "path" to it.path, "isDirectory" to it.node.directory,
                "modified" to it.node.modified)
        }, "truncated" to result.truncated)
    }
}
