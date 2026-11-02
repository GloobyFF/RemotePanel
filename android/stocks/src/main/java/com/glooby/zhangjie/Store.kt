package com.glooby.zhangjie

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class Holding(
    val code: String,
    var name: String,
    var buy: Double,
    var shares: Double,
    var above: Double,
    var below: Double,
)

data class Quote(
    val price: Double,
    val percent: Double,
    val change: Double,
    val at: Long,
    val name: String,
)

data class AlertHit(
    val code: String,
    val name: String,
    val above: Boolean,
    val limit: Double,
    val price: Double,
)

data class Brief(val title: String, val whenText: String, val source: String)

/** Holdings, last quotes, dwells, and once-per-day price alerts. Mirrors the iPad app. */
object Store {
    private const val PREF = "zhangjie"
    private const val K_HOLD = "holdings"
    private const val K_QUOTES = "quotes"
    private const val K_SUM = "dwellSummary"
    private const val K_STOCK = "dwellStock"
    private const val K_SRC = "source"
    private const val K_SOUND = "alertSound"
    private const val K_STATE = "alertState"

    private lateinit var prefs: android.content.SharedPreferences
    private val lock = Any()
    private val listeners = LinkedHashSet<() -> Unit>()
    private val news = HashMap<String, Pair<Long, List<Brief>>>()
    private val main = Handler(Looper.getMainLooper())
    private val zone: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")

    fun init(ctx: Context) {
        if (::prefs.isInitialized) return
        prefs = ctx.applicationContext.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        synchronized(lock) { if (!prefs.contains(K_HOLD)) saveHoldingsLocked(seed()) }
    }

    fun listen(fn: () -> Unit) = synchronized(listeners) { listeners += fn }
    fun unlisten(fn: () -> Unit) = synchronized(listeners) { listeners -= fn }

    private fun notifyChanged() {
        val copy = synchronized(listeners) { listeners.toList() }
        main.post { copy.forEach { runCatching { it() } } }
    }

    fun holdings(): List<Holding> = synchronized(lock) { readHoldings() }

    fun quote(code: String): Quote? = synchronized(lock) { readQuotes()[code] }

    fun briefs(code: String): List<Brief> = synchronized(lock) { news[code]?.second.orEmpty() }

    fun newsFresh(code: String): Boolean = synchronized(lock) {
        val row = news[code] ?: return false
        row.second.isNotEmpty() && System.currentTimeMillis() - row.first < 10 * 60 * 1000L
    }

    fun mergeNews(code: String, items: List<Brief>) {
        if (items.isEmpty()) return
        synchronized(lock) { news[code] = System.currentTimeMillis() to items.take(4) }
        notifyChanged()
    }

    fun quotes(): Map<String, Quote> = synchronized(lock) { readQuotes() }

    fun lastSource(): String = synchronized(lock) { prefs.getString(K_SRC, "").orEmpty() }

    fun dwellSummary(): Int = dwell(K_SUM, 20)
    fun dwellStock(): Int = dwell(K_STOCK, 12)

    fun alertSoundOn(): Boolean = synchronized(lock) {
        if (!prefs.contains(K_SOUND)) true else prefs.getBoolean(K_SOUND, true)
    }

    fun setAlertSound(on: Boolean) {
        synchronized(lock) { prefs.edit().putBoolean(K_SOUND, on).apply() }
        notifyChanged()
    }

    fun setDwells(summary: Int, stock: Int) {
        synchronized(lock) {
            prefs.edit()
                .putInt(K_SUM, summary.coerceIn(5, 600))
                .putInt(K_STOCK, stock.coerceIn(5, 600))
                .apply()
        }
        notifyChanged()
    }

    fun saveHoldings(list: List<Holding>) {
        synchronized(lock) { saveHoldingsLocked(list) }
        notifyChanged()
    }

