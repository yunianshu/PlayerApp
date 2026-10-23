package com.runtrail.runtrail

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Only launcher entries are toggled. MainActivity stays enabled for notifications and old explicit intents. */
internal class LauncherIconManager(private val context: Context) {
    private val pm = context.packageManager
    private val aliases = linkedMapOf(
        "default" to component("LauncherDefault"),
        "light" to component("LauncherLight"),
        "dark" to component("LauncherDark"),
        "editorial" to component("LauncherEditorial"),
    )

    private fun component(name: String) = ComponentName(context.packageName, "${context.packageName}.$name")

    private fun enabled(component: ComponentName): Boolean = when (pm.getComponentEnabledSetting(component)) {
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
        PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> component == aliases.getValue("default")
        else -> false
    }

    @Synchronized
    fun setIcon(style: String) {
        val target = requireNotNull(aliases[style]) { "Unsupported launcher style" }
        val before = aliases.values.associateWith { pm.getComponentEnabledSetting(it) }
        if (enabled(target) && aliases.values.none { it != target && enabled(it) }) return
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                // One atomic package-manager transaction on Android 13+.
                pm.setComponentEnabledSettings(aliases.values.map {
                    PackageManager.ComponentEnabledSetting(
                        it,
                        if (it == target) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                })
            } else {
                // Older Android: never disable the last working launcher entry first.
                pm.setComponentEnabledSetting(target, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                aliases.values.filter { it != target }.forEach {
                    pm.setComponentEnabledSetting(it, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                }
            }
            check(enabled(target) && aliases.values.none { it != target && enabled(it) })
        } catch (failure: Exception) {
            // Restore enabled entries before disabling extras, so rollback cannot strand the app.
            val oldEnabled = before.filter { (component, state) ->
                state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                    (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && component == aliases.getValue("default"))
            }.keys
            oldEnabled.forEach { component ->
                runCatching { pm.setComponentEnabledSetting(component, before.getValue(component), PackageManager.DONT_KILL_APP) }
            }
            // If restoration itself failed, keep any working entry rather than remove the last one.
            if (oldEnabled.any { enabled(it) }) {
                before.filterKeys { it !in oldEnabled }.forEach { (component, state) ->
                    runCatching { pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP) }
                }
            }
            throw failure
        }
    }

    companion object {
        fun register(messenger: BinaryMessenger, context: Context) {
            val manager = LauncherIconManager(context.applicationContext)
            MethodChannel(messenger, "runtrail/launcher_icon").setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSupport" -> result.success(true)
                    "setIcon" -> {
                        val style = call.argument<String>("style")
                        if (style == null || !manager.aliases.containsKey(style)) {
                            result.error("invalid_icon_style", "Unknown launcher icon style", null)
                        } else {
                            try {
                                manager.setIcon(style)
                                result.success(null)
                            } catch (_: Exception) {
                                result.error("launcher_icon_failed", "Unable to update launcher icon", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
