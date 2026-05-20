package com.example.cripticam

import android.view.WindowManager
// ✨ BURAYI DEĞİŞTİR: FlutterActivity yerine FlutterFragmentActivity olmalı
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterFragmentActivity() { // 👈 Burası güncellendi
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 🛡️ Native ekran koruman burada durmaya devam etsin
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}