package com.choisangjin.txtviewer

import org.junit.Assert.*
import org.junit.Test

class FolderIndexTest {
    private val tree = mapOf(
        "root" to listOf(FolderIndex.Node("pdf", "문서.pdf"), FolderIndex.Node("sub", "시리즈", true),
            FolderIndex.Node("b", "B.TXT"), FolderIndex.Node("a", "a.txt")),
        "sub" to listOf(FolderIndex.Node("moon", "Moon.txt"), FolderIndex.Node("cycle", "cycle", true)),
        "cycle" to listOf(FolderIndex.Node("sub", "시리즈", true))
    )
    private fun scan(query: String, index: FolderIndex = FolderIndex()) =
        index.scan("root", query, { id, limit -> tree[id].orEmpty().take(limit + 1) }, {})

    @Test fun browsingListsOnlyImmediateFoldersAndTxtInOrder() {
        val result = scan("")
        assertEquals(listOf("시리즈", "a.txt", "B.TXT"), result.entries.map { it.node.name })
        assertFalse(result.truncated)
    }
    @Test fun recursiveSearchIgnoresCaseAndReturnsRelativePaths() {
        val result = scan(" MOON ")
        assertEquals(listOf("시리즈/Moon.txt"), result.entries.map { it.path })
        assertFalse(result.truncated)
    }
    @Test fun searchMatchesParentPathAndTerminatesCycles() {
        val result = scan("시리즈")
        assertEquals(listOf("moon"), result.entries.map { it.node.id })
    }
    @Test fun scanBudgetMarksPartialResultsEvenWithoutMatches() {
        assertTrue(scan("missing", FolderIndex(maxVisited = 2)).truncated)
    }
    @Test fun resultLimitMarksPartialResults() {
        val result = scan("", FolderIndex(maxResults = 1))
        assertTrue(result.truncated); assertEquals(1, result.entries.size)
    }
    @Test fun emptyFolderIsNotReportedAsTruncated() {
        val result = FolderIndex().scan("empty", "", { _, _ -> emptyList() }, {})
        assertTrue(result.entries.isEmpty()); assertFalse(result.truncated)
    }
    @Test(expected = SecurityException::class) fun permissionErrorsPropagate() {
        FolderIndex().scan("root", "x", { _, _ -> throw SecurityException("revoked") }, {})
    }
    @Test(expected = java.util.concurrent.CancellationException::class) fun cancelledSearchStopsTraversal() {
        FolderIndex().scan("root", "x", { _, _ -> error("must not query") },
            { throw java.util.concurrent.CancellationException() })
    }
}
