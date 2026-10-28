// Android stand-ins for the firmware's hardware: NVS (Preferences), the
// ES8311 speaker and the AXP2101 battery gauge.
package com.pokewatch

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.BatteryManager
import com.pokewatch.game.Sfx
import com.pokewatch.game.Store
import java.util.concurrent.LinkedBlockingQueue

class PrefsStore(context: Context) : Store {
    private val sp: SharedPreferences = context.getSharedPreferences("tamapoke", Context.MODE_PRIVATE)
    private var ed: SharedPreferences.Editor? = null
    private fun e() = ed ?: sp.edit().also { ed = it }

    override fun getInt(key: String, def: Int) = sp.getInt(key, def)
    override fun putInt(key: String, v: Int) { e().putInt(key, v) }
    override fun getLong(key: String, def: Long) = sp.getLong(key, def)
    override fun putLong(key: String, v: Long) { e().putLong(key, v) }
    override fun getBool(key: String, def: Boolean) = sp.getBoolean(key, def)
    override fun putBool(key: String, v: Boolean) { e().putBoolean(key, v); flush() }
    override fun getString(key: String, def: String) = sp.getString(key, def) ?: def
    override fun putString(key: String, v: String) { e().putString(key, v) }
    override fun has(key: String) = sp.contains(key)
    override fun clear() { sp.edit().clear().commit(); ed = null }
    override fun flush() { ed?.apply(); ed = null }
}

/** Square-wave sound effects, same notes as the firmware's audio.cpp. */
class Sound(private val prefs: SharedPreferences) {
    private class Note(val f: Int, val ms: Int)

    private val table: Map<Sfx, List<Note>> = mapOf(
        Sfx.TAP to listOf(Note(880, 35)),
        Sfx.EAT to listOf(Note(660, 45), Note(0, 12), Note(660, 45)),
        Sfx.PLAY to listOf(Note(784, 45), Note(988, 60)),
        Sfx.HEART to listOf(Note(1047, 55), Note(1319, 90)),
        Sfx.HATCH to listOf(Note(523, 80), Note(659, 80), Note(784, 110), Note(1047, 170)),
        Sfx.EVOLVE to listOf(Note(523, 80), Note(659, 80), Note(784, 80), Note(1047, 90), Note(1319, 230)),
        Sfx.MEDAL to listOf(Note(784, 70), Note(0, 25), Note(784, 70), Note(0, 25), Note(1047, 200)),
        Sfx.DENY to listOf(Note(300, 110), Note(200, 170)),
        Sfx.BYE to listOf(Note(784, 150), Note(659, 150), Note(523, 280)),
        Sfx.LEVEL to listOf(Note(784, 70), Note(1047, 130)),
    )

    private val rate = 22050
    private val queue = LinkedBlockingQueue<Sfx>(8)
    private val pcm = HashMap<Sfx, ShortArray>()

    var enabled: Boolean = prefs.getBoolean("snd", true)
        set(v) { field = v; prefs.edit().putBoolean("snd", v).apply() }

    private fun render(notes: List<Note>): ShortArray {
        val total = notes.sumOf { it.ms } * rate / 1000
        val out = ShortArray(total)
        var i = 0
        for (n in notes) {
            val len = n.ms * rate / 1000
            val half = if (n.f > 0) rate / (2 * n.f) else 0
            for (k in 0 until len) {
                out[i++] = if (n.f == 0) 0 else if ((k / half) % 2 == 0) 5000 else -5000
            }
        }
        return out
    }

    init {
        Thread({
            while (true) {
                val id = queue.take()
                val data = pcm.getOrPut(id) { render(table.getValue(id)) }
                val track = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).build())
                    .setAudioFormat(
                        AudioFormat.Builder().setSampleRate(rate)
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()
                    )
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(data.size * 2)
                    .build()
                try {
                    track.write(data, 0, data.size)
                    track.play()
                    Thread.sleep(data.size * 1000L / rate + 20)
                } catch (_: Exception) {
                } finally {
                    track.release()
                }
            }
        }, "sfx").apply { isDaemon = true }.start()
    }

    fun play(id: Sfx) {
        if (enabled) queue.offer(id)
    }
}

class Battery(private val context: Context) {
    private var cachedAt = 0L
    var percent = -1
        private set
    var charging = false
        private set

    fun poll(now: Long) {
        if (now - cachedAt < 10_000 && percent >= 0) return
        cachedAt = now
        val i: Intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        percent = if (level >= 0 && scale > 0) level * 100 / scale else -1
        val st = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        charging = st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL
    }
}
