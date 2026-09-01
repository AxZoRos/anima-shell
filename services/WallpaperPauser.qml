pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Io
import qs.services
import qs.utils

Singleton {
    id: root

    property bool pauseOnBattery: false
    property bool pauseOnWindowOverlap: true
    property string hwDecoder: "auto"

    property bool paused: false
    property bool _loaded: false
    property string pauseReason: "None"

    // Maps monitor name to its pause state: { "DP-1": true, "HDMI-A-1": false }
    property var screenPauseMap: ({})

    readonly property real largeWindowAreaRatio: 0.7

    // Helper for monitor-specific wallpaper layers
    function isScreenPaused(screenName: string): bool {
        if (pauseOnBattery && UPower.onBattery)
            return true;
        if (!pauseOnWindowOverlap)
            return false;
        if (!screenName)
            return paused;
        return !!screenPauseMap[screenName];
    }

    function checkBatteryReason() {
        return (pauseOnBattery && UPower.onBattery) ? "Battery" : "";
    }

    // Evaluates desktop area occlusion for a specific monitor
    function checkMonitorOverlapReason(mon) {
        if (!mon)
            return "";
        const ws = mon.activeWorkspace;
        if (!ws || !ws.toplevels || !ws.toplevels.values)
            return "";

        const toplevels = ws.toplevels.values;
        if (toplevels.length >= 2) {
            return `2+ windows (${toplevels.length} total)`;
        }

        const screen = Quickshell.screens ? Quickshell.screens.find(s => s && s.name === mon.name) : null;
        const screenArea = screen ? (screen.width * screen.height) : 0;
        if (screenArea > 0 && toplevels.length === 1 && toplevels[0]) {
            const threshold = screenArea * largeWindowAreaRatio;
            const percent = Math.round(largeWindowAreaRatio * 100);
            const size = toplevels[0].lastIpcObject?.size;
            if (size && size.length >= 2 && (size[0] * size[1]) >= threshold) {
                const title = toplevels[0].lastIpcObject?.title ?? "Unknown";
                return `${percent}%+ area rule by: ${title} (${size[0]}x${size[1]})`;
            }
        }

        return "";
    }

    function checkWindowOverlapReason() {
        if (!pauseOnWindowOverlap)
            return "";
        const monitor = Hyprland.focusedMonitor;
        return checkMonitorOverlapReason(monitor);
    }

    function recalculate() {
        let batteryReason = checkBatteryReason();
        let newMap = {};

        const monitors = Hyprland.monitors?.values ?? [];
        for (let i = 0; i < monitors.length; i++) {
            const mon = monitors[i];
            if (!mon)
                continue;
            let monReason = batteryReason || (pauseOnWindowOverlap ? checkMonitorOverlapReason(mon) : "");
            newMap[mon.name] = !!monReason;
        }
        screenPauseMap = newMap;

        let focusedReason = batteryReason || checkWindowOverlapReason();
        paused = !!focusedReason;
        pauseReason = focusedReason || "None";
    }

    function scheduleRecalculate() {
        recalcTimer.restart();
    }

    readonly property var relevantEvents: new Set(["fullscreen", "changefloatingmode", "minimize", "movewindow", "openwindow", "closewindow", "moveworkspace", "focusedmon"])

    function isRelevantHyprlandEvent(name) {
        if (!name || typeof name !== "string")
            return false;
        const c = name.charCodeAt(0);
        if (c === 119 || c === 97 || c === 99 || c === 100) {
            if (name.startsWith("workspace") || name.startsWith("activewindow") || name.startsWith("createworkspace") || name.startsWith("destroyworkspace")) {
                return true;
            }
        }
        return relevantEvents.has(name);
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.scheduleRecalculate();
        }
        function onFocusedMonitorChanged() {
            root.scheduleRecalculate();
        }
        function onRawEvent(event) {
            if (root.isRelevantHyprlandEvent(event.name)) {
                root.scheduleRecalculate();
            }
        }
    }

    Connections {
        target: UPower
        function onOnBatteryChanged() {
            root.scheduleRecalculate();
        }
    }

    Timer {
        id: recalcTimer
        interval: 50
        repeat: false
        onTriggered: root.recalculate()
    }

    Timer {
        id: startupTimer
        interval: 1000
        repeat: true
        running: true
        property int attempts: 0
        onTriggered: {
            root.recalculate();
            attempts++;
            if (attempts >= 3)
                running = false;
        }
    }

    onPauseOnBatteryChanged: {
        scheduleRecalculate();
        if (_loaded)
            Wallpapers.saveUiState();
    }
    onPauseOnWindowOverlapChanged: {
        scheduleRecalculate();
        if (_loaded)
            Wallpapers.saveUiState();
    }

    // Injects HW decoder configuration and restarts shell process
    function setHwDecoder(val) {
        if (hwDecoder === val)
            return;
        hwDecoder = val;
        if (!_loaded)
            return;

        Wallpapers.saveUiState(true);
        Quickshell.execDetached(["sh", "-c", "sleep 0.1; qs -c caelestia kill; sleep 0.2; caelestia shell -d"]);
    }

    Component.onCompleted: {
        root._loaded = true;
        recalculate();
    }
}
