package com.glooby.remotepanel.data

import com.glooby.remotepanel.net.HttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean

object FeedRepository {
    @Volatile
    var lastState: PanelState = PanelState()
        private set

    private val busy = AtomicBoolean(false)
    private val lock = Any()

    /**
     * Fetch every enabled source in parallel. [onPartial] runs (on a background thread) each time one
     * source lands, so pages fill in as data arrives instead of waiting for the slowest host.
     */
    suspend fun refresh(onPartial: (PanelState) -> Unit = {}): PanelState = withContext(Dispatchers.IO) {
        if (!busy.compareAndSet(false, true)) return@withContext lastState
        try {
            val errors = Collections.synchronizedList(mutableListOf<String>())
            fun put(update: (PanelState) -> PanelState) {
                val next = synchronized(lock) {
                    update(lastState).copy(fetchedAt = FeedCache.ages()).also { lastState = it }
                }
                onPartial(next)
            }
            coroutineScope {
                fun <T> job(name: String, fetch: () -> T?, apply: (PanelState, T) -> PanelState) = async {
                    val v = runCatching { fetch() }.onFailure { errors += "$name: ${it.message ?: "失败"}" }.getOrNull()
                    if (v != null) put { apply(it, v) }
                }
                val weather = async {
                    runCatching { Feeds.weather() }.onFailure { errors += "天气: ${it.message ?: "失败"}" }.getOrNull()
                        ?.also { w -> put { it.copy(weather = w) } }
                }
                val jobs = listOf(
                    job("新闻", { Feeds.news() }) { s, v -> s.copy(dailyNews = v) },
                    job("股票", { Feeds.stocks() }) { s, v -> s.copy(stocks = v) },
                    job("加密", { Feeds.crypto() }) { s, v -> s.copy(crypto = v) },
                    job("GitHub", { MoreFeeds.github() }) { s, v -> s.copy(github = v) },
                    job("X", { MoreFeeds.trends() }) { s, v -> s.copy(trends = v) },
                    job("小红书", { MoreFeeds.xiaohongshu() }) { s, v -> s.copy(xhs = v) },
                    job("哔哩哔哩", { MoreFeeds.bilibili() }) { s, v -> s.copy(bili = v) },
                    job("电影", { MoreFeeds.movies() }) { s, v -> s.copy(movies = v) },
                    job("Steam", { MoreFeeds.steam() }) { s, v -> s.copy(steam = v) },
                    job("PC", { MoreFeeds.covers("gamer520-pc-latest", "pc") }) { s, v -> s.copy(pcGames = v) },
                    job("Switch", { MoreFeeds.covers("gamer520-switch-latest", "switch") }) { s, v -> s.copy(switchGames = v) },
                    job("PS5", { MoreFeeds.covers("ps5-games-latest", "ps5") }) { s, v -> s.copy(ps5Games = v) },
                    job("VPS", { MoreFeeds.vps() }) { s, v -> s.copy(vps = v) },
                    job("打印机", { MoreFeeds.printer() }) { s, v -> s.copy(printer = v) },
                    async {
                        val w = weather.await()
                        val (period, slot) = helloSlot()
                        put { it.copy(helloPeriod = period) }
                        val line = runCatching { helloLine(period, slot, w) }.onFailure { errors += "问候: ${it.message ?: "失败"}" }.getOrNull()
                        if (!line.isNullOrBlank()) put { it.copy(hello = line) }
                    },
                )
                jobs.awaitAll()
            }
            synchronized(lock) {
                lastState = lastState.copy(fetchedAt = FeedCache.ages(), errors = errors.toList())
                lastState
            }
        } finally {
            busy.set(false)
        }
    }

    /** “早上好 / 中午好 / 晚上好” and a cache slot per day and period (before 5:00 counts as last evening). */
    fun helloSlot(): Pair<String, String> {
        val c = Calendar.getInstance()
        val h = c.get(Calendar.HOUR_OF_DAY)
        val period = when (h) {
            in 5..10 -> "早上好"
            in 11..16 -> "中午好"
            else -> "晚上好"
        }
        if (h < 5) c.add(Calendar.DAY_OF_YEAR, -1)
        return period to "${c.get(Calendar.YEAR)}-${c.get(Calendar.DAY_OF_YEAR)}-$period"
    }

    /** One AI-written line per period when a key is set; null otherwise (the page writes its own tip). */
    private fun helloLine(period: String, slot: String, w: WeatherState?): String? {
        if (!Prefs.pageEnabled("hello")) return null
        val key = Prefs.helloKey().ifEmpty { return null }
        return FeedCache.get("hello:$slot", 12 * 3600_000L) {
            val base = Prefs.sourceUrl("hello").ifBlank { "https://apiclaude.cc" }.trimEnd('/')
            val today = w?.daily?.firstOrNull()
            val weatherNote = if (w != null && today != null)
                "天气：${w.city}${Wmo.text(w.code)}，现在${w.temp.toInt()}度，今天${today.low.toInt()}到${today.high.toInt()}度，降水概率${today.rainChance}%。"
            else ""
            val prompt = "现在是$period。$weatherNote 用一句中文跟家人打招呼并给一个贴心提醒，25到45个字，不要标题，不要引号。"
            val body = JSONObject()
                .put("model", Prefs.helloModel())
                .put("messages", JSONArray().put(JSONObject().put("role", "user").put("content", prompt)))
            val raw = HttpClient.postJson("$base/v1/chat/completions", body.toString(), mapOf("Authorization" to "Bearer $key"))
            JSONObject(raw).optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")?.optString("content")
                ?.trim()?.trim('"', '“', '”')?.ifBlank { null } ?: error("AI 没有返回内容")
        }
    }
}
