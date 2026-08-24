pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Models
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: {
        const c = nState ? nState.selectedWallpaperCategory : "";
        return c ? (c.slice(0, 1).toUpperCase() + c.slice(1)) : "";
    }
    isSubPage: true

    property int displayLimit: 20
    readonly property int pageSize: 20

    property var cachedCategoryWalls: []

    readonly property real cellWidth: Math.floor((root.cappedWidth - (Config.nexus.wallpapersPerRow - 1) * grid.columnSpacing) / Config.nexus.wallpapersPerRow)

    function updateCategoryWalls() {
        if (!root.nState || !root.nState.selectedWallpaperCategory) {
            root.cachedCategoryWalls = [];
            return;
        }
        const category = root.nState.selectedWallpaperCategory;
        const mode = Wallpapers.filterMode;
        const walls = (Wallpapers.rawEntries || []).filter(w => {
            if (Wallpapers.getCategoryFor(w) !== category)
                return false;
            const isVid = Wallpapers.isVideo(w.path);
            if (mode === 0 && isVid)
                return false;
            if (mode === 1 && !isVid)
                return false;
            return true;
        }).sort((a, b) => a.name.localeCompare(b.name));
        root.cachedCategoryWalls = walls;
    }

    Component.onCompleted: updateCategoryWalls()

    data: [
        Connections {
            target: Wallpapers
            function onRawEntriesChanged() {
                root.updateCategoryWalls();
            }
            function onFilterModeChanged() {
                root.updateCategoryWalls();
            }
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        GridLayout {
            id: grid
            Layout.fillWidth: true

            columns: Config.nexus.wallpapersPerRow
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.large

            Repeater {
                id: categoryWalls
                model: root.cachedCategoryWalls.slice(0, root.displayLimit)

                WallItem {
                    required property var modelData

                    Layout.preferredWidth: root.cellWidth
                    Layout.maximumWidth: root.cellWidth
                    Layout.fillWidth: false

                    readonly property var fileProperties: {
                        const _ = Wallpapers.cacheBuster;
                        return Wallpapers.getParsedProperty(modelData?.path);
                    }

                    source: {
                        if (!modelData)
                            return "";
                        const path = String(modelData.path);
                        if (Wallpapers.isVideo(path)) {
                            return Wallpapers.getWallpaperThumb(path, Wallpapers.cacheBuster);
                        }
                        return path;
                    }
                    formatIcon: {
                        if (!modelData)
                            return "";
                        return Wallpapers.isVideo(modelData.path) ? "smart_display" : "image";
                    }
                    formatText: fileProperties.format
                    fpsText: fileProperties.fps
                    resText: fileProperties.resolution
                    text: modelData?.name ?? ""
                    onClicked: {
                        if (modelData) {
                            Wallpapers.setWallpaper(modelData.path);
                            Qt.callLater(() => {
                                if (root.nState)
                                    root.nState.closeSubPage();
                            });
                        }
                    }
                }
            }
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            visible: root.cachedCategoryWalls.length > root.displayLimit
            icon: "expand_more"
            text: qsTr("Show more (%1 remaining)").arg(root.cachedCategoryWalls.length - root.displayLimit)
            type: IconTextButton.Tonal
            onClicked: root.displayLimit += root.pageSize
        }
    }
}
