package co.edu.uniandes.senecapp

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "senecapp/ambient_light")
            .setStreamHandler(AmbientLightHandler(applicationContext))
    }
}

private class AmbientLightHandler(context: Context) :
    EventChannel.StreamHandler, SensorEventListener {

    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val sensor: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_LIGHT)
    private var events: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        if (sensor == null) {
            sink?.error("NO_SENSOR", "This phone has no ambient light sensor", null)
            sink?.endOfStream()
            return
        }
        events = sink
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        events = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        events?.success(event.values[0].toDouble())
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
