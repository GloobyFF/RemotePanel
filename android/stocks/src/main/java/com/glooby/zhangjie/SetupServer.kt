package com.glooby.zhangjie

import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean

/**
 * LAN page for the stock list, buy prices, share counts, and price alerts.
 * No password, same as the iPad kiosk setup page. Port 8091 so it does not
 * collide with RemotePanel on 8090.
 */
object SetupServer {
    const val PORT = 8091
    private val running = AtomicBoolean(false)
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var socket: ServerSocket? = null
    @Volatile var error: String = ""
        private set

    fun start() {
        if (!running.compareAndSet(false, true)) return
        Thread({
            try {
                val server = ServerSocket(PORT)
                socket = server
                error = ""
                while (running.get()) {
                    val client = runCatching { server.accept() }.getOrNull() ?: break
                    client.soTimeout = 8000
                    Thread { runCatching { handle(client) }; runCatching { client.close() } }.start()
                }
            } catch (e: Exception) {
                error = e.message ?: "设置服务没打开"
                running.set(false)
            }
        }, "zj-setup").apply { isDaemon = true }.start()
    }

    fun lanUrl(): String {
        val ip = lanIp()
        return if (ip.isEmpty()) "http://本机:$PORT" else "http://$ip:$PORT"
    }

    private fun lanIp(): String {
        val found = ArrayList<String>()
        runCatching {
            val ifaces = NetworkInterface.getNetworkInterfaces() ?: return@runCatching
            while (ifaces.hasMoreElements()) {
                val addrs = ifaces.nextElement().inetAddresses
                while (addrs.hasMoreElements()) {
                    val a = addrs.nextElement()
                    if (a is Inet4Address && !a.isLoopbackAddress) found += a.hostAddress.orEmpty()
                }
            }
        }
        return found.firstOrNull { it.startsWith("192.168.") || it.startsWith("10.") || it.startsWith("172.") }
            ?: found.firstOrNull().orEmpty()
    }

    private fun handle(client: java.net.Socket) {
        val input = BufferedInputStream(client.getInputStream())
        val raw = readHttp(input) ?: return
        val head = raw.first
        val body = raw.second
        val line = head.lineSequence().firstOrNull().orEmpty()
        val parts = line.split(' ')
        val method = parts.getOrNull(0).orEmpty()
        val path = parts.getOrNull(1)?.substringBefore('?').orEmpty()
        when {
            method == "GET" && (path == "/" || path == "/index.html") -> write(client, 200, "text/html; charset=utf-8", page().toByteArray(StandardCharsets.UTF_8))
            method == "GET" && path == "/setup.json" -> write(client, 200, "application/json; charset=utf-8", Store.document().toString().toByteArray(StandardCharsets.UTF_8))
            method == "POST" && path == "/setup" -> {
                val doc = runCatching { JSONObject(body) }.getOrNull()
                if (doc == null) {
                    write(client, 400, "text/plain; charset=utf-8", "需要 JSON".toByteArray())
                } else {
                    main.post { Store.applyDocument(doc) }
                    write(client, 200, "text/plain; charset=utf-8", "ok".toByteArray())
                }
            }
            else -> write(client, 404, "text/plain; charset=utf-8", "not found".toByteArray())
        }
    }

    private fun readHttp(input: BufferedInputStream): Pair<String, String>? {
        val header = ByteArrayOutputStream()
        var matched = 0
        val end = byteArrayOf(13, 10, 13, 10)
        while (header.size() < 16_000) {
            val b = input.read()
            if (b < 0) return null
            header.write(b)
            if (b == end[matched].toInt()) matched++ else matched = if (b == 13) 1 else 0
            if (matched == 4) break
        }
        if (matched != 4) return null
        val head = header.toString(StandardCharsets.UTF_8.name())
        val len = Regex("(?i)Content-Length:\\s*(\\d+)").find(head)?.groupValues?.get(1)?.toIntOrNull() ?: 0
        if (len <= 0) return head to ""
        if (len > 64_000) return null
        val buf = ByteArray(len)
        var off = 0
        while (off < len) {
            val n = input.read(buf, off, len - off)
            if (n < 0) break
            off += n
        }
        return head to String(buf, 0, off, StandardCharsets.UTF_8)
    }

    private fun write(client: java.net.Socket, code: Int, type: String, body: ByteArray) {
        val reason = if (code == 200) "OK" else if (code == 400) "Bad Request" else "Not Found"
        val head = "HTTP/1.1 $code $reason\r\nContent-Type: $type\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n"
        val out = client.getOutputStream()
        out.write(head.toByteArray(StandardCharsets.US_ASCII))
        out.write(body)
        out.flush()
    }

