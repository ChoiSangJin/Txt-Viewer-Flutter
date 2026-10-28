package com.choisangjin.txtviewer

import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.zip.CRC32

/** Derived page metadata only; never writes or removes books or reading history. */
class PageIndexStore(private val books: File, private val cache: File) {
    companion object { private const val MAGIC = 0x47595031; private const val MAX_PAGES = 200000 }
    private fun token(bookId: String, layout: String): String {
        require(bookId.matches(Regex("[a-f0-9-]{36}")))
        require(layout.length <= 2048)
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(layout.toByteArray(Charsets.UTF_8)); digest.update(0.toByte())
        File(books, "$bookId.txt").inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    fun load(bookId: String, layout: String): Map<String, Any?> {
        val key = token(bookId, layout)
        val file = File(cache, "$key.bin")
        var ends: IntArray? = null
        if (file.isFile) {
            try {
                require(file.length() in 16L..(16L + MAX_PAGES * 4L))
                val bytes = file.readBytes(); val buffer = ByteBuffer.wrap(bytes)
                require(buffer.int == MAGIC)
                val count = buffer.int
                require(count in 1..MAX_PAGES && bytes.size.toLong() == 16L + count * 4L)
                val result = IntArray(count) { buffer.int }
                val expected = buffer.long
                val crc = CRC32().apply { update(bytes, 0, bytes.size - 8) }.value
                require(crc == expected && valid(result))
                ends = result
                file.setLastModified(System.currentTimeMillis())
            } catch (_: Exception) { file.delete() }
        }
        return mapOf("token" to key, "ends" to ends)
    }
    private fun valid(ends: IntArray): Boolean {
        if (ends.isEmpty() || ends.size > MAX_PAGES) return false
        var previous = 0
        for (end in ends) {
            if (end < 0 || (end <= previous && !(ends.size == 1 && end == 0))) return false
            previous = end
        }
        return true
    }
    fun save(bookId: String, layout: String, expectedToken: String, ends: IntArray): Boolean {
        if (!expectedToken.matches(Regex("[a-f0-9]{64}")) || !valid(ends)) return false
        if (token(bookId, layout) != expectedToken) return false
        check(cache.isDirectory || cache.mkdirs())
        val buffer = ByteBuffer.allocate(16 + ends.size * 4)
        buffer.putInt(MAGIC); buffer.putInt(ends.size)
        ends.forEach { buffer.putInt(it) }
        buffer.putLong(CRC32().apply { update(buffer.array(), 0, buffer.position()) }.value)
        val temp = File.createTempFile("index-", ".tmp", cache)
        try {
            temp.outputStream().use { it.write(buffer.array()) }
            if (!temp.renameTo(File(cache, "$expectedToken.bin"))) return false
        } finally { temp.delete() }
        var bytes = cache.listFiles()?.filter { it.name.endsWith(".bin") }?.sumOf { it.length() } ?: 0
        val files = cache.listFiles()?.filter { it.name.endsWith(".bin") }?.sortedWith(compareBy<File> { it.name == "$expectedToken.bin" }.thenBy { it.lastModified() }).orEmpty()
        var count = files.size
        for (file in files) {
            if (count <= 12 && bytes <= 16L * 1024 * 1024) break
            val size = file.length()
            if (file.delete()) { count--; bytes -= size }
        }
        return true
    }
}