    /** Write only the fields that are present, same idea as the iPad setup page. */
    fun applyDocument(doc: JSONObject) {
        synchronized(lock) {
            if (doc.has("dwellSummary") || doc.has("dwellStock")) {
                val sum = if (doc.has("dwellSummary")) doc.optInt("dwellSummary", 20) else dwellSummary()
                val stock = if (doc.has("dwellStock")) doc.optInt("dwellStock", 12) else dwellStock()
                prefs.edit()
                    .putInt(K_SUM, sum.coerceIn(5, 600))
                    .putInt(K_STOCK, stock.coerceIn(5, 600))
                    .apply()
            }
            if (doc.has("alertSound")) prefs.edit().putBoolean(K_SOUND, doc.optBoolean("alertSound", true)).apply()
            if (doc.has("holdings")) {
                val arr = doc.optJSONArray("holdings") ?: JSONArray()
                val next = ArrayList<Holding>()
                val seen = HashSet<String>()
                for (i in 0 until arr.length()) {
                    val row = arr.optJSONObject(i) ?: continue
                    val code = Quotes.codeForToken(row.optString("code")) ?: continue
                    if (!seen.add(code)) continue
                    val name = row.optString("name").trim().ifEmpty { code }
                    next += Holding(
                        code = code,
                        name = name,
                        buy = row.optDouble("buy", 0.0).coerceAtLeast(0.0),
                        shares = row.optDouble("shares", 0.0).coerceAtLeast(0.0),
                        above = row.optDouble("above", 0.0).coerceAtLeast(0.0),
                        below = row.optDouble("below", 0.0).coerceAtLeast(0.0),
                    )
                    if (next.size >= 40) break
                }
                saveHoldingsLocked(next)
            }
        }
        notifyChanged()
    }

    fun document(): JSONObject = synchronized(lock) {
        val holds = JSONArray()
        readHoldings().forEach { h ->
            holds.put(JSONObject()
                .put("code", h.code)
                .put("name", h.name)
                .put("buy", h.buy)
                .put("shares", h.shares)
                .put("above", h.above)
                .put("below", h.below))
        }
        JSONObject()
            .put("dwellSummary", dwell(K_SUM, 20))
            .put("dwellStock", dwell(K_STOCK, 12))
            .put("alertSound", if (!prefs.contains(K_SOUND)) true else prefs.getBoolean(K_SOUND, true))
            .put("holdings", holds)
    }

    fun merge(rows: List<QuoteRow>, source: String) {
        synchronized(lock) {
            val all = JSONObject(prefs.getString(K_QUOTES, null) ?: "{}")
            val holds = readHoldings().toMutableList()
            var renamed = false
            val now = System.currentTimeMillis()
            for (row in rows) {
                if (row.price <= 0 || row.code.length != 6) continue
                all.put(row.code, JSONObject()
                    .put("price", row.price)
                    .put("percent", row.percent)
                    .put("change", row.change)
                    .put("at", now)
                    .put("name", row.name))
                if (row.name.isNotBlank()) {
                    holds.forEach {
                        if (it.code == row.code && it.name != row.name) {
                            it.name = row.name
                            renamed = true
                        }
                    }
                }
            }
            prefs.edit().putString(K_QUOTES, all.toString()).putString(K_SRC, source).apply()
            if (renamed) saveHoldingsLocked(holds)
        }
        notifyChanged()
    }

    /**
     * Fire when the price reaches a limit, once per Shanghai trading day.
     * Re-arm after the price moves back by 0.5% of the limit.
     * A quote older than 30 minutes cannot fire (yesterday's close at 9:00).
     */
    fun checkAlerts(): List<AlertHit> {
        val today = tradingDay()
        val now = System.currentTimeMillis()
        val fired = ArrayList<AlertHit>()
        synchronized(lock) {
            val state = JSONObject(prefs.getString(K_STATE, null) ?: "{}")
            for (h in readHoldings()) {
                val q = readQuotes()[h.code] ?: continue
                if (q.price <= 0 || now - q.at > 30 * 60 * 1000L) continue
                val side = state.optJSONObject(h.code) ?: JSONObject()
                checkSide(h, q, today, above = true, side, fired)
                checkSide(h, q, today, above = false, side, fired)
                state.put(h.code, side)
            }
            prefs.edit().putString(K_STATE, state.toString()).apply()
        }
        return fired
    }

    private fun checkSide(
        h: Holding,
        q: Quote,
        today: String,
        above: Boolean,
        side: JSONObject,
        fired: MutableList<AlertHit>,
    ) {
        val key = if (above) "above" else "below"
        val limit = if (above) h.above else h.below
        if (limit <= 0) {
            side.remove(key)
            return
        }
        val crossed = if (above) q.price >= limit else q.price <= limit
        val band = limit * 0.005
        val clear = if (above) q.price < limit - band else q.price > limit + band
        val firedOn = side.optString(key)
        if (crossed && firedOn != today) {
            fired += AlertHit(h.code, h.name.ifBlank { h.code }, above, limit, q.price)
            side.put(key, today)
        } else if (clear && firedOn.isNotEmpty()) {
            side.put(key, "")
        }
    }

