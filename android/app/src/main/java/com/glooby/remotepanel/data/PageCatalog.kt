package com.glooby.remotepanel.data

data class PageDef(
    val id: String,
    val title: String,
    val defaultDwell: Int,
    val hasSource: Boolean = false,
    val sourceHint: String = "",
    val kind: Kind = Kind.BUILTIN
) {
    enum class Kind { BUILTIN, WEB }
}

object PageCatalog {
    /** P0 built-in pages shown in settings + roster when enabled. */
    fun builtins(): List<PageDef> = listOf(
        PageDef("hello", "问候海报", 60),
        PageDef("weather", "天气", 70, hasSource = true, sourceHint = "城市名，例如 Shanghai"),
        PageDef("daily-news", "每日新闻", 70, hasSource = true, sourceHint = "新闻 RSS"),
        PageDef("person-photo-local-1", "本地相册", 60),
    )

    fun sourceDefaults(): Map<String, String> = mapOf(
        "weather" to "Shanghai",
        "daily-news" to "https://www.chinanews.com.cn/rss/scroll-news.xml",
    )

    fun isWebId(id: String): Boolean = id.startsWith("web-")
}
