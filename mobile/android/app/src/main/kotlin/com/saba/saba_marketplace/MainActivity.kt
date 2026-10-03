package com.saba.saba_marketplace

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Saba's pushes arrive on this channel (the server names it
        // saba_default), and Android shows nothing on a channel that does
        // not exist. Making it again is harmless: it keeps the person's
        // settings.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    "saba_default",
                    getString(R.string.push_channel),
                    NotificationManager.IMPORTANCE_HIGH,
                ),
            )
        }
    }
}
