package com.runtrail.runtrail

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** A discoverable default launcher; the permanent Flutter host is never toggled. */
class LauncherDefault : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep launch extras/data (e.g. Flutter tooling) and reuse an existing host.
        startActivity(Intent(intent).setClass(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
