package com.glooby.remotepanel.data

data class PageDef(
    val id: String,
    val title: String,
    val defaultDwell: Int,
    val hasSource: Boolean = false,
    val sourceHint: String = "",
    val defaultOn: Boolean = true,
    val defaultProxy: Boolean = false,
    val kind: Kind = Kind.BUILTIN
) {
    enum class Kind { BUILTIN, WEB }
}

object PageCatalog {
    /** Same roster as the iPad app. Photos and video stay off until turned on. */
    fun builtins(): List<PageDef> = listOf(
        PageDef("hello", "问候海报", 60, hasSource = true, sourceHint = "AI 接口，例如 https://apiclaude.cc"),
        PageDef("schedule", "日程与提醒", 60, hasSource = true, sourceHint = "ICS 订阅，可留空"),
        PageDef("weather", "天气+VPS", 70, hasSource = true, sourceHint = "城市名，例如 Shanghai"),
        PageDef("daily-news", "每日新闻", 70, hasSource = true, sourceHint = "新闻 RSS"),
        PageDef("github-news", "AI·热门项目", 70, hasSource = true, sourceHint = "GitHub 接口", defaultProxy = true),
        PageDef("x-news", "X · 动态", 60, hasSource = true, sourceHint = "热门话题页，也可换成 RSS", defaultProxy = true),
        PageDef("xiaohongshu-hot", "小红书热门", 60, hasSource = true, sourceHint = "小红书热榜页面", defaultProxy = true),
        PageDef("bilibili-hot", "哔哩哔哩热门", 60, hasSource = true, sourceHint = "哔哩哔哩热门接口"),
        PageDef("stocks-cn", "国内股票", 70, hasSource = true, sourceHint = "股票代码，逗号分隔，如 600519,300750"),
        PageDef("crypto", "比特币", 70, hasSource = true, sourceHint = "币种，逗号分隔，如 btc,eth,sol", defaultProxy = true),
        PageDef("person-photo-local-1", "照片", 60, defaultOn = false),
        PageDef("print", "打印机", 75, hasSource = true, sourceHint = "打印机 JSON 接口"),
        PageDef("movie-now-showing", "最近上映", 35, hasSource = true, sourceHint = "电影接口"),
        PageDef("steam-new-releases", "Steam 新游", 60, hasSource = true, sourceHint = "Steam 接口", defaultProxy = true),
        PageDef("steam-new-releases-2", "Steam 热销", 60, hasSource = true, sourceHint = "与 Steam 新游共用接口", defaultProxy = true),
        PageDef("gamer520-pc-latest", "PC 游戏上新", 60, hasSource = true, sourceHint = "PC 游戏页面", defaultProxy = true),
        PageDef("person-photo-local-2", "照片 2", 60, defaultOn = false),
        PageDef("gamer520-switch-latest", "Switch 上新", 60, hasSource = true, sourceHint = "Switch 游戏页面", defaultProxy = true),
        PageDef("ps5-games-latest", "PS5 上新", 60, hasSource = true, sourceHint = "PS5 游戏页面", defaultProxy = true),
        PageDef("local-video", "视频", 12, defaultOn = false),
    )

    fun byId(id: String): PageDef? = builtins().firstOrNull { it.id == id }

    fun defaultOn(id: String): Boolean = byId(id)?.defaultOn ?: true

    fun defaultProxy(id: String): Boolean = byId(id)?.defaultProxy ?: false

    fun sourceDefaults(): Map<String, String> = mapOf(
        "hello" to "https://apiclaude.cc",
        "weather" to "Shanghai",
        "daily-news" to "https://www.chinanews.com.cn/rss/scroll-news.xml",
        "github-news" to "https://api.github.com/search/repositories",
        "print" to "http://192.168.28.126:8088/api/printers",
        "movie-now-showing" to "https://m.maoyan.com/ajax/movieOnInfoList",
        "steam-new-releases" to "https://store.steampowered.com/api/featuredcategories?cc=cn&l=schinese",
        "steam-new-releases-2" to "https://store.steampowered.com/api/featuredcategories?cc=cn&l=schinese",
        "gamer520-pc-latest" to "https://www.gamer520.com/pcplay",
        "gamer520-switch-latest" to "https://www.gamer520.com/gameswitch",
        "ps5-games-latest" to "https://2468c.com/ps5game",
        "x-news" to "https://getdaytrends.com/united-states/",
        "xiaohongshu-hot" to "https://tophub.today/n/L4MdA5ldxD",
        "bilibili-hot" to "https://api.bilibili.com/x/web-interface/popular?ps=10&pn=1",
        "stocks-cn" to "600519,300750,600036,601318,002594",
        "crypto" to "btc,eth,sol,bnb,xrp",
    )

    fun isWebId(id: String): Boolean = id.startsWith("web-")
}
