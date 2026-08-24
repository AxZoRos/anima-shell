pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia

Item {
    id: root

    property url videoSource
    property bool autoStart: true
    property bool _isDestroying: false
    property bool _initialFrameRendered: false

    onVideoSourceChanged: root._initialFrameRendered = false

    readonly property alias playbackState: player.playbackState
    readonly property alias mediaStatus: player.mediaStatus
    readonly property alias error: player.error
    readonly property alias errorString: player.errorString
    readonly property bool playing: !_isDestroying && playbackState === MediaPlayer.PlayingState
    readonly property bool hasError: !_isDestroying && (mediaStatus === MediaPlayer.InvalidMedia || error !== MediaPlayer.NoError)

    function play() {
        if (_isDestroying || videoSource.toString() === "")
            return;
        if (playbackState === MediaPlayer.PlayingState)
            return;

        root.autoStart = true;
        player.play();
    }

    function pause() {
        if (_isDestroying)
            return;
        root.autoStart = false;

        if (playbackState === MediaPlayer.PausedState || playbackState === MediaPlayer.StoppedState)
            return;

        if (root._initialFrameRendered) {
            player.pause();
        }
    }

    function stop() {
        if (playbackState === MediaPlayer.StoppedState)
            return;
        player.stop();
    }

    anchors.fill: parent

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    MediaPlayer {
        id: player

        videoOutput: output
        audioOutput: null
        loops: MediaPlayer.Infinite
        autoPlay: false
        source: root.videoSource

        onPositionChanged: {
            if (!root._initialFrameRendered && player.position > 0) {
                root._initialFrameRendered = true;
                if (!root.autoStart && !root._isDestroying && playbackState !== MediaPlayer.PausedState) {
                    player.pause();
                }
            }
        }

        onMediaStatusChanged: {
            if (root._isDestroying)
                return;

            if (mediaStatus === MediaPlayer.LoadedMedia && playbackState !== MediaPlayer.PlayingState) {
                player.play();
            }
        }
    }

    Component.onDestruction: {
        _isDestroying = true;
        player.stop();
        player.source = "";
    }
}
