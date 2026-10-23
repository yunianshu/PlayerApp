package com.runtrail.runtrail

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/** Inexact, OS-managed reminders. No location service or exact-alarm privilege. */
object TrainingAlarms {
    private const val PREFS = "training_alarms"
    private const val KEY = "entries"
    private const val CHANNEL = "training_daily_v1"
    fun replace(context: Context, entries: List<Map<String, Any?>>) {
        cancel(context)
        val array = JSONArray()
        entries.forEachIndexed { index, entry ->
            val time = (entry["at"] as? Number)?.toLong() ?: return@forEachIndexed
            if (time <= System.currentTimeMillis()) return@forEachIndexed
            val json = JSONObject()
                .put("id", index + 10000)
                .put("at", time)
                .put("title", entry["title"] as? String ?: "今日训练")
                .put("body", entry["body"] as? String ?: "打开跑迹查看任务")
            array.put(json)
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY, array.toString()).apply()
        scheduleSaved(context)
    }
    fun cancel(context: Context) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        saved(context).forEach {
            alarm.cancel(intent(context, it.getInt("id")))
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY).apply()
    }
    private fun saved(context: Context): List<JSONObject> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, "[]") ?: "[]"
        return try {
            val a = JSONArray(raw)
            (0 until a.length()).map { a.getJSONObject(it) }
        } catch (_: Exception) { emptyList() }
    }
    private fun intent(context: Context, id: Int): PendingIntent {
        val i = Intent(context, TrainingAlarmReceiver::class.java).putExtra("id", id)
        return PendingIntent.getBroadcast(context, id, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    fun scheduleSaved(context: Context) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        saved(context).forEach { item ->
            val whenMs = item.getLong("at")
            if (whenMs > System.currentTimeMillis()) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMs,
                    intent(context, item.getInt("id")))
            }
        }
    }
    fun show(context: Context, id: Int) {
        val item = saved(context).firstOrNull { it.optInt("id") == id } ?: return
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL,
                "马拉松训练提醒", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = PendingIntent.getActivity(context, 0,
            // Target the permanent activity, not an alias that can be disabled later.
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(id, NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(item.optString("title"))
            .setContentText(item.optString("body"))
            .setStyle(NotificationCompat.BigTextStyle().bigText(item.optString("body")))
            .setContentIntent(open).setAutoCancel(true).build())
    }
}
class TrainingAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        TrainingAlarms.show(context, intent.getIntExtra("id", -1))
    }
}
class TrainingBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            TrainingAlarms.scheduleSaved(context)
        }
    }
}
