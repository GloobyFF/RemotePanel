package com.glooby.remotepanel.ui

import android.os.Bundle
import android.util.TypedValue
import android.view.LayoutInflater
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.glooby.remotepanel.R
import com.glooby.remotepanel.data.PageCatalog
import com.glooby.remotepanel.data.Prefs
import com.glooby.remotepanel.data.Theme
import com.glooby.remotepanel.data.WebPageConfig

class SettingsActivity : AppCompatActivity() {
    private lateinit var container: LinearLayout
    private lateinit var dwellGlobal: EditText
    private lateinit var weatherCity: EditText
    private lateinit var newsRss: EditText
    private val pageRows = mutableListOf<PageRow>()
    private val webRows = mutableListOf<WebRow>()
    private lateinit var webHost: LinearLayout
    private var webDraft = Prefs.loadWebPages().toMutableList()

    data class PageRow(val id: String, val enabled: Switch, val dwell: EditText)
    data class WebRow(
        val id: String,
        val title: EditText,
        val url: EditText,
        val dwell: EditText,
        val enabled: Switch
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        container = findViewById(R.id.settingsContainer)
        findViewById<Button>(R.id.saveBtn).setOnClickListener { saveAndFinish() }
        buildForm()
    }

    private fun buildForm() {
        container.removeAllViews()
        pageRows.clear()
        webRows.clear()

        section(getString(R.string.dwell_global))
        dwellGlobal = edit(Prefs.dwellOverride().toString(), inputNumber = true)
        container.addView(dwellGlobal)

        section(getString(R.string.weather_city))
        weatherCity = edit(Prefs.sourceUrl("weather"))
        container.addView(weatherCity)

        section(getString(R.string.news_rss))
        newsRss = edit(Prefs.sourceUrl("daily-news"))
        container.addView(newsRss)

        section(getString(R.string.pages_section))
        val inflater = LayoutInflater.from(this)
        for (def in PageCatalog.builtins()) {
            val row = inflater.inflate(R.layout.item_settings_page_row, container, false)
            row.setBackgroundColor(Theme.card())
            row.findViewById<TextView>(R.id.name).text = def.title
            val enabled = row.findViewById<Switch>(R.id.enabled)
            enabled.isChecked = Prefs.pageEnabled(def.id)
            val dwell = row.findViewById<EditText>(R.id.dwell)
            dwell.setText(Prefs.pageDwell(def.id, def.defaultDwell).toString())
            val url = row.findViewById<EditText>(R.id.url)
            if (def.hasSource) {
                url.visibility = android.view.View.VISIBLE
                url.hint = def.sourceHint
                url.setText(Prefs.sourceUrl(def.id))
                url.tag = def.id
            }
            container.addView(row)
            pageRows += PageRow(def.id, enabled, dwell)
            if (def.hasSource) {
                // stash url field via tag on dwell for save — keep map
                dwell.tag = url
            }
        }

        val webHeader = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            val t = TextView(this@SettingsActivity).apply {
                text = getString(R.string.web_section)
                setTextColor(Theme.accent())
                textSize = 20f
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }
            val add = Button(this@SettingsActivity).apply {
                text = getString(R.string.add_web_page)
                setOnClickListener { addWeb() }
            }
            addView(t)
            addView(add)
        }
        container.addView(webHeader, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(18); bottomMargin = dp(8) })

        val hint = TextView(this).apply {
            text = "轮到该页时全屏打开网址，无顶栏。最多 ${WebPageConfig.MAX} 个。左右边缘点按翻页；顶部长按打开设置。"
            setTextColor(Theme.border())
            textSize = 13f
        }
        container.addView(hint)

        webHost = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        container.addView(webHost)
        rebuildWebRows()
    }

    private fun rebuildWebRows() {
        webHost.removeAllViews()
        webRows.clear()
        val inflater = LayoutInflater.from(this)
        if (webDraft.isEmpty()) {
            webHost.addView(TextView(this).apply {
                text = "还没有自定义网页"
                setTextColor(Theme.border())
                setPadding(0, dp(8), 0, dp(8))
            })
        }
        webDraft.forEachIndexed { i, page ->
            val row = inflater.inflate(R.layout.item_settings_web_row, webHost, false)
            row.setBackgroundColor(Theme.card())
            val title = row.findViewById<EditText>(R.id.title)
            val url = row.findViewById<EditText>(R.id.url)
            val dwell = row.findViewById<EditText>(R.id.dwell)
            val enabled = row.findViewById<Switch>(R.id.enabled)
            title.setText(page.title)
            url.setText(page.url)
            dwell.setText(page.dwell.toString())
            enabled.isChecked = page.enabled
            row.findViewById<Button>(R.id.delete).setOnClickListener {
                collectWebDraft()
                if (i < webDraft.size) {
                    webDraft.removeAt(i)
                    rebuildWebRows()
                }
            }
            webHost.addView(row)
            webRows += WebRow(page.id, title, url, dwell, enabled)
        }
    }

    private fun addWeb() {
        collectWebDraft()
        if (webDraft.size >= WebPageConfig.MAX) return
        webDraft += WebPageConfig(
            id = WebPageConfig.newId(),
            title = "网页 ${webDraft.size + 1}",
            url = "",
            dwell = 60,
            enabled = false
        )
        rebuildWebRows()
    }

    private fun collectWebDraft() {
        val next = mutableListOf<WebPageConfig>()
        webRows.forEachIndexed { i, r ->
            next += WebPageConfig(
                id = r.id,
                title = r.title.text?.toString().orEmpty(),
                url = r.url.text?.toString().orEmpty(),
                dwell = r.dwell.text?.toString()?.toIntOrNull() ?: 60,
                enabled = r.enabled.isChecked
            ).normalized(i)
        }
        webDraft = next
    }

    private fun saveAndFinish() {
        Prefs.setDwellOverride(dwellGlobal.text?.toString()?.toIntOrNull() ?: 0)
        Prefs.setSourceUrl("weather", weatherCity.text?.toString().orEmpty())
        Prefs.setSourceUrl("daily-news", newsRss.text?.toString().orEmpty())
        for (row in pageRows) {
            Prefs.setPageEnabled(row.id, row.enabled.isChecked)
            Prefs.setPageDwell(row.id, row.dwell.text?.toString()?.toIntOrNull() ?: 0)
            val urlField = row.dwell.tag as? EditText
            if (urlField != null) {
                Prefs.setSourceUrl(row.id, urlField.text?.toString().orEmpty())
            }
        }
        collectWebDraft()
        Prefs.saveWebPages(webDraft)
        finish()
    }

    private fun section(text: String) {
        val t = TextView(this)
        t.text = text
        t.setTextColor(Theme.accent())
        t.textSize = 16f
        t.setPadding(0, dp(16), 0, dp(8))
        container.addView(t)
    }

    private fun edit(value: String, inputNumber: Boolean = false): EditText {
        return EditText(this).apply {
            setText(value)
            setTextColor(0xFFFFFFFF.toInt())
            setHintTextColor(Theme.border())
            setBackgroundColor(0x22000000)
            setPadding(dp(10), dp(10), dp(10), dp(10))
            if (inputNumber) inputType = android.text.InputType.TYPE_CLASS_NUMBER
        }
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()
}
