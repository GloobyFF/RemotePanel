package com.glooby.zhangjie

import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.nio.charset.Charset
import java.util.concurrent.TimeUnit

object Quotes {
    private val client = OkHttpClient.Builder()
        .callTimeout(12, TimeUnit.SECONDS)
        .build()
    private val gbk: Charset = Charset.forName("GB18030")

    fun codeForToken(token: String?): String? {
        var s = token?.trim()?.lowercase().orEmpty().replace(".", "")
        if (s.startsWith("sh") || s.startsWith("sz") || s.startsWith("bj")) {
            if (s.length <= 2) return null
            s = s.substring(2)
        }
        if (s.length != 6 || s.any { !it.isDigit() }) return null
        return s
    }

    /** Eastmoney first. On any failure, the same codes are asked from Tencent. */
    fun refresh(): Result<String> {
        val holds = Store.holdings()
        val codes = holds.map { it.code }.filter { it.length == 6 }
        if (codes.isEmpty()) return Result.failure(IllegalStateException("还没有股票"))
        val east = fetch(eastmoneyUrl(codes))
        val parsed = east?.let { parseEastmoney(it, codes) }.orEmpty()
        if (parsed.isNotEmpty()) {
            Store.merge(parsed, "东方财富")
            return Result.success("东方财富")
        }
        val backup = fetch(tencentUrl(codes))
        val more = backup?.let { parseTencent(it, codes) }.orEmpty()
        if (more.isNotEmpty()) {
            Store.merge(more, "腾讯")
            return Result.success("腾讯")
        }
        return Result.failure(IllegalStateException("东方财富和腾讯行情都没连上"))
    }

    /** Latest headlines for each holding. Failures keep the previous list. */
    fun refreshNews() {
        val codes = Store.holdings().map { it.code }.filter { it.length == 6 && !Store.newsFresh(it) }
        for (code in codes) {
            val items = fetchNews(code)
            if (items.isNotEmpty()) Store.mergeNews(code, items)
        }
    }

    private fun fetchNews(code: String): List<Brief> {
        val market = if (code[0] == '6' || code[0] == '5' || code[0] == '9') "1" else "0"
        val url = "https://np-listapi.eastmoney.com/comm/wap/getListInfo?client=wap&type=1&mTypeAndCode=$market.$code&pageSize=4&pageIndex=1"
        val text = fetch(url) ?: return emptyList()
        val list = runCatching { JSONObject(text).optJSONObject("data")?.optJSONArray("list") }.getOrNull() ?: return emptyList()
        val out = ArrayList<Brief>()
        for (i in 0 until list.length()) {
            val row = list.optJSONObject(i) ?: continue
            val title = row.optString("Art_Title").trim()
            if (title.isEmpty()) continue
            val raw = row.optString("Art_ShowTime").trim()
            val whenText = if (raw.length >= 16) raw.substring(5, 16) else raw
            out += Brief(title, whenText, row.optString("Art_MediaName").trim())
            if (out.size >= 4) break
        }
        return out
    }

    private fun eastmoneyUrl(codes: List<String>): String {
        val secids = codes.joinToString(",") { code ->
            val market = if (code[0] == '6' || code[0] == '5' || code[0] == '9') "1" else "0"
            "$market.$code"
        }
        return "https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&fields=f2,f3,f4,f12,f14&secids=$secids"
    }

    private fun tencentUrl(codes: List<String>): String {
        val keys = codes.joinToString(",") { code ->
            val market = when (code[0]) {
                '6', '5', '9' -> "sh"
                '8', '4' -> "bj"
                else -> "sz"
            }
            market + code
        }
        return "https://qt.gtimg.cn/q=$keys"
    }

    private fun fetch(url: String): String? {
        val req = Request.Builder().url(url).header("User-Agent", "ZhangJieStocks/1.0").build()
        return runCatching {
            client.newCall(req).execute().use { res ->
                if (!res.isSuccessful) return null
                val bytes = res.body?.bytes() ?: return null
                if (bytes.isEmpty()) return null
                if (url.contains("gtimg.cn")) String(bytes, gbk) else String(bytes, Charsets.UTF_8)
            }
        }.getOrNull()
    }

    private fun parseEastmoney(text: String, codes: List<String>): List<QuoteRow> {
        val diff = runCatching { JSONObject(text).optJSONObject("data")?.optJSONArray("diff") }.getOrNull() ?: return emptyList()
        val byCode = HashMap<String, QuoteRow>()
        for (i in 0 until diff.length()) {
            val row = diff.optJSONObject(i) ?: continue
            val code = row.opt("f12")?.toString().orEmpty()
            if (code.length != 6) continue
            val price = row.optDouble("f2", 0.0)
            if (price <= 0) continue
            val name = row.opt("f14")?.toString().orEmpty().ifBlank { code }
            byCode[code] = QuoteRow(code, name, price, row.optDouble("f3", 0.0), row.optDouble("f4", 0.0))
        }
        return codes.mapNotNull { byCode[it] }
    }

    /** v_sh600519="1~贵州茅台~600519~price~…~31 change~32 percent~…"; */
    private fun parseTencent(text: String, codes: List<String>): List<QuoteRow> {
        val byCode = HashMap<String, QuoteRow>()
        for (line in text.split(';')) {
            val q1 = line.indexOf('"')
            val q2 = line.lastIndexOf('"')
            if (q1 < 0 || q2 <= q1) continue
            val fields = line.substring(q1 + 1, q2).split('~')
            if (fields.size < 33) continue
            val code = fields[2]
            val price = fields[3].toDoubleOrNull() ?: 0.0
            if (code.length != 6 || price <= 0) continue
            val name = fields[1].ifBlank { code }
            byCode[code] = QuoteRow(
                code, name, price,
                fields[32].toDoubleOrNull() ?: 0.0,
                fields[31].toDoubleOrNull() ?: 0.0,
            )
        }
        return codes.mapNotNull { byCode[it] }
    }
}
