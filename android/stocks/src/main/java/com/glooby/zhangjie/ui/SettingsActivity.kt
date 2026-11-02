package com.glooby.zhangjie.ui

import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.glooby.zhangjie.Holding
import com.glooby.zhangjie.Quotes
import com.glooby.zhangjie.SetupServer
import com.glooby.zhangjie.Store

/** On-device editor. The same fields are on the browser page at port 8091. */
class SettingsActivity : AppCompatActivity() {
    private val rows = ArrayList<Row>()
    private lateinit var list: LinearLayout
    private lateinit var sumField: EditText
    private lateinit var stockField: EditText
    private lateinit var sound: Switch
    private lateinit var addField: EditText
    private var dirty = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Ui.init(this)
        setContentView(build())
        load()
    }

    @Deprecated("Kiosk back saves the form")
    override fun onBackPressed() {
        save()
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    private fun build(): View {
        val scroll = ScrollView(this).apply { setBackgroundColor(Ui.BG) }
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(Ui.px(36), Ui.px(28), Ui.px(36), Ui.px(48))
        }
        col.addView(Ui.label(this, "设置", 56, Ui.TEXT, bold = true).apply { gravity = Gravity.START }, Ui.wide(80))
        col.addView(Ui.label(this, "电脑或手机浏览器打开下面的地址，可以改股票、买入价、股数和提醒。", 30, Ui.DIM).apply {
            gravity = Gravity.START
        })
        val url = TextView(this).apply {
            text = SetupServer.lanUrl() + if (SetupServer.error.isEmpty()) "" else "\n${SetupServer.error}"
            setTextColor(Ui.TEXT)
            textSize = 18f
            setTextIsSelectable(true)
            setPadding(0, Ui.px(12), 0, Ui.px(24))
        }
        col.addView(url)

        sumField = field(Store.dwellSummary().toString(), InputType.TYPE_CLASS_NUMBER)
        stockField = field(Store.dwellStock().toString(), InputType.TYPE_CLASS_NUMBER)
        val dwell = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        dwell.addView(labeled("汇总停留（秒）", sumField), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = Ui.px(16) })
        dwell.addView(labeled("单只停留（秒）", stockField), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        col.addView(dwell)
        sound = Switch(this).apply {
            text = "价格提醒响铃"
            setTextColor(Ui.TEXT)
            isChecked = Store.alertSoundOn()
            setOnCheckedChangeListener { _, _ -> dirty = true }
        }
        col.addView(sound, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, Ui.px(88)).apply { topMargin = Ui.px(12) })

        col.addView(Ui.label(this, "买入价、股数，和价格提醒。提醒留空就是不提醒。", 28, Ui.DIM).apply { gravity = Gravity.START }, Ui.wide(bottom = 12))
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        col.addView(list)

        addField = field("", InputType.TYPE_CLASS_NUMBER)
        val addRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        addRow.addView(addField, LinearLayout.LayoutParams(0, Ui.px(80), 1f).apply { marginEnd = Ui.px(12) })
        addRow.addView(button("添加") { addStock() })
        col.addView(addRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = Ui.px(8) })
        col.addView(button("保存") {
            save()
            finish()
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, Ui.px(88)).apply { topMargin = Ui.px(24) })
        scroll.addView(col)
        return scroll
    }

    private fun load() {
        list.removeAllViews()
        rows.clear()
        Store.holdings().forEach { addRow(it) }
        sumField.setText(Store.dwellSummary().toString())
        stockField.setText(Store.dwellStock().toString())
        sound.isChecked = Store.alertSoundOn()
        dirty = false
    }

    private fun addRow(h: Holding) {
        val code = field(h.code, InputType.TYPE_CLASS_NUMBER)
        val name = field(h.name, InputType.TYPE_CLASS_TEXT)
        val buy = field(num(h.buy), InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL)
        val shares = field(num(h.shares), InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL)
        val above = field(num(h.above), InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL)
        val below = field(num(h.below), InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL)
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(Ui.CARD)
                cornerRadius = Ui.px(16).toFloat()
            }
            setPadding(Ui.px(16), Ui.px(12), Ui.px(16), Ui.px(12))
        }
        val head = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        head.addView(code, LinearLayout.LayoutParams(0, Ui.px(72), 0.4f).apply { marginEnd = Ui.px(8) })
        head.addView(name, LinearLayout.LayoutParams(0, Ui.px(72), 0.6f).apply { marginEnd = Ui.px(8) })
        val row = Row(code, name, buy, shares, above, below, box)
        head.addView(button("删除") {
            rows.remove(row)
            list.removeView(box)
            dirty = true
        })
        box.addView(head)
        val line = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        line.addView(labeled("买入价", buy), piece())
        line.addView(labeled("股数", shares), piece())
        line.addView(labeled("涨到", above), piece())
        line.addView(labeled("跌到", below), piece())
        box.addView(line, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = Ui.px(8) })
        list.addView(box, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = Ui.px(12) })
        rows += row
    }

    private fun addStock() {
        val code = Quotes.codeForToken(addField.text.toString())
        if (code == null) return
        if (rows.any { Quotes.codeForToken(it.code.text.toString()) == code }) return
        addRow(Holding(code, code, 0.0, 0.0, 0.0, 0.0))
        addField.setText("")
        dirty = true
    }

    private fun save() {
        val next = ArrayList<Holding>()
        val seen = HashSet<String>()
        for (row in rows) {
            val code = Quotes.codeForToken(row.code.text.toString()) ?: continue
            if (!seen.add(code)) continue
            val name = row.name.text.toString().trim().ifEmpty { code }
            next += Holding(code, name, number(row.buy), number(row.shares), number(row.above), number(row.below))
        }
        Store.saveHoldings(next)
        Store.setDwells(sumField.text.toString().toIntOrNull() ?: 20, stockField.text.toString().toIntOrNull() ?: 12)
        Store.setAlertSound(sound.isChecked)
        dirty = false
    }

    private fun number(field: EditText): Double {
        val t = field.text.toString().replace(",", "").trim()
        return t.toDoubleOrNull()?.coerceAtLeast(0.0) ?: 0.0
    }

    private fun num(v: Double): String = if (v > 0) v.toString().trimEnd('0').trimEnd('.') else ""

    private fun field(value: String, input: Int): EditText = EditText(this).apply {
        setText(value)
        setTextColor(Ui.TEXT)
        setHintTextColor(Ui.DIM)
        inputType = input
        background = GradientDrawable().apply {
            setColor(0xFF0E1A2E.toInt())
            cornerRadius = Ui.px(10).toFloat()
        }
        setPadding(Ui.px(12), Ui.px(8), Ui.px(12), Ui.px(8))
        setOnFocusChangeListener { _, _ -> dirty = true }
    }

    private fun labeled(caption: String, input: View): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        addView(Ui.label(this@SettingsActivity, caption, 22, Ui.DIM).apply { gravity = Gravity.START })
        addView(input, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, Ui.px(72)))
    }

    private fun piece(): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = Ui.px(8) }

    private fun button(text: String, click: () -> Unit): Button = Button(this).apply {
        this.text = text
        setTextColor(Ui.TEXT)
        background = GradientDrawable().apply {
            setColor(Ui.UP)
            cornerRadius = Ui.px(12).toFloat()
        }
        setOnClickListener { click() }
    }

    private class Row(
        val code: EditText,
        val name: EditText,
        val buy: EditText,
        val shares: EditText,
        val above: EditText,
        val below: EditText,
        val view: View,
    )
}
