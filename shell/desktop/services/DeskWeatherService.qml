// Desktop adapter over the shell's real services/WeatherService.qml
// (Open-Meteo, configured via core/Config.qml's weather section) rather than
// porting impasto's own wttr.in-backed scripts/weather.py -- one real
// weather backend beats two, and the shell's already has real lat/long
// config, a settings surface and history. Exposes impasto's WeatherService-
// shaped API (place/glyph/description/high/low/hourly) for faces/analogue/
// WeatherFace.qml and the modern faces' weather rows.

pragma Singleton

import QtQuick
import Quickshell
import "../../services" as Shell
import "../../core" as Core

Singleton {
    id: root

    readonly property bool available: Shell.WeatherService.available
    readonly property string place: Core.Config.weather.locationName
    readonly property real temperature: Math.round(Shell.WeatherService.temperature)
    readonly property real feelsLike: Math.round(Shell.WeatherService.apparentTemperature)
    readonly property real high: Math.round(Shell.WeatherService.highTemperature)
    readonly property real low: Math.round(Shell.WeatherService.lowTemperature)
    readonly property string description: Shell.WeatherService.condition
    readonly property string glyph: Shell.WeatherService.icon
    readonly property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }

    // impasto's shape: [{ hour, temperature, glyph, rain, tomorrow }, ...],
    // today and tomorrow. The shell's hourlyForecast only carries a display
    // "time" string (not a Date), so `hour`/`tomorrow` are reconstructed
    // from the current wall-clock hour plus the entry's offset -- good
    // enough for the today/tomorrow grouping the faces do with it.
    readonly property var hourly: {
        const source = Shell.WeatherService.hourlyForecast || []
        const nowHour = new Date().getHours()
        return source.map((entry, index) => ({
            hour: (nowHour + index) % 24,
            temperature: entry.temperature,
            glyph: entry.icon,
            rain: entry.precipitation,
            tomorrow: nowHour + index >= 24
        }))
    }

    // Added for the dashboard port's WeatherCard (bar/island/controls/
    // WeatherCard.qml). The shell's WeatherService has no subscribe/
    // release lifecycle (it polls on its own timer regardless), so these
    // are no-ops kept only so ported Component.onCompleted/onDestruction
    // calls need no further edits.
    function subscribe(): void {}
    function release(): void {}
}
