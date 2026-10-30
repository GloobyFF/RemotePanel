package com.glooby.remotepanel.pages

import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.bumptech.glide.Glide
import com.glooby.remotepanel.R
import com.glooby.remotepanel.data.PanelState
import com.glooby.remotepanel.data.Theme

class NewsPage(context: android.content.Context) : PanelPage {
    override val root = LayoutInflater.from(context).inflate(R.layout.page_simple_scroll, null)
    private val content: LinearLayout = root.findViewById(R.id.content)

    override fun bind(state: PanelState) {
        content.removeAllViews()
        root.setBackgroundColor(Theme.bg())
        val items = state.dailyNews
        if (items.isEmpty()) {
            val empty = TextView(root.context)
            empty.text = "这一页还没有新闻。检查设置里的 RSS 地址。"
            empty.setTextColor(Theme.border())
            empty.textSize = 20f
            content.addView(empty)
            return
        }
        val inflater = LayoutInflater.from(root.context)
        items.take(8).forEachIndexed { i, item ->
            val card = inflater.inflate(R.layout.item_news_card, content, false)
            card.setBackgroundColor(Theme.card())
            card.findViewById<TextView>(R.id.index).text = "%02d".format(i + 1)
            card.findViewById<TextView>(R.id.title).text = item.title
            card.findViewById<TextView>(R.id.summary).text = item.summary
            val thumb = card.findViewById<ImageView>(R.id.thumb)
            if (item.imageUrl.isNotBlank()) {
                thumb.visibility = View.VISIBLE
                Glide.with(thumb).load(item.imageUrl).centerCrop().into(thumb)
            } else {
                thumb.visibility = View.GONE
            }
            content.addView(card)
        }
    }
}
