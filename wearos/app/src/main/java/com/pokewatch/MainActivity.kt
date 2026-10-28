package com.pokewatch

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager

class MainActivity : Activity() {
    private lateinit var view: GameView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("tamapoke", Context.MODE_PRIVATE)
        view = GameView(this, Sound(prefs), Battery(this))
        setContentView(view)
        // the minigames need the screen awake; the system still times out otherwise
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onResume() {
        super.onResume()
        view.onResumeGame()
    }

    override fun onPause() {
        view.onPauseGame()
        super.onPause()
    }

    @Deprecated("Wear OS still delivers the back button here")
    override fun onBackPressed() {
        if (!view.onBack()) {
            @Suppress("DEPRECATION")
            super.onBackPressed()
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && view.onBack()) return true
        return super.onKeyDown(keyCode, event)
    }
}
