package com.glooby.remotepanel.ui

import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.ImageView
import android.widget.LinearLayout

/** Page entrance: cards come in from the right, then covers drift a little. */
object Motion {
    private val ease = DecelerateInterpolator()

    fun enter(host: ViewGroup, done: () -> Unit = {}) {
        val body = content(host)
        val blocks = ArrayList<View>()
        if (body is ViewGroup) {
            for (i in 0 until body.childCount) collect(body.getChildAt(i), blocks)
        }
        if (blocks.isEmpty()) {
            done()
            return
        }
        val each = 280L
        val gap = if (blocks.size <= 1) 0L else minOf(60L, (700L - each) / (blocks.size - 1))
        blocks.forEachIndexed { i, v ->
            v.animate().cancel()
            v.translationX = Ui.pxf(160f)
            v.alpha = 0f
            v.animate().translationX(0f).alpha(1f).setStartDelay(i * gap).setDuration(each).setInterpolator(ease).start()
        }
        val total = (blocks.size - 1) * gap + each
        host.postDelayed({ drift(host) }, total)
        host.postDelayed(done, total)
    }

    fun cancel(host: View) {
        fun walk(v: View) {
            v.animate().cancel()
            v.translationX = 0f
            v.alpha = 1f
            v.scaleX = 1f
            v.scaleY = 1f
            if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        walk(host)
    }

    private fun content(host: ViewGroup): View? {
        val page = host.getChildAt(0) as? ViewGroup ?: return null
        val frame = page.getChildAt(0) as? ViewGroup ?: return page
        return frame.getChildAt(0) ?: frame
    }

    /** A stack of cards (no loose text) splits so each card can fly on its own. */
    private fun collect(v: View, into: MutableList<View>) {
        if (!expandable(v)) {
            into += v
            return
        }
        val group = v as ViewGroup
        for (i in 0 until group.childCount) collect(group.getChildAt(i), into)
    }

    private fun expandable(v: View): Boolean {
        if (v !is LinearLayout || v.childCount < 2 || v.background != null) return false
        for (i in 0 until v.childCount) if (v.getChildAt(i) !is ViewGroup) return false
        return true
    }

    private fun drift(root: View) {
        val images = ArrayList<ImageView>()
        fun walk(v: View) {
            if (v is ImageView && v.drawable != null && v.width > Ui.px(120)) images += v
            if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        walk(root)
        images.take(8).forEach { img ->
            if (img.scaleX != 1f) return@forEach
            img.pivotX = img.width / 2f
            img.pivotY = img.height / 2f
            img.animate().scaleX(1.06f).scaleY(1.06f).setDuration(18_000).setInterpolator(ease).start()
        }
    }
}
