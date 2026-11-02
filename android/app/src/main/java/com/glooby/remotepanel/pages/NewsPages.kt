package com.glooby.remotepanel.pages

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.ui.Fmt
import com.glooby.remotepanel.ui.Img
import com.glooby.remotepanel.ui.Roll
import com.glooby.remotepanel.ui.Ui
import com.glooby.remotepanel.ui.Ui.W

/** 每日新闻, GitHub, X 话题, 小红书, 哔哩哔哩. */
object NewsPages {
    const val BILI_W = 336
    const val BILI_H = 189

    fun news(ctx: Context, s: PanelState): View {
        val items = s.dailyNews.ifEmpty { return Blocks.pending(ctx, "daily", "新闻") }
        return Ui.column(ctx).apply {
            val lead = items.first()
            val hero = Ui.column(ctx, Theme.surface()).apply {
                setPadding(Ui.px(36), Ui.px(26), Ui.px(36), Ui.px(26))
                addView(Ui.row(ctx).apply {
                    addView(Ui.pill(ctx, "头条", Theme.bad(), Color.WHITE), Ui.wrap(end = 18))
                    if (lead.publishedAt > 0) addView(Ui.text(ctx, Fmt.ago(lead.publishedAt), Ui.META, Theme.textDim()), Ui.wrap())
                }, Ui.wide(bottom = 14))
                addView(Ui.text(ctx, lead.title, Ui.H1, Theme.text(), W.BOLD, lines = 1), Ui.wide())
            }
            addView(hero, Ui.wide(bottom = Ui.GAP))
            val list = Ui.column(ctx)
            val rest = items.drop(1).take(4)
            rest.forEachIndexed { i, n ->
                val row = Ui.row(ctx, Theme.surface()).apply {
                    setPadding(Ui.px(26), Ui.px(10), Ui.px(26), Ui.px(10))
                    addView(Blocks.rank(ctx, i + 2, 60))
                    addView(Ui.text(ctx, n.title, Ui.BODY, Theme.text(), W.MEDIUM, lines = 1), LinearLayout.LayoutParams(0, -2, 1f))
                    if (n.publishedAt > 0) addView(Ui.text(ctx, Fmt.clock(n.publishedAt), Ui.META, Theme.textFaint()), Ui.wrap(start = 16))
                }
                list.addView(row, Ui.flexV(bottom = if (i < rest.size - 1) 14 else 0))
            }
            addView(list, Ui.flexV())
        }
    }

