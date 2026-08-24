pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import Caelestia.Models
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Wallpapers")
    isSubPage: true

    property int displayLimit: 20
    readonly property int pageSize: 20

    property int filterMode: 2

    property var filteredList: []

    readonly property real cellWidth: Math.floor((root.cappedWidth - (Config.nexus.wallpapersPerRow - 1) * grid.columnSpacing) / Config.nexus.wallpapersPerRow)

    function isRootWall(w) {
        return Wallpapers.getCategoryFor(w) === "All";
    }

    function updateFilteredList() {
        const walls = Wallpapers.rawEntries || [];
        const mode = root.filterMode;
        const categories = {};
        const list = [];

        for (let i = 0; i < walls.length; i++) {
            const w = walls[i];
            const isVid = Wallpapers.isVideo(w.path);
            if (mode === 0 && isVid)
                continue;  // Static
            if (mode === 1 && !isVid)
                continue; // Animated

            const cat = Wallpapers.getCategoryFor(w);
            if (cat !== "All") {
                if (!(cat in categories) || categories[cat].name.localeCompare(w.name) > 0)
                    categories[cat] = w;
            } else {
                list.push(w);
            }
        }
        list.push(...Object.values(categories));
        list.sort((a, b) => (isRootWall(a) - isRootWall(b)) || a.name.localeCompare(b.name));
        root.filteredList = list;
    }

    Component.onCompleted: updateFilteredList()

    onFilterModeChanged: {
        root.displayLimit = root.pageSize;
        root.updateFilteredList();
    }

    data: [
        Connections {
            target: Wallpapers
            function onRawEntriesChanged() {
                root.displayLimit = root.pageSize;
                root.updateFilteredList();
            }
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.small

        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.medium
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "photo_library"
                text: qsTr("Browse")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: browseDialog.open()

                FileDialog {
                    id: browseDialog

                    title: qsTr("Select an image")
                    filterLabel: qsTr("Image files")
                    filters: Images.validImageExtensions
                    onAccepted: path => {
                        Wallpapers.setWallpaper(path);
                        root.nState.closeSubPage();
                    }
                }
            }

            IconTextButton {
                icon: "shuffle"
                text: qsTr("Random")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                type: IconTextButton.Tonal
                onClicked: {
                    Wallpapers.setRandom();
                    root.nState.closeSubPage();
                }
            }

            IconTextButton {
                icon: "refresh"
                text: qsTr("Rescan")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                horizontalPadding: Tokens.padding.large
                verticalPadding: Tokens.padding.medium
                type: IconTextButton.Tonal
                onClicked: Wallpapers.refreshAnimatedThumbs()
            }
        }

        WallItem {
            Layout.fillWidth: true
            imgHeight: Math.round(root.cappedWidth * 0.3)
            radius: Tokens.rounding.extraLarge
            source: Wallpapers.fallback
            text: qsTr("Featured wallpaper")
            fillLabel: false
            onClicked: {
                Wallpapers.setWallpaper(Wallpapers.fallback);
                root.nState.closeSubPage();
            }
        }

        RowLayout {
            Layout.topMargin: Tokens.spacing.large
            Layout.fillWidth: true

            StyledText {
                text: qsTr("Local wallpapers")
                font: Tokens.font.title.small
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }

            ButtonRow {
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacing.small

                IconTextButton {
                    icon: "collections"
                    text: qsTr("All")
                    isToggle: true
                    checked: root.filterMode === 2
                    onClicked: root.filterMode = 2
                }
                IconTextButton {
                    icon: "image"
                    text: qsTr("Static")
                    isToggle: true
                    checked: root.filterMode === 0
                    onClicked: root.filterMode = 0
                }
                IconTextButton {
                    icon: "smart_display"
                    text: qsTr("Animated")
                    isToggle: true
                    checked: root.filterMode === 1
                    onClicked: root.filterMode = 1
                }
            }
        }

        GridLayout {
            id: grid
            Layout.fillWidth: true
            visible: root.filteredList.length > 0

            columns: Config.nexus.wallpapersPerRow
            rowSpacing: Tokens.spacing.medium
            columnSpacing: Tokens.spacing.large

            Repeater {
                id: localWalls
                model: root.filteredList.slice(0, root.displayLimit)

                WallItem {
                    required property var modelData

                    Layout.preferredWidth: root.cellWidth
                    Layout.maximumWidth: root.cellWidth
                    Layout.fillWidth: false

                    readonly property bool isCategoryFolder: !!modelData && Wallpapers.getCategoryFor(modelData) !== "All"
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
                        if (isCategoryFolder)
                            return "folder";
                        return Wallpapers.isVideo(modelData.path) ? "smart_display" : "image";
                    }
                    formatText: isCategoryFolder ? "" : fileProperties.format
                    fpsText: isCategoryFolder ? "" : fileProperties.fps
                    resText: isCategoryFolder ? "" : fileProperties.resolution
                    text: {
                        if (!modelData)
                            return "";
                        const cat = Wallpapers.getCategoryFor(modelData);
                        if (cat !== "All") {
                            return cat.slice(0, 1).toUpperCase() + cat.slice(1);
                        }
                        return modelData.name;
                    }
                    onClicked: {
                        if (modelData) {
                            const cat = Wallpapers.getCategoryFor(modelData);
                            if (cat !== "All") {
                                root.nState.selectedWallpaperCategory = cat;
                                root.nState.openSubPage(2);
                            } else {
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
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            visible: root.filteredList.length > root.displayLimit
            icon: "expand_more"
            text: qsTr("Show more (%1 remaining)").arg(root.filteredList.length - root.displayLimit)
            type: IconTextButton.Tonal
            onClicked: root.displayLimit += root.pageSize
        }

        Loader {
            Layout.fillWidth: true
            active: root.filteredList.length === 0
            visible: active

            sourceComponent: StyledRect {
                color: Colours.tPalette.m3surfaceContainer
                radius: Tokens.rounding.extraLarge
                implicitHeight: noWallsLayout.implicitHeight + Tokens.padding.extraExtraLarge * 2

                ColumnLayout {
                    id: noWallsLayout

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3outline
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No local wallpapers found")
                        color: Colours.palette.m3outline
                        font: Tokens.font.title.small
                    }
                }
            }
        }
    }
}
