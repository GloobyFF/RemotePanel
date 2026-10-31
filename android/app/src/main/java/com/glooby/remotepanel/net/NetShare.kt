package com.glooby.remotepanel.net

import com.glooby.remotepanel.data.Prefs
import jcifs.config.PropertyConfiguration
import jcifs.context.BaseContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import jcifs.smb.SmbRandomAccessFile
import java.io.ByteArrayOutputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.Properties

object NetShare {
    data class FileRef(val name: String, val url: String, val size: Long)

    private val imageExt = setOf("jpg", "jpeg", "png", "webp", "gif")
    private val videoExt = setOf("mp4", "m4v", "mov", "mkv", "3gp")

    fun listImages(dir: String): List<FileRef> = list(dir, imageExt)
    fun listVideos(dir: String): List<FileRef> = list(dir, videoExt)

    private fun list(dir: String, exts: Set<String>): List<FileRef> {
        val url = dir.trim()
        if (url.isEmpty()) return emptyList()
        return if (url.startsWith("http://") || url.startsWith("https://")) {
            listHttp(url, exts)
        } else {
            listSmb(url, exts)
        }
    }

    private fun context() = buildContext()

    private fun buildContext(): jcifs.CIFSContext {
        val props = Properties()
        props.setProperty("jcifs.smb.client.enableSMB2", "true")
        props.setProperty("jcifs.smb.client.disableSMB1", "false")
        props.setProperty("jcifs.smb.client.ipcSigningEnforced", "false")
        props.setProperty("jcifs.smb.client.dfs.disabled", "true")
        val base = BaseContext(PropertyConfiguration(props))
        val user = Prefs.shareUser()
        val pass = Prefs.sharePass()
        if (user.isEmpty() && pass.isEmpty()) return base
        return base.withCredentials(NtlmPasswordAuthenticator("", user, pass))
    }

    private fun listSmb(dir: String, exts: Set<String>): List<FileRef> {
        val url = if (dir.endsWith("/")) dir else "$dir/"
        val folder = SmbFile(url, context())
        val files = folder.listFiles() ?: return emptyList()
        return files.mapNotNull { file ->
            val name = file.name.trim().trimEnd('/')
            val ext = name.substringAfterLast('.', "").lowercase()
            if (name.isBlank() || file.isDirectory || ext !in exts) return@mapNotNull null
            val child = if (url.endsWith("/")) url + name else "$url/$name"
            FileRef(name, child, runCatching { file.length() }.getOrDefault(0L))
        }
    }

    private fun listHttp(dir: String, exts: Set<String>): List<FileRef> {
        val html = HttpClient.getString(dir)
        val base = if (dir.endsWith("/")) dir else dir.substringBeforeLast('/') + "/"
        val found = LinkedHashSet<String>()
        Regex("""href=["']([^"']+)["']""", RegexOption.IGNORE_CASE).findAll(html).forEach { m ->
            var href = m.groupValues[1]
            if (href.startsWith("?") || href.startsWith("#")) return@forEach
            if (href.startsWith("./")) href = href.removePrefix("./")
            val full = when {
                href.startsWith("http://") || href.startsWith("https://") -> href
                href.startsWith("/") -> {
                    val root = Regex("""https?://[^/]+""").find(dir)?.value ?: return@forEach
                    root + href
                }
                else -> base + href
            }
            val path = full.substringBefore("?").substringBefore("#")
            val ext = path.substringAfterLast('.', "").lowercase()
            if (ext in exts) found += path
        }
        return found.map { FileRef(it.substringAfterLast('/'), it, 0L) }
    }

    fun readBytes(url: String, max: Int = 8 * 1024 * 1024): ByteArray {
        if (url.startsWith("http://") || url.startsWith("https://")) {
            val bytes = HttpClient.getBytes(url)
            return if (bytes.size <= max) bytes else bytes.copyOf(max)
        }
        SmbFile(url, context()).inputStream.use { input ->
            val out = ByteArrayOutputStream()
            val buf = ByteArray(16 * 1024)
            var left = max
            while (left > 0) {
                val n = input.read(buf, 0, minOf(buf.size, left))
                if (n < 0) break
                out.write(buf, 0, n)
                left -= n
            }
            return out.toByteArray()
        }
    }

    fun length(url: String): Long = SmbFile(url, context()).length()

    fun open(url: String): SmbRandomAccessFile = SmbRandomAccessFile(SmbFile(url, context()), "r")
}

class SmbStreamServer {
    @Volatile private var socket: ServerSocket? = null

    fun start(fileUrl: String): String {
        stop()
        val server = ServerSocket(0)
        socket = server
        Thread({
            while (!server.isClosed) {
                try {
                    val client = server.accept()
                    Thread { serve(client, fileUrl) }.apply { isDaemon = true }.start()
                } catch (_: Exception) {
                    break
                }
            }
        }, "smb-stream").apply { isDaemon = true }.start()
        return "http://127.0.0.1:${server.localPort}/video.mp4"
    }

    fun stop() {
        runCatching { socket?.close() }
        socket = null
    }

    private fun serve(client: Socket, fileUrl: String) {
        var raf: SmbRandomAccessFile? = null
        try {
            client.soTimeout = 30_000
            val input = client.getInputStream()
            val headerBuf = java.io.ByteArrayOutputStream()
            while (headerBuf.size() < 8192) {
                val b = input.read()
                if (b < 0) return
                headerBuf.write(b)
                val n = headerBuf.size()
                if (n >= 4) {
                    val raw = headerBuf.toByteArray()
                    if (raw[n - 4] == 13.toByte() && raw[n - 3] == 10.toByte() &&
                        raw[n - 2] == 13.toByte() && raw[n - 1] == 10.toByte()
                    ) break
                }
            }
            val header = headerBuf.toString("ISO-8859-1")
            val range = Regex("""Range: bytes=(\d+)-""", RegexOption.IGNORE_CASE)
                .find(header)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
            val len = NetShare.length(fileUrl)
            raf = NetShare.open(fileUrl)
            if (range > 0) raf.seek(range)
            val rest = (len - range).coerceAtLeast(0)
            val status = if (range > 0) "206 Partial Content" else "200 OK"
            val head = buildString {
                append("HTTP/1.1 $status\r\n")
                append("Content-Type: video/mp4\r\n")
                append("Accept-Ranges: bytes\r\n")
                append("Content-Length: $rest\r\n")
                if (range > 0 && len > 0) append("Content-Range: bytes $range-${len - 1}/$len\r\n")
                append("Connection: close\r\n\r\n")
            }
            val out = client.getOutputStream()
            out.write(head.toByteArray())
            val buf = ByteArray(64 * 1024)
            var left = if (len > 0) rest else Long.MAX_VALUE
            while (left > 0) {
                val want = minOf(buf.size.toLong(), left).toInt()
                val n = raf.read(buf, 0, want)
                if (n <= 0) break
                out.write(buf, 0, n)
                left -= n
            }
            out.flush()
        } catch (_: Exception) {
        } finally {
            runCatching { raf?.close() }
            runCatching { client.close() }
        }
    }
}
