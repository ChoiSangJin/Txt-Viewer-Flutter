package com.choisangjin.txtviewer

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/** Strict decoding avoids silently corrupting Korean text; input stays bounded. */
object TextDecoder {
    const val MAX_BYTES = 10 * 1024 * 1024

    fun read(input: InputStream, limit: Int = MAX_BYTES): String {
        val output = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        while (output.size() <= limit) {
            val count = input.read(chunk, 0, minOf(chunk.size, limit + 1 - output.size()))
            if (count < 0) break
            output.write(chunk, 0, count)
        }
        require(output.size() <= limit) { "10MB 이하의 TXT 파일을 선택해 주세요." }
        val text = decode(output.toByteArray()).replace("\r\n", "\n")
            .replace('\r', '\n').removePrefix("\uFEFF")
        require(text.isNotBlank()) { "비어 있는 TXT 파일입니다." }
        require(!text.contains('\u0000')) { "지원하지 않는 텍스트 형식입니다." }
        return text
    }

    private fun decode(bytes: ByteArray): String {
        val charset = when {
            bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte() -> Charsets.UTF_16LE
            bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte() -> Charsets.UTF_16BE
            else -> Charsets.UTF_8
        }
        fun strict(cs: Charset) = cs.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        return try { strict(charset) } catch (e: java.nio.charset.CharacterCodingException) {
            if (charset != Charsets.UTF_8) throw e
            strict(Charset.forName("MS949"))
        }
    }
}