    fun marketIsOpen(): Boolean = inWindow(openAm = 9 * 60 + 30, closeAm = 11 * 60 + 30, openPm = 13 * 60, closePm = 15 * 60)

    /** Opening auction from 9:15, and keep fetching until 15:05 so the close is seen. */
    fun shouldFetch(): Boolean = inWindow(openAm = 9 * 60 + 15, closeAm = 11 * 60 + 35, openPm = 12 * 60 + 55, closePm = 15 * 60 + 5)

    fun sessionTitle(): String = if (marketIsOpen()) "交易中 · 每分钟更新" else "未开盘 · 最后成交"

    fun sessionShort(): String = if (marketIsOpen()) "交易中" else "未开盘"

    private fun inWindow(openAm: Int, closeAm: Int, openPm: Int, closePm: Int): Boolean {
        val cal = Calendar.getInstance(zone, Locale.US)
        val day = cal.get(Calendar.DAY_OF_WEEK)
        if (day == Calendar.SUNDAY || day == Calendar.SATURDAY) return false
        val m = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        return (m in openAm until closeAm) || (m in openPm until closePm)
    }

    private fun tradingDay(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        fmt.timeZone = zone
        return fmt.format(Date())
    }

    private fun dwell(key: String, fallback: Int): Int {
        val n = synchronized(lock) { prefs.getInt(key, 0) }
        return if (n < 5) fallback else n.coerceAtMost(600)
    }

    private fun seed(): List<Holding> = listOf(
        Holding("600519", "贵州茅台", 0.0, 0.0, 0.0, 0.0),
        Holding("300750", "宁德时代", 0.0, 0.0, 0.0, 0.0),
        Holding("600036", "招商银行", 0.0, 0.0, 0.0, 0.0),
        Holding("601318", "中国平安", 0.0, 0.0, 0.0, 0.0),
        Holding("002594", "比亚迪", 0.0, 0.0, 0.0, 0.0),
    )

    private fun readHoldings(): List<Holding> {
        val arr = JSONArray(prefs.getString(K_HOLD, null) ?: "[]")
        val out = ArrayList<Holding>()
        for (i in 0 until arr.length()) {
            val row = arr.optJSONObject(i) ?: continue
            val code = row.optString("code")
            if (code.length != 6) continue
            val name = row.optString("name").ifBlank { code }
            out += Holding(
                code, name,
                row.optDouble("buy", 0.0),
                row.optDouble("shares", 0.0),
                row.optDouble("above", 0.0),
                row.optDouble("below", 0.0),
            )
        }
        return out
    }

    private fun readQuotes(): Map<String, Quote> {
        val obj = JSONObject(prefs.getString(K_QUOTES, null) ?: "{}")
        val out = LinkedHashMap<String, Quote>()
        val it = obj.keys()
        while (it.hasNext()) {
            val code = it.next()
            val row = obj.optJSONObject(code) ?: continue
            val price = row.optDouble("price", 0.0)
            if (price <= 0) continue
            out[code] = Quote(price, row.optDouble("percent", 0.0), row.optDouble("change", 0.0), row.optLong("at"), row.optString("name"))
        }
        return out
    }

    private fun saveHoldingsLocked(list: List<Holding>) {
        val arr = JSONArray()
        val seen = HashSet<String>()
        for (h in list) {
            if (h.code.length != 6 || !seen.add(h.code)) continue
            arr.put(JSONObject()
                .put("code", h.code)
                .put("name", h.name.ifBlank { h.code })
                .put("buy", h.buy.coerceAtLeast(0.0))
                .put("shares", h.shares.coerceAtLeast(0.0))
                .put("above", h.above.coerceAtLeast(0.0))
                .put("below", h.below.coerceAtLeast(0.0)))
        }
        prefs.edit().putString(K_HOLD, arr.toString()).apply()
    }
}

data class QuoteRow(val code: String, val name: String, val price: Double, val percent: Double, val change: Double)
