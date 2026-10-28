package com.choisangjin.txtviewer

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class PageIndexStoreTest {
    @Rule @JvmField val temp = TemporaryFolder()
    private val id = "11111111-1111-1111-1111-111111111111"
    private fun setup(): Triple<PageIndexStore, File, File> {
        val books = temp.newFolder("books"); val cache = temp.newFolder("cache")
        File(books, "$id.txt").writeText("읽을 책입니다.")
        return Triple(PageIndexStore(books, cache), books, cache)
    }
    @Test fun roundTripPreservesBoundaries() {
        val (store, _, _) = setup(); val key = store.load(id, "font20/360x650")["token"] as String
        assertTrue(store.save(id, "font20/360x650", key, intArrayOf(3, 6, 8)))
        assertArrayEquals(intArrayOf(3, 6, 8), store.load(id, "font20/360x650")["ends"] as IntArray)
    }
    @Test fun partialCheckpointCanBeExtendedAfterReopening() {
        val (store, books, cache) = setup(); val key = store.load(id, "layout")["token"] as String
        assertTrue(store.save(id, "layout", key, intArrayOf(3)))
        val reopened = PageIndexStore(books, cache)
        assertArrayEquals(intArrayOf(3), reopened.load(id, "layout")["ends"] as IntArray)
        assertTrue(reopened.save(id, "layout", key, intArrayOf(3, 6, 8)))
        assertArrayEquals(intArrayOf(3, 6, 8), store.load(id, "layout")["ends"] as IntArray)
    }
    @Test fun layoutChangesInvalidateCachedPages() {
        val (store, _, _) = setup(); val key = store.load(id, "font20")["token"] as String
        store.save(id, "font20", key, intArrayOf(8))
        assertNull(store.load(id, "font32")["ends"])
        assertNotEquals(key, store.load(id, "font32")["token"])
    }
    @Test fun contentChangesRejectAnOldSaveToken() {
        val (store, books, _) = setup(); val key = store.load(id, "layout")["token"] as String
        File(books, "$id.txt").writeText("바뀐 내용")
        assertFalse(store.save(id, "layout", key, intArrayOf(8)))
        assertNull(store.load(id, "layout")["ends"])
        assertEquals("바뀐 내용", File(books, "$id.txt").readText())
    }
    @Test fun corruptedCacheIsIgnoredWithoutChangingBooks() {
        val (store, books, cache) = setup(); val key = store.load(id, "layout")["token"] as String
        store.save(id, "layout", key, intArrayOf(8))
        val file = cache.listFiles()!!.single(); val bytes = file.readBytes()
        bytes[8] = (bytes[8].toInt() xor 1).toByte(); file.writeBytes(bytes)
        assertNull(store.load(id, "layout")["ends"])
        assertFalse(file.exists()); assertEquals("읽을 책입니다.", File(books, "$id.txt").readText())
    }
    @Test fun invalidBoundariesAreNotWritten() {
        val (store, _, _) = setup(); val key = store.load(id, "layout")["token"] as String
        for (ends in listOf(intArrayOf(), intArrayOf(3, 2), intArrayOf(-1), intArrayOf(2, 2))) {
            assertFalse(store.save(id, "layout", key, ends))
        }
        assertNull(store.load(id, "layout")["ends"])
    }
    @Test fun cacheEvictionIsBoundedAndLeavesOtherFilesUntouched() {
        val (store, books, cache) = setup(); File(cache, "other.txt").writeText("keep")
        for (i in 0..15) {
            val layout = "layout$i"; val key = store.load(id, layout)["token"] as String
            assertTrue(store.save(id, layout, key, intArrayOf(8)))
        }
        assertTrue(cache.listFiles()!!.count { it.name.endsWith(".bin") } <= 12)
        assertNotNull(store.load(id, "layout15")["ends"])
        assertEquals("keep", File(cache, "other.txt").readText())
        assertEquals("읽을 책입니다.", File(books, "$id.txt").readText())
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsBookPathTraversal() {
        val (store, _, _) = setup(); store.load("../../other", "layout")
    }
}