    fun github(ctx: Context, s: PanelState): View {
        val repos = s.github.ifEmpty { return Blocks.pending(ctx, "github", "热门项目") }.take(4)
        return Ui.column(ctx).apply {
            addView(Blocks.section(ctx, "近 30 天新建 · AI 项目", "按 Star 排序"), Ui.wide(64, bottom = 16))
            repos.forEachIndexed { i, r ->
                val card = Ui.row(ctx, Theme.surface()).apply {
                    setPadding(Ui.px(26), Ui.px(10), Ui.px(30), Ui.px(10))
                    gravity = Gravity.CENTER_VERTICAL
                    addView(Blocks.rank(ctx, i + 1, 60))
                    addView(Ui.column(ctx).apply {
                        val name = r.name.substringAfter('/')
                        addView(Ui.row(ctx).apply {
                            addView(Ui.text(ctx, name, Ui.H2, Theme.text(), W.BOLD), LinearLayout.LayoutParams(0, -2, 1f))
                            if (r.stars > 0) {
                                val stars = Ui.number(ctx, "★ ${Fmt.big(r.stars.toDouble())}", Ui.BODY, Theme.warn())
                                Roll.bind(stars, "star-${r.name}", stars.text.toString())
                                addView(stars, Ui.wrap(start = 16))
                            }
                        }, Ui.wide())
                        if (r.description.isNotBlank()) addView(Ui.text(ctx, r.description, Ui.BODY, Theme.textDim(), lines = 1), Ui.wide(top = 6))
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                }
                addView(card, Ui.flexV(bottom = if (i < repos.size - 1) 14 else 0))
            }
        }
    }
    fun trends(ctx: Context, s: PanelState): View {
        val t = s.trends ?: return Blocks.pending(ctx, "x", "X 热门话题")
        val items = t.now.take(8)
        return Ui.column(ctx).apply {
            addView(Blocks.section(ctx, "美国 · 此刻热门", "前 ${items.size} 名"), Ui.wide(64, bottom = 16))
            items.forEachIndexed { i, it ->
                val row = Ui.row(ctx, Theme.surface(), radius = 20).apply {
                    setPadding(Ui.px(22), 0, Ui.px(28), 0)
                    addView(Blocks.rank(ctx, it.rank, 72).apply { layoutParams = Ui.fixed(72, 72, end = 22) })
                    addView(Ui.text(ctx, it.name, Ui.H2, Theme.text(), W.BOLD, lines = 1), LinearLayout.LayoutParams(0, -2, 1f))
                }
                addView(row, Ui.flexV(bottom = if (i < items.size - 1) 14 else 0))
            }
        }
    }

    // ---------- 小红书：头条大图 + 6 宫格 + 文字榜 ----------

    fun xiaohongshu(ctx: Context, s: PanelState): View {
        val items = s.xhs.ifEmpty { return Blocks.pending(ctx, "xhs", "小红书热榜") }
        return Ui.column(ctx).apply {
            val lead = items.first()
            addView(
                Blocks.overlayTile(ctx, lead.imageUrl, lead.title, "🔥 ${lead.heat}", "小红书", 4, 1008, 420, Ui.H1, 2, rankNo = 1),
                Ui.wide(420, bottom = Ui.GAP),
            )
            addView(Pages.grid(ctx, 3, 2, Ui.GAP) { i ->
                items.getOrNull(i + 1)?.let { p ->
                    Blocks.overlayTile(ctx, p.imageUrl, p.title, "🔥 ${p.heat}", "小红书", i + 5, 494, 300, rankNo = i + 2)
                }
            }, Ui.flexV())
        }
    }
    // ---------- 哔哩哔哩：缩略图 + 标题 + UP 主 + 数据 ----------

    fun bilibili(ctx: Context, s: PanelState): View {
        val items = s.bili.ifEmpty { return Blocks.pending(ctx, "bili", "B 站热门") }.take(4)
        return Ui.column(ctx).apply {
            items.forEachIndexed { i, v ->
                val row = Ui.row(ctx, Theme.surface()).apply {
                    setPadding(Ui.px(4), Ui.px(4), Ui.px(26), Ui.px(4))
                    val thumb = FrameLayout(ctx).apply {
                        Ui.clip(this, 18)
                        val img = Img.view(ctx, 0)
                        addView(img, Ui.fill())
                        Img.load(img, v.imageUrl, v.title, "bilibili", i + 1, BILI_W, BILI_H)
                        if (v.duration.isNotBlank()) {
                            addView(Ui.number(ctx, v.duration, Ui.META, Color.WHITE).apply {
                                background = Ui.rounded(0xB3000000.toInt(), 10)
                                setPadding(Ui.px(10), Ui.px(2), Ui.px(10), Ui.px(2))
                            }, FrameLayout.LayoutParams(-2, -2, Gravity.END or Gravity.BOTTOM).apply {
                                rightMargin = Ui.px(10); bottomMargin = Ui.px(10)
                            })
                        }
                    }
                    addView(thumb, Ui.fixed(BILI_W, BILI_H, end = 24))
                    addView(Ui.column(ctx).apply {
                        addView(Ui.text(ctx, v.title, Ui.H2, Theme.text(), W.BOLD, lines = 2), Ui.wide())
                        val meta = listOfNotNull(
                            v.author.ifBlank { null }?.let { "UP $it" },
                            v.heat.ifBlank { null }?.let { "▶ $it" },
                        ) + v.stats
                        if (meta.isNotEmpty()) addView(Ui.text(ctx, meta.joinToString("   "), Ui.BODY, Theme.textDim(), lines = 1), Ui.wide(top = 8))
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                }
                addView(row, Ui.flexV(bottom = if (i < items.size - 1) 14 else 0))
            }
        }
    }
}
