pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Caelestia.Config
import QtQuick.Effects
import M3Shapes
import qs.components
import qs.components.images
import qs.services

Item {
    id: root

    property string source: Wallpapers.current
    property Item current: null
    property string settledSource: ""

    readonly property int sourceChangeDebounceMs: 80

    readonly property var shapes: [MaterialShape.Circle, MaterialShape.Square, MaterialShape.Diamond, MaterialShape.ClamShell, MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Clover4Leaf, MaterialShape.SoftBurst, MaterialShape.Cookie6Sided]

    function toFileUrl(path) {
        if (!path)
            return "";
        const clean = String(path).trim();
        if (clean.startsWith("file://"))
            return clean;
        return Qt.resolvedUrl(clean);
    }

    function activateLayer(layer, path) {
        layer.path = path;
        layer.state = "active";
        root.current = layer;
    }

    Timer {
        id: coalesceTimer
        interval: root.sourceChangeDebounceMs
        repeat: false
        onTriggered: root.applySourceChange()
    }

    onSourceChanged: {
        if (source !== settledSource) {
            one.interrupt();
            two.interrupt();
        }
        coalesceTimer.restart();
    }

    function applySourceChange() {
        if (source === settledSource && root.current?.state === "active")
            return;
        settledSource = source;

        if (!settledSource) {
            one.purge();
            two.purge();
            root.current = null;
            return;
        }

        const prevLayer = root.current;
        const nextLayer = prevLayer === one ? two : one;

        nextLayer.purge();

        if (prevLayer) {
            prevLayer.interrupt();
            prevLayer.state = "background";
        }

        activateLayer(nextLayer, settledSource);
    }

    Component.onCompleted: {
        if (source) {
            settledSource = source;
            activateLayer(one, settledSource);
        }
    }

    Img {
        id: one
        layerName: "Layer-1"
    }
    Img {
        id: two
        layerName: "Layer-2"
    }

    component Img: Item {
        id: img

        property string layerName: "Layer"
        property string path: ""
        state: "inactive"

        readonly property bool isVideo: Wallpapers.isVideo(path)
        readonly property bool animsEnabled: !!Wallpapers.enableAnimation
        readonly property int fadeMs: 400
        readonly property int maskDurationMs: 2500
        readonly property int maskCleanupBufferMs: 100
        readonly property real maskCompletionEpsilon: 1.5
        readonly property int resumeDelayMs: 80

        property bool renderActive: false
        property bool pendingVideoAnim: false

        readonly property bool isPlayerPlaying: !!(videoChannelLoader.item?.playing)
        readonly property bool videoFailed: isVideo && !!(videoChannelLoader.item?.hasError)

        anchors.fill: parent
        opacity: 0

        // Immediately aborts and destroys the running animation without waiting for timer completion
        function interrupt() {
            pendingVideoAnim = false;
            if (maskAnim.running) {
                maskAnim.stop();
            }
            if (state === "active" || state === "background") {
                maskRadius = maxRadius;
            }
        }

        // Fully releases buffer resources and resets pipeline state
        function purge() {
            cleanupTimer.stop();
            maskAnim.stop();
            pendingVideoAnim = false;
            maskRadius = 0;
            if (isVideo && videoChannelLoader.item) {
                videoChannelLoader.item.pause();
            }
            path = "";
            state = "inactive";
        }

        onIsPlayerPlayingChanged: {
            if (isPlayerPlaying && pendingVideoAnim && animsEnabled && state === "active") {
                pendingVideoAnim = false;
                maskAnim.stop();
                maskRadius = 0;
                maskAnim.restart();
            }
        }

        onVideoFailedChanged: {
            if (videoFailed && pendingVideoAnim && animsEnabled && state === "active") {
                pendingVideoAnim = false;
                maskAnim.stop();
                maskRadius = 0;
                maskAnim.restart();
            }
        }

        Timer {
            id: cleanupTimer
            interval: img.animsEnabled ? (img.maskDurationMs + img.maskCleanupBufferMs) : (img.fadeMs + 20)
            repeat: false
            onTriggered: img.purge()
        }

        states: [
            State {
                name: "active"
                PropertyChanges {
                    img.opacity: 1
                    img.z: 1
                    img.renderActive: true
                }
            },
            State {
                name: "background"
                PropertyChanges {
                    img.opacity: 1
                    img.z: 0
                    img.renderActive: true
                }
            },
            State {
                name: "inactive"
                PropertyChanges {
                    img.opacity: 0
                    img.z: 0
                    img.renderActive: false
                }
            }
        ]

        transitions: [
            Transition {
                from: "inactive"
                to: "active"
                NumberAnimation {
                    property: "opacity"
                    duration: img.fadeMs
                    easing.type: Easing.InOutQuad
                }
            }
        ]

        // Coordinates mask resets, cleanup timers, and shape selection across layer transitions
        onStateChanged: {
            maskAnim.stop();

            if (state === "active") {
                cleanupTimer.stop();
                if (animsEnabled) {
                    maskRadius = 0;
                    if (isVideo) {
                        if (videoChannelLoader.isPaused) {
                            pendingVideoAnim = false;
                            maskAnim.restart();
                        } else {
                            pendingVideoAnim = true;
                        }
                    } else {
                        pendingVideoAnim = false;
                        maskAnim.restart();
                    }
                } else {
                    pendingVideoAnim = false;
                    maskRadius = maxRadius;
                }
            } else if (state === "background") {
                pendingVideoAnim = false;
                maskRadius = maxRadius;
                cleanupTimer.restart();

                if (!animsEnabled) {
                    if (isVideo && videoChannelLoader.item) {
                        videoChannelLoader.item.pause();
                    }
                } else {
                    currentShape = root.shapes[Math.floor(Math.random() * root.shapes.length)];
                }
            } else if (state === "inactive") {
                cleanupTimer.stop();
                pendingVideoAnim = false;
                maskRadius = 0;
                if (isVideo && videoChannelLoader.item) {
                    videoChannelLoader.item.pause();
                }
                path = "";
            }
        }

        readonly property real maxRadius: Math.sqrt(width * width + height * height)
        property real maskRadius: 0
        property int currentShape: MaterialShape.Circle

        onMaxRadiusChanged: {
            if (!maskAnim.running && (state === "active" || state === "background")) {
                maskRadius = maxRadius;
            }
        }

        readonly property bool needsMask: animsEnabled && img.state === "active" && img.maskRadius < (img.maxRadius - img.maskCompletionEpsilon) && !!maskLoader.item

        Loader {
            id: maskLoader
            anchors.fill: parent
            active: img.animsEnabled

            sourceComponent: Item {
                anchors.fill: parent
                readonly property Item maskSource: maskSourceItem

                Item {
                    id: maskWrapper
                    anchors.fill: parent
                    visible: img.needsMask
                    MaterialShape {
                        anchors.centerIn: parent
                        width: img.maxRadius * 2
                        height: img.maxRadius * 2
                        shape: img.currentShape
                        color: "white"
                        scale: img.maxRadius > 0 ? (img.maskRadius / img.maxRadius) : 0
                    }
                }

                ShaderEffectSource {
                    id: maskSourceItem
                    sourceItem: maskWrapper
                    anchors.fill: parent
                    hideSource: true
                    live: img.needsMask
                    visible: false
                }
            }
        }

        Item {
            id: contentItem
            anchors.fill: parent

            layer.enabled: img.needsMask
            layer.effect: MultiEffect {
                maskEnabled: img.needsMask
                maskSource: maskLoader.item?.maskSource ?? null
            }

            CachingImage {
                id: thumbImg
                anchors.fill: parent
                path: (!img.isVideo && img.renderActive) ? img.path : ""
                source: (!img.isVideo && img.renderActive) ? img.path : ""
                visible: !img.isVideo && img.renderActive
                asynchronous: true

                onStatusChanged: {
                    if (status === Image.Ready && !img.isVideo && img.path === root.settledSource) {
                        root.current = img;
                    }
                }
            }

            // Dynamically creates and tears down VideoWallpaper to optimize VRAM
            Loader {
                id: videoChannelLoader
                anchors.fill: parent
                active: img.isVideo && img.path !== "" && img.renderActive
                source: "VideoWallpaper.qml"

                readonly property string screenName: (QsWindow.window as QsWindow)?.screen?.name ?? ""
                readonly property bool isPaused: WallpaperPauser.isScreenPaused(screenName)

                onIsPausedChanged: {
                    if (!item || !img.isVideo)
                        return;
                    if (isPaused) {
                        resumeTimer.stop();
                        item.pause();
                    } else if (img.state === "active") {
                        resumeTimer.restart();
                    }
                }

                Timer {
                    id: resumeTimer
                    interval: img.resumeDelayMs
                    repeat: false
                    onTriggered: {
                        if (videoChannelLoader.item && img.isVideo && !videoChannelLoader.isPaused && img.state === "active") {
                            videoChannelLoader.item.play();
                        }
                    }
                }

                // Configures media source and initial playback state when video layer loads
                onLoaded: {
                    if (item && img.path !== "") {
                        item.videoSource = root.toFileUrl(img.path);
                        item.autoStart = !isPaused;
                    }
                }
            }
        }

        Anim {
            id: maskAnim
            target: img
            property: "maskRadius"
            from: 0
            to: img.maxRadius
            type: Anim.Emphasized
            duration: img.maskDurationMs
        }
    }

    // Headless QtMultimedia warm-up to eliminate the initial 1-2s GUI freeze
    Timer {
        id: warmupTimer
        interval: 1200
        running: true
        repeat: false
        onTriggered: warmupLoader.active = true
    }

    Loader {
        id: warmupLoader
        active: false
        sourceComponent: Item {
            MediaPlayer {
                audioOutput: null
            }
        }
    }
}
