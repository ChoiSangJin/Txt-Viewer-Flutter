package com.choisangjin.txtviewer

import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.charset.Charset

class TextDecoderTest {
    private fun read(bytes: ByteArray, limit: Int = 1000) = bytes.inputStream().use { TextDecoder.read(it, limit) }
    @Test fun utf8AndLineEndings() {
        assertEquals("한글 English 📖\n다음\n끝", read("\uFEFF한글 English 📖\r\n다음\r끝".toByteArray()))
    }
    @Test fun utf16BothByteOrders() {
        for (charset in listOf(Charsets.UTF_16LE, Charsets.UTF_16BE)) {
            assertEquals("한글 English", read("\uFEFF한글 English".toByteArray(charset)))
        }
    }
    @Test fun legacyKorean() {
        assertEquals("오래된 소설입니다.", read("오래된 소설입니다.".toByteArray(Charset.forName("MS949"))))
    }
    @Test(expected = IllegalArgumentException::class) fun emptyRejected() { read(byteArrayOf()) }
    @Test(expected = IllegalArgumentException::class) fun binaryRejected() { read(byteArrayOf(0, 0, 1, 0)) }
    @Test(expected = IllegalArgumentException::class) fun oversizedRejected() { read(ByteArray(101) { 65 }, 100) }
    @Test fun exactSizeLimitAccepted() { assertEquals("AAA", read(byteArrayOf(65, 65, 65), 3)) }
    @Test(expected = java.nio.charset.CharacterCodingException::class)
    fun malformedUtf16Rejected() { read(byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 65)) }
}
