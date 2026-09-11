package com.deepseek.harness.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that keeps the app process (and therefore its mux
 * WebSocket) alive while the app is not visible.
 *
 * Android freezes a cached process shortly after it leaves the foreground —
 * screen lock included — which stops the Dart isolate and lets the mux
 * generation die silently. A process hosting a foreground service is never
 * cached, and the partial wake lock keeps the CPU running with the screen
 * off, so the connection survives long enough for an in-flight turn to
 * finish and post its notification.
 *
 * The service is driven entirely from Dart ([dsh/keep_alive] in
 * [MainActivity]): work in flight starts it, the last session settling stops
 * it, so the ongoing notification exists only while there is something to
 * keep alive. START_NOT_STICKY is deliberate — a restarted service would
 * have no Dart client to stop it again.
 */
class DshKeepAliveService : Service() {
    companion object {
        const val CHANNEL_ID = "keep-alive"
        const val NOTIFICATION_ID = 0x44534801

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_CHANNEL_NAME = "channelName"
        private const val EXTRA_CHANNEL_DESCRIPTION = "channelDescription"
        private const val WAKE_LOCK_TAG = "dsh:keep-alive"

        /**
         * Requests the service. Throws when Android refuses a background
         * foreground-service start (Android 12+); the caller reports that
         * refusal to Dart instead of crashing.
         */
        fun start(
            context: Context,
            title: String,
            text: String,
            channelName: String,
            channelDescription: String,
        ) {
            val intent = Intent(context, DshKeepAliveService::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
                putExtra(EXTRA_CHANNEL_NAME, channelName)
                putExtra(EXTRA_CHANNEL_DESCRIPTION, channelDescription)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DshKeepAliveService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "DSH"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        val channelName = intent?.getStringExtra(EXTRA_CHANNEL_NAME) ?: title
        val channelDescription = intent?.getStringExtra(EXTRA_CHANNEL_DESCRIPTION) ?: text
        createChannel(channelName, channelDescription)
        startInForeground(buildNotification(title, text))
        acquireWakeLock()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    /**
     * Android 15 caps `dataSync` foreground services at six hours per day and
     * calls this when the budget runs out; the process must stop promptly or
     * the system raises an ANR. Every API this app starts the service on
     * passes `specialUse` instead, so the cap does not apply here, but the
     * override stays as the documented safety net.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    private fun startInForeground(notification: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // specialUse does not exist before API 34; the manifest declares
            // both types so the pre-34 platforms get a type they know.
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel(name: String, description: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW).apply {
            this.description = description
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, text: String) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_dsh)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(launchIntent())
            .build()

    /** Tapping the row opens the app; a host without a launch intent gets a
     *  notification that is still informative but not tappable. */
    private fun launchIntent(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        wakeLock = null
        if (lock.isHeld) lock.release()
    }
}
