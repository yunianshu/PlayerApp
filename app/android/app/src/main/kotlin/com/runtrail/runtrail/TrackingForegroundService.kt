package com.runtrail.runtrail

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 跑步进行中的前台服务：持有 location 类型前台通知，
 * 让系统在锁屏/退后台时继续向"使用期间"定位权限的应用推送位置。
 * Flutter 侧通过 runtrail/background 通道启停；服务本身不做定位。
 *
 * 通知内容随实时成绩刷新（Keep 同款锁屏体验）：息屏/锁屏抬手即可看到
 * 距离、配速与用时，由 Flutter 侧每秒推送 ACTION_UPDATE。
 */
class TrackingForegroundService : Service() {

    private var started = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UPDATE -> {
                // 只刷新已启动服务的通知；未启动时收到更新不拉起前台。
                if (started) {
                    updateNotification(intent.getStringExtra(EXTRA_TEXT))
                } else {
                    stopSelf(startId)
                }
            }
            else -> startAsForeground()
        }
        // 进程被杀后 Flutter 侧跑步状态已丢失，不做无意义的自动重启。
        return START_NOT_STICKY
    }

    private fun startAsForeground() {
        val notification = buildNotification(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
        started = true
    }

    private fun updateNotification(text: String?) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun buildNotification(liveText: String?): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "跑步记录",
                    // DEFAULT + 无声：IMPORTANCE_LOW 的每秒更新通知会被系统
                    // 频控降级（demoted/muted），锁屏看不到实时成绩。
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "跑步进行中保持定位更新"
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("跑步记录中")
            .setContentText(liveText ?: "跑迹正在记录你的跑步轨迹")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            // IMPORTANCE_LOW 已静音；再显式声明不震动不提醒，刷新时不打扰。
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "runtrail_tracking"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_UPDATE = "com.runtrail.runtrail.UPDATE_NOTIFICATION"
        private const val EXTRA_TEXT = "liveText"

        /** 刷新前台通知的实时成绩文案（服务未启动时为无操作）。 */
        fun update(context: Context, liveText: String) {
            val intent = Intent(context, TrackingForegroundService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra(EXTRA_TEXT, liveText)
            // 应用在前台时 startService 合法；跑步中刷新必然处于前台/前台服务态。
            context.startService(intent)
        }
    }
}
