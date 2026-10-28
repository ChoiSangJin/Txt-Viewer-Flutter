package com.choisangjin.txtviewer

import java.util.ArrayDeque
import java.util.Locale

/** Traversal is independent of the Android provider so limits and cycles are testable. */
class FolderIndex(private val maxVisited: Int = 20000, private val maxResults: Int = 2000) {
    data class Node(val id: String, val name: String, val directory: Boolean = false, val modified: Long = 0, val deletable: Boolean = false)
    data class Entry(val node: Node, val path: String)
    data class Result(val entries: List<Entry>, val truncated: Boolean)
    private data class Directory(val id: String, val path: String)

    fun scan(root: String, query: String,
             children: (String, Int) -> List<Node>, checkCancelled: () -> Unit): Result {
        val queue = ArrayDeque<Directory>()
        queue.add(Directory(root, ""))
        val seen = mutableSetOf<String>()
        val entries = mutableListOf<Entry>()
        val needle = query.trim().lowercase(Locale.ROOT)
        var visited = 0
        var truncated = false
        while (queue.isNotEmpty()) {
            checkCancelled()
            val directory = queue.removeFirst()
            if (!seen.add(directory.id)) continue
            for (node in children(directory.id, maxVisited - visited)) {
                checkCancelled()
                if (++visited > maxVisited) { truncated = true; break }
                val path = if (directory.path.isEmpty()) node.name else "${directory.path}/${node.name}"
                if (node.directory && needle.isNotEmpty()) queue.add(Directory(node.id, path))
                val matches = needle.isEmpty() || path.lowercase(Locale.ROOT).contains(needle)
                if (matches && ((node.directory && needle.isEmpty()) ||
                    (!node.directory && node.name.endsWith(".txt", true)))) {
                    if (entries.size >= maxResults) { truncated = true; break }
                    entries.add(Entry(node, path))
                }
            }
            if (truncated || needle.isEmpty()) break
        }
        return Result(entries.sortedWith(compareByDescending<Entry> { it.node.directory }
            .thenBy { it.node.name.lowercase(Locale.ROOT) }.thenBy { it.path.lowercase(Locale.ROOT) }), truncated)
    }
}
