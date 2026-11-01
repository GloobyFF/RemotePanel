package com.glooby.remotepanel.data

import java.util.concurrent.ConcurrentHashMap

/**
 * In-memory feed cache.
 * - Fresh values are reused until their TTL runs out.
 * - After a failed fetch the key waits [backoffMs] before trying again, instead of on every 30 s poll.
 * - When a refetch fails, the last good value keeps showing (stale) rather than blanking the page.
 */
object FeedCache {
    private class Entry(
        val value: Any?,
        val fetchedAt: Long,
        val failedAt: Long,
        val error: String?,
        val expired: Boolean = false,
    )

    private val map = ConcurrentHashMap<String, Entry>()
    private const val backoffMs = 3 * 60_000L

    fun <T : Any> get(key: String, ttlMs: Long, fetch: () -> T): T? {
        val now = System.currentTimeMillis()
        val hit = map[key]
        @Suppress("UNCHECKED_CAST")
        val last = hit?.value as T?
        if (hit != null && !hit.expired && last != null && now - hit.fetchedAt < ttlMs) return last
        if (hit != null && !hit.expired && now - hit.failedAt < backoffMs) return last
        return try {
            val value = fetch()
            map[key] = Entry(value, now, 0L, null)
            value
        } catch (t: Throwable) {
            map[key] = Entry(last, hit?.fetchedAt ?: 0L, now, t.message ?: t.javaClass.simpleName)
            if (last == null) throw t
            last
        }
    }

    fun ages(): Map<String, Long> = map.mapValues { it.value.fetchedAt }.filterValues { it > 0L }

    /** Keys whose most recent attempt failed, with the reason. */
    fun failures(): Map<String, String> =
        map.filterValues { it.error != null && it.failedAt >= it.fetchedAt }.mapValues { it.value.error.orEmpty() }

    /** Force a refetch on the next refresh (after settings change) but keep showing current data. */
    fun expireAll() {
        for ((k, e) in map) map[k] = Entry(e.value, e.fetchedAt, 0L, null, expired = true)
    }
}