    private fun page(): String {
        val doc = Store.document()
        val holds = doc.getJSONArray("holdings")
        val rows = buildString {
            for (i in 0 until holds.length()) {
                val h = holds.getJSONObject(i)
                append(htmlRow(h.optString("code"), h.optString("name"), h.optDouble("buy"), h.optDouble("shares"), h.optDouble("above"), h.optDouble("below")))
            }
        }
        val sound = if (doc.optBoolean("alertSound", true)) "checked" else ""
        return """
<!DOCTYPE html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>张洁股票</title>
<style>
body{margin:0;background:#0B1220;color:#fff;font:18px/1.4 sans-serif}
main{max-width:920px;margin:0 auto;padding:24px}
h1{font-size:32px;margin:0 0 8px}
p{color:#9AA4B2;margin:0 0 18px}
label{display:block;color:#9AA4B2;font-size:14px;margin-bottom:4px}
input{background:#16233A;color:#fff;border:0;border-radius:8px;padding:10px 12px;font-size:18px;width:100%;box-sizing:border-box}
.row{display:grid;grid-template-columns:1.1fr 1.2fr .9fr .9fr .9fr .9fr auto;gap:8px;margin-bottom:10px;align-items:end}
.top{display:flex;gap:16px;flex-wrap:wrap;margin-bottom:18px}
.top>div{flex:1;min-width:140px}
button{background:#F0444C;color:#fff;border:0;border-radius:8px;padding:12px 16px;font-size:18px}
button.ghost{background:#16233A}
.msg{min-height:28px;margin-top:12px}
</style></head><body><main>
<h1>张洁股票</h1>
<p>代码用 6 位数字。买入价、股数、涨到、跌到留空就是不设。提醒每个方向每个交易日最多响一次。</p>
<div class="top">
  <div><label>汇总停留（秒）</label><input id="sum" inputmode="numeric" value="${doc.optInt("dwellSummary", 20)}"></div>
  <div><label>单只停留（秒）</label><input id="stock" inputmode="numeric" value="${doc.optInt("dwellStock", 12)}"></div>
  <div><label>价格提醒响铃</label><input id="sound" type="checkbox" $sound style="width:28px;height:28px"></div>
</div>
<div id="list">$rows</div>
<p><button class="ghost" type="button" onclick="addRow()">添加股票</button>
<button type="button" onclick="save()">保存</button></p>
<div class="msg" id="msg"></div>
<script>
function row(code,name,buy,shares,above,below){
  function v(n){return n?n:""}
  return '<div class="row">'+
    '<div><label>代码</label><input class="code" value="'+esc(code)+'"></div>'+
    '<div><label>名称</label><input class="name" value="'+esc(name)+'"></div>'+
    '<div><label>买入价</label><input class="buy" inputmode="decimal" value="'+v(buy)+'"></div>'+
    '<div><label>股数</label><input class="shares" inputmode="decimal" value="'+v(shares)+'"></div>'+
    '<div><label>涨到提醒</label><input class="above" inputmode="decimal" value="'+v(above)+'"></div>'+
    '<div><label>跌到提醒</label><input class="below" inputmode="decimal" value="'+v(below)+'"></div>'+
    '<button class="ghost" type="button" onclick="this.parentNode.remove()">删除</button></div>';
}
function esc(s){return String(s).replace(/&/g,"&amp;").replace(/"/g,"&quot;").replace(/</g,"&lt;")}
function addRow(){document.getElementById("list").insertAdjacentHTML("beforeend", row("","","","","",""))}
function num(el){var t=el.value.replace(/,/g,"").trim(); if(!t) return 0; var n=Number(t); return isFinite(n)&&n>0?n:0}
function save(){
  var holdings=[];
  document.querySelectorAll(".row").forEach(function(r){
    holdings.push({code:r.querySelector(".code").value.trim(), name:r.querySelector(".name").value.trim(),
      buy:num(r.querySelector(".buy")), shares:num(r.querySelector(".shares")),
      above:num(r.querySelector(".above")), below:num(r.querySelector(".below"))});
  });
  var body={dwellSummary:Number(document.getElementById("sum").value)||20,
    dwellStock:Number(document.getElementById("stock").value)||12,
    alertSound:document.getElementById("sound").checked, holdings:holdings};
  fetch("/setup",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)})
    .then(function(r){return r.text()})
    .then(function(t){document.getElementById("msg").textContent = t==="ok"?"已保存，屏幕会马上换上":t})
    .catch(function(){document.getElementById("msg").textContent="没保存上"});
}
</script>
</main></body></html>
        """.trimIndent()
    }

    private fun htmlRow(code: String, name: String, buy: Double, shares: Double, above: Double, below: Double): String {
        fun n(v: Double) = if (v > 0) v.toString().trimEnd('0').trimEnd('.') else ""
        return """<div class="row"><div><label>代码</label><input class="code" value="${esc(code)}"></div><div><label>名称</label><input class="name" value="${esc(name)}"></div><div><label>买入价</label><input class="buy" inputmode="decimal" value="${n(buy)}"></div><div><label>股数</label><input class="shares" inputmode="decimal" value="${n(shares)}"></div><div><label>涨到提醒</label><input class="above" inputmode="decimal" value="${n(above)}"></div><div><label>跌到提醒</label><input class="below" inputmode="decimal" value="${n(below)}"></div><button class="ghost" type="button" onclick="this.parentNode.remove()">删除</button></div>"""
    }

    private fun esc(s: String): String = s
        .replace("&", "&amp;")
        .replace("\"", "&quot;")
        .replace("<", "&lt;")
}
