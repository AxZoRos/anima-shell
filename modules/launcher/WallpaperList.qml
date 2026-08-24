pragma ComponentBehavior: Bound

import "items"
import QtQuick
import Quickshell
import Caelestia.Config
import qs.components.controls
import qs.services

PathView {
    id: root

    required property SearchBar search
    required property var screenState
    required property var panels
    required property var content

    readonly property int itemWidth: Tokens.sizes.launcher.wallpaperWidth * 0.8 + Tokens.padding.medium * 2

    readonly property int rapidScrollThresholdMs: 60
    readonly property int settledPreviewDelayMs: 60
    readonly property int singleStepPreviewDelayMs: 60
    readonly property int fastFadePreviewDelayMs: 60

    property real lastSwitchTime: 0

    readonly property int numItems: {
        const screen = (QsWindow.window as QsWindow)?.screen;
        if (!screen)
            return 0;

        // Screen width - 4x outer rounding - 2x max side thickness (cause centered)
        const barMargins = Math.max(Config.border.thickness, panels.bar.implicitWidth);
        let outerMargins = 0;
        if (panels.popouts.hasCurrent && panels.popouts.currentCenter + panels.popouts.nonAnimHeight / 2 > screen.height - content.implicitHeight - Config.border.thickness * 2)
            outerMargins = panels.popouts.nonAnimWidth;
        if ((screenState.utilities || screenState.sidebar) && panels.utilities.implicitWidth > outerMargins)
            outerMargins = panels.utilities.implicitWidth;
        const maxWidth = screen.width - Config.border.rounding * 4 - (barMargins + outerMargins) * 2;
        if (maxWidth <= 0)
            return 0;
        const maxItemsOnScreen = Math.floor(maxWidth / itemWidth);
        const visible = Math.min(maxItemsOnScreen, Config.launcher.maxWallpapers, root.count);
        if (visible === 2)
            return 1;
        if (visible > 1 && visible % 2 === 0)
            return visible - 1;
        return visible;
    }

    function resolveCurrentTargetIndex(): int {
        const target = root.content ? root.content.categoryAwareTarget(Wallpapers.filterMode) : Wallpapers.actualCurrent;
        const foundIdx = Wallpapers.indexOf(target);
        return foundIdx >= 0 ? foundIdx : 0;
    }

    currentIndex: resolveCurrentTargetIndex()

    function jumpToIndex(targetIdx: int) {
        if (targetIdx < 0 || targetIdx >= count)
            return;

        positionViewAtIndex(targetIdx, PathView.Center);
        currentIndex = targetIdx;
        previewDebounce.restart();
    }

    property string debouncedSearch: ""

    onDebouncedSearchChanged: {
        if (debouncedSearch !== "") {
            root.jumpToIndex(0);
        } else {
            Qt.callLater(() => {
                const target = root.content ? root.content.categoryAwareTarget(Wallpapers.filterMode) : Wallpapers.actualCurrent;
                const foundIdx = Wallpapers.indexOf(target);
                root.jumpToIndex(foundIdx >= 0 ? foundIdx : 0);
            });
        }
    }

    Timer {
        id: searchDebounce
        interval: 120
        repeat: false
        onTriggered: {
            const queryText = root.search.text.split(" ").slice(1).join(" ");
            root.debouncedSearch = queryText;
        }
    }

    Connections {
        target: root.search
        enabled: !!root.search
        function onTextChanged() {
            const queryText = root.search.text.split(" ").slice(1).join(" ");
            if (queryText.trim() === "") {
                searchDebounce.stop();
                root.debouncedSearch = "";
            } else {
                searchDebounce.restart();
            }
        }
    }

    // Direct reactive array model without ScriptModel diff overhead
    model: {
        Wallpapers.list;
        return Wallpapers.query(root.debouncedSearch);
    }

    onWidthChanged: {
        if (width > 0 && count > 0) {
            positionViewAtIndex(currentIndex, PathView.Center);
        }
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            const targetIdx = resolveCurrentTargetIndex();
            jumpToIndex(targetIdx);
            Wallpapers.startSpiralQueue();
        });
    }

    Connections {
        target: root.screenState
        enabled: !!root.screenState
        function onLauncherChanged() {
            if (root.screenState.launcher) {
                Qt.callLater(() => {
                    const targetIdx = resolveCurrentTargetIndex();
                    root.jumpToIndex(targetIdx);
                    Wallpapers.startSpiralQueue();
                });
            }
        }
    }

    Component.onDestruction: Wallpapers.stopPreview()

    Timer {
        id: previewDebounce
        interval: root.singleStepPreviewDelayMs
        repeat: false
        onTriggered: {
            if (!root || !root.model || root.model.length === 0)
                return;
            const entry = root.model[root.currentIndex];
            if (entry && entry.path) {
                const clean = String(entry.path).replace(/^file:\/\//, "");
                Wallpapers.preview(clean);
            }
        }
    }

    onCurrentIndexChanged: {
        if (!Wallpapers.enableAnimation) {
            previewDebounce.interval = fastFadePreviewDelayMs;
            previewDebounce.restart();
            return;
        }

        const now = Date.now();
        const delta = now - lastSwitchTime;
        lastSwitchTime = now;

        previewDebounce.interval = (delta < rapidScrollThresholdMs) ? settledPreviewDelayMs : singleStepPreviewDelayMs;
        previewDebounce.restart();
    }

    implicitWidth: Math.min(numItems, count) * itemWidth
    pathItemCount: numItems
    cacheItemCount: 4

    snapMode: PathView.SnapToItem
    preferredHighlightBegin: 0.5
    preferredHighlightEnd: 0.5
    highlightRangeMode: PathView.StrictlyEnforceRange

    delegate: WallpaperItem {
        screenState: root.screenState
    }

    path: Path {
        startY: root.height / 2
        PathAttribute {
            name: "z"
            value: 0
        }
        PathLine {
            x: root.width / 2
            relativeY: 0
        }
        PathAttribute {
            name: "z"
            value: 1
        }
        PathLine {
            x: root.width
            relativeY: 0
        }
    }
}
