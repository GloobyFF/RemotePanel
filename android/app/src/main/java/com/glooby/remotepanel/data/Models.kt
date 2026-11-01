package com.glooby.remotepanel.data

data class NewsItem(
    val title: String,
    val summary: String,
    val link: String,
    val imageUrl: String,
    val publishedAt: Long = 0L,
)

data class HourSlot(val hour: String, val code: Int, val temp: Double, val rainChance: Int)

data class DaySlot(
    val date: String,
    val code: Int,
    val low: Double,
    val high: Double,
    val rainChance: Int,
    val sunrise: String = "",
    val sunset: String = "",
    val uv: Double = 0.0,
)

data class WeatherState(
    val city: String,
    val temp: Double,
    val feelsLike: Double,
    val code: Int,
    val humidity: Int,
    val windKmh: Double,
    val windDir: Int,
    val pressure: Double,
    val hourly: List<HourSlot>,
    val daily: List<DaySlot>,
)

data class QuoteItem(
    val name: String,
    val symbol: String,
    val price: Double,
    val percent: Double,
    val change: Double,
    val high: Double,
    val low: Double,
    val open: Double,
    val prev: Double,
    val turnover: Double,
    val unit: String,
    val market: String,
)

data class StockBoard(val indices: List<QuoteItem>, val stocks: List<QuoteItem>)

data class RepoCard(
    val name: String,
    val description: String,
    val stars: Int,
    val forks: Int,
    val language: String,
    val topics: List<String>,
)

data class TrendItem(val rank: Int, val name: String, val score: String = "")

data class TrendState(val now: List<TrendItem>, val mostTweeted: List<TrendItem>)

/** A ranked feed entry with an optional image (小红书, 哔哩哔哩). */
data class PostCard(
    val title: String,
    val imageUrl: String,
    val heat: String = "",
    val author: String = "",
    val stats: List<String> = emptyList(),
    val badge: String = "",
    val duration: String = "",
)

/** Poster or capsule tile (movies, Steam, game listings). */
data class CoverCard(
    val title: String,
    val imageUrl: String,
    val subtitle: String = "",
    val meta: String = "",
    val badge: String = "",
    val price: String = "",
    val oldPrice: String = "",
    val score: String = "",
    /** Publish time (epoch ms), formatted when the page is drawn so “N 小时前” stays right. */
    val time: Long = 0L,
)

data class SteamBoard(val newReleases: List<CoverCard>, val topSellers: List<CoverCard>, val specials: List<CoverCard>)

data class VpsState(val used: String, val remain: String, val status: String, val cycle: String, val percent: Double)

data class TempChip(val label: String, val value: String)

data class FilamentSlot(val name: String, val percent: Int, val color: Int, val kind: String)

data class PrintState(
    val online: Boolean,
    val title: String,
    val status: String,
    val progress: Double,
    val fileName: String,
    val remainMinutes: Int,
    val layer: String,
    val temps: List<TempChip>,
    val slots: List<FilamentSlot>,
)

data class PanelState(
    val hello: String = "",
    val helloPeriod: String = "",
    val weather: WeatherState? = null,
    val vps: VpsState? = null,
    val dailyNews: List<NewsItem> = emptyList(),
    val github: List<RepoCard> = emptyList(),
    val trends: TrendState? = null,
    val xhs: List<PostCard> = emptyList(),
    val bili: List<PostCard> = emptyList(),
    val stocks: StockBoard? = null,
    val crypto: List<QuoteItem> = emptyList(),
    val movies: List<CoverCard> = emptyList(),
    val steam: SteamBoard? = null,
    val pcGames: List<CoverCard> = emptyList(),
    val switchGames: List<CoverCard> = emptyList(),
    val ps5Games: List<CoverCard> = emptyList(),
    val printer: PrintState? = null,
    /** Feed key → epoch ms of the data being shown. */
    val fetchedAt: Map<String, Long> = emptyMap(),
    val errors: List<String> = emptyList(),
)
