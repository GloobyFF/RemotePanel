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
    /** Built-in pages shown in settings + roster when enabled. */
    fun builtins(): List<PageDef> = listOf(
        PageDef("hello", "问候海报", 60),
        PageDef("weather", "天气", 70, hasSource = true, sourceHint = "城市名，例如 Shanghai"),
        PageDef("daily-news", "每日新闻", 70, hasSource = true, sourceHint = "新闻 RSS"),
        PageDef("stocks-cn", "国内股票", 70, hasSource = true, sourceHint = "股票代码，逗号分隔，如 600519,300750"),
        PageDef("crypto", "比特币", 70, hasSource = true, sourceHint = "币种，逗号分隔，如 btc,eth,sol"),
        PageDef("person-photo-local-1", "本地相册", 60),
    )

    fun sourceDefaults(): Map<String, String> = mapOf(
        "weather" to "Shanghai",
        "daily-news" to "https://www.chinanews.com.cn/rss/scroll-news.xml",
        "stocks-cn" to "600519,300750,600036,601318,002594",
        "crypto" to "btc,eth,sol,bnb,xrp",
    )

    fun isWebId(id: String): Boolean = id.startsWith("web-")
}
