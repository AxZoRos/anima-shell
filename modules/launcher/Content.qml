pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property ScreenState screenState
    required property var panels
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: search.height + listWrapper.height + padding + search.anchors.bottomMargin + (wallpaperControlsContainer.visible ? wallpaperControlsContainer.implicitHeight + Tokens.spacing.small + root.padding : 0) + (categoryFlickable.visible ? categoryFlickable.implicitHeight + root.padding : 0)

    function performJump(targetPath) {
        Qt.callLater(() => {
            if (!list.currentList)
                return;
            let targetIdx = 0;
            if (targetPath) {
                const found = Wallpapers.indexOf(targetPath);
                if (found >= 0)
                    targetIdx = found;
            }
            if (typeof list.currentList.jumpToIndex === "function") {
                list.currentList.jumpToIndex(targetIdx);
            } else {
                list.currentList.currentIndex = targetIdx;
            }
        });
    }

    function categoryAwareTarget(mode) {
        if (mode === 0 && Wallpapers.selectedCategory !== "All" && !Wallpapers.categoryHasStatics(Wallpapers.selectedCategory)) {
            Wallpapers.selectedCategory = "All";
        } else if (mode === 1 && Wallpapers.selectedCategory !== "All" && !Wallpapers.categoryHasVideos(Wallpapers.selectedCategory)) {
            Wallpapers.selectedCategory = "All";
        }

        if (Wallpapers.selectedCategory !== "All") {
            return Wallpapers.categoryMemory[Wallpapers.selectedCategory] || "";
        }

        if (mode === 0)
            return Wallpapers.isVideo(Wallpapers.actualCurrent) ? Wallpapers.lastStatic : Wallpapers.actualCurrent;
        if (mode === 1)
            return Wallpapers.isVideo(Wallpapers.actualCurrent) ? Wallpapers.actualCurrent : Wallpapers.lastAnimated;
        if (Wallpapers.filterMode === 0)
            return Wallpapers.lastStatic;
        if (Wallpapers.filterMode === 1)
            return Wallpapers.lastAnimated;
        return Wallpapers.actualCurrent;
    }

    function selectCategoryByIndex(idx) {
        if (!Wallpapers.categories || idx < 0 || idx >= Wallpapers.categories.length)
            return;
        const cat = Wallpapers.categories[idx];
        Wallpapers.selectedCategory = cat;

        let target = "";
        if (cat === "All") {
            if (Wallpapers.filterMode === 0)
                target = Wallpapers.lastStatic;
            else if (Wallpapers.filterMode === 1)
                target = Wallpapers.lastAnimated;
            else
                target = Wallpapers.actualCurrent;
        } else {
            target = Wallpapers.categoryMemory[cat] || "";
        }
        root.performJump(target);
    }

    function cycleCategory(forward) {
        if (forward === undefined)
            forward = true;
        if (!Wallpapers.categories || Wallpapers.categories.length <= 1)
            return;
        const cats = Wallpapers.categories;
        let idx = cats.indexOf(Wallpapers.selectedCategory);
        if (idx < 0)
            idx = 0;
        const nextIdx = forward ? ((idx + 1) % cats.length) : ((idx - 1 + cats.length) % cats.length);
        root.selectCategoryByIndex(nextIdx);
    }

    function cycleFilterMode(forward) {
        if (forward === undefined)
            forward = true;
        const order = [2, 0, 1];
        let currIdx = order.indexOf(Wallpapers.filterMode);
        if (currIdx < 0)
            currIdx = 0;
        const nextIdx = forward ? ((currIdx + 1) % order.length) : ((currIdx - 1 + order.length) % order.length);
        const nextMode = order[nextIdx];

        const target = root.categoryAwareTarget(nextMode);
        Wallpapers.filterMode = nextMode;
        root.performJump(target);
    }

    Item {
        id: wallpaperControlsContainer
        visible: list.showWallpapers
        anchors.bottom: listWrapper.top
        anchors.bottomMargin: Tokens.spacing.small
        anchors.horizontalCenter: parent.horizontalCenter
        implicitHeight: 36
        implicitWidth: segmentedContainer.implicitWidth

        Item {
            id: segmentedContainer
            anchors.centerIn: parent
            width: implicitWidth
            height: implicitHeight
            implicitHeight: 36
            implicitWidth: segmentedRow.implicitWidth + 8

            StyledRect {
                id: activeIndicator
                height: 30
                y: 3
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary
                z: 0

                readonly property Item targetSeg: Wallpapers.filterMode === 2 ? allSeg : (Wallpapers.filterMode === 0 ? staticSeg : animSeg)
                x: targetSeg ? (segmentedRow.x + targetSeg.x) : 4
                width: targetSeg ? targetSeg.width : 0

                Behavior on x {
                    NumberAnimation {
                        duration: 280
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on width {
                    NumberAnimation {
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Row {
                id: segmentedRow
                anchors.centerIn: parent
                spacing: 0
                z: 1

                Item {
                    id: allSeg
                    width: implicitWidth
                    height: implicitHeight
                    implicitHeight: 30
                    implicitWidth: allLayout.implicitWidth + Tokens.padding.large * 2

                    Row {
                        id: allLayout
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "collections"
                            fontStyle: Tokens.font.icon.small
                            color: Wallpapers.filterMode === 2 ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color {
                                CAnim {}
                            }
                        }
                        StyledText {
                            text: qsTr("All")
                            font: Tokens.font.label.medium
                            color: Wallpapers.filterMode === 2 ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color {
                                CAnim {}
                            }
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        onClicked: {
                            const target = root.categoryAwareTarget(2);
                            Wallpapers.filterMode = 2;
                            root.performJump(target);
                        }
                    }
                }

                Item {
                    id: staticSeg
                    width: implicitWidth
                    height: implicitHeight
                    implicitHeight: 30
                    implicitWidth: staticLayout.implicitWidth + Tokens.padding.large * 2

                    Row {
                        id: staticLayout
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "image"
                            fontStyle: Tokens.font.icon.small
                            color: Wallpapers.filterMode === 0 ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color {
                                CAnim {}
                            }
                        }
                        StyledText {
                            text: qsTr("Static")
                            font: Tokens.font.label.medium
                            color: Wallpapers.filterMode === 0 ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color {
                                CAnim {}
                            }
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        onClicked: {
                            const target = root.categoryAwareTarget(0);
                            Wallpapers.filterMode = 0;
                            root.performJump(target);
                        }
                    }
                }

                Item {
                    id: animSeg
                    width: implicitWidth
                    height: implicitHeight
                    implicitHeight: 30
                    implicitWidth: animLayout.implicitWidth + Tokens.padding.large * 2

                    Row {
                        id: animLayout
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: "smart_display"
                            fontStyle: Tokens.font.icon.small
                            color: Wallpapers.filterMode === 1 ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color {
                                CAnim {}
                            }
                        }
                        StyledText {
                            text: qsTr("Animated")
                            font: Tokens.font.label.medium
                            color: Wallpapers.filterMode === 1 ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color {
                                CAnim {}
                            }
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        onClicked: {
                            const target = root.categoryAwareTarget(1);
                            Wallpapers.filterMode = 1;
                            root.performJump(target);
                        }
                    }
                }
            }
        }

        // Expandable Action Capsule
        StyledRect {
            id: actionCapsule
            anchors.left: segmentedContainer.right
            anchors.leftMargin: Tokens.spacing.small
            anchors.verticalCenter: segmentedContainer.verticalCenter
            implicitHeight: 32
            implicitWidth: 32 + (capsuleHover.hovered ? ((32 + Tokens.spacing.extraSmall) * 2) : 0)
            radius: Tokens.rounding.full
            color: capsuleHover.hovered ? Colours.tPalette.m3surfaceContainerHigh : "transparent"
            clip: true

            Behavior on implicitWidth {
                NumberAnimation {
                    duration: 240
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                CAnim {}
            }

            HoverHandler {
                id: capsuleHover
            }

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacing.extraSmall

                Item {
                    implicitWidth: 32
                    implicitHeight: 32

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "shuffle"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurface
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        onClicked: {
                            if (list.currentList && list.currentList.count > 0) {
                                const randomIndex = Math.floor(Math.random() * list.currentList.count);
                                if (typeof list.currentList.jumpToIndex === "function") {
                                    list.currentList.jumpToIndex(randomIndex);
                                } else {
                                    list.currentList.currentIndex = randomIndex;
                                }
                            } else {
                                Wallpapers.setRandom();
                            }
                        }
                    }
                }

                Item {
                    id: badgeToggleBtn
                    implicitHeight: 32
                    implicitWidth: capsuleHover.hovered ? 32 : 0
                    opacity: capsuleHover.hovered ? 1 : 0
                    clip: true

                    Behavior on implicitWidth {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: Wallpapers.badgeMode === 0 ? "badge" : "label_off"
                        fontStyle: Tokens.font.icon.small
                        color: Wallpapers.badgeMode === 0 ? Colours.palette.m3primary : Colours.palette.m3outline
                        Behavior on color {
                            CAnim {}
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        onClicked: Wallpapers.cycleBadgeMode()
                    }
                }

                Item {
                    id: rescanBtn
                    implicitHeight: 32
                    implicitWidth: capsuleHover.hovered ? 32 : 0
                    opacity: capsuleHover.hovered ? 1 : 0
                    clip: true

                    Behavior on implicitWidth {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "refresh"
                        fontStyle: Tokens.font.icon.small
                        color: (Wallpapers.isScanning || Wallpapers.isGenerating) ? Colours.palette.m3primary : Colours.palette.m3onSurface
                        Behavior on color {
                            CAnim {}
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        enabled: !(Wallpapers.isScanning || Wallpapers.isGenerating)
                        onClicked: Wallpapers.refreshAnimatedThumbs()
                    }
                }
            }
        }

        StyledRect {
            id: statusPill
            readonly property bool isBusy: Wallpapers.isScanning || Wallpapers.isGenerating || Wallpapers.queueRemaining > 0
            visible: opacity > 0
            opacity: isBusy ? 1.0 : 0.0

            anchors.left: actionCapsule.right
            anchors.leftMargin: Tokens.spacing.extraSmall
            anchors.verticalCenter: segmentedContainer.verticalCenter
            implicitHeight: 28
            implicitWidth: pillLayout.implicitWidth + Tokens.padding.small * 2
            radius: Tokens.rounding.full
            color: "transparent"

            Row {
                id: pillLayout
                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "burst_mode"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: Wallpapers.queueRemaining > 0 ? `${Wallpapers.queueRemaining}` : (Wallpapers.isScanning ? qsTr("Scan...") : "")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Item {
        id: listWrapper
        implicitWidth: list.width
        implicitHeight: list.height + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: categoryFlickable.visible ? categoryFlickable.top : search.top
        anchors.bottomMargin: root.padding

        ContentList {
            id: list
            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight - search.implicitHeight - root.padding * 3 - (wallpaperControlsContainer.visible ? wallpaperControlsContainer.implicitHeight + Tokens.spacing.small + root.padding : 0) - (categoryFlickable.visible ? categoryFlickable.implicitHeight + root.padding : 0)
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    Flickable {
        id: categoryFlickable
        visible: list.showWallpapers && Wallpapers.categories && Wallpapers.categories.length > 1
        implicitWidth: Math.min(categoryRow.implicitWidth, root.width - root.padding * 2)
        implicitHeight: categoryRow.implicitHeight
        contentWidth: categoryRow.implicitWidth
        contentHeight: categoryRow.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        anchors.bottom: search.top
        anchors.bottomMargin: root.padding
        anchors.horizontalCenter: parent.horizontalCenter

        Row {
            id: categoryRow
            spacing: Tokens.spacing.small

            Repeater {
                model: Wallpapers.categories

                delegate: StyledRect {
                    id: chip
                    required property string modelData
                    readonly property bool isSelected: Wallpapers.selectedCategory === chip.modelData

                    implicitWidth: chipLayout.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 30
                    radius: Tokens.rounding.full
                    color: chip.isSelected ? Qt.rgba(Colours.palette.m3primary.r, Colours.palette.m3primary.g, Colours.palette.m3primary.b, 0.16) : "transparent"

                    Behavior on color {
                        CAnim {}
                    }

                    Row {
                        id: chipLayout
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: chip.isSelected ? "folder_open" : "folder"
                            fontStyle: Tokens.font.icon.small
                            color: chip.isSelected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            opacity: chip.isSelected ? 1.0 : 0.65
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color {
                                CAnim {}
                            }
                            Behavior on opacity {
                                Anim {
                                    type: Anim.DefaultEffects
                                }
                            }
                        }

                        StyledText {
                            text: chip.modelData
                            font: chip.isSelected ? Tokens.font.label.builders.medium.weight(Font.DemiBold).build() : Tokens.font.label.medium
                            color: chip.isSelected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            opacity: chip.isSelected ? 1.0 : 0.7
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color {
                                CAnim {}
                            }
                            Behavior on opacity {
                                Anim {
                                    type: Anim.DefaultEffects
                                }
                            }
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        onClicked: {
                            Wallpapers.selectedCategory = chip.modelData;

                            let target = "";
                            if (chip.modelData === "All") {
                                if (Wallpapers.filterMode === 0)
                                    target = Wallpapers.lastStatic;
                                else if (Wallpapers.filterMode === 1)
                                    target = Wallpapers.lastAnimated;
                                else
                                    target = Wallpapers.actualCurrent;
                            } else {
                                target = Wallpapers.categoryMemory[chip.modelData] || "";
                            }

                            root.performJump(target);
                        }
                    }
                }
            }
        }
    }

    SearchBar {
        id: search
        objectName: "launcherSearch"

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.bottomMargin: CUtils.clamp(root.padding - Config.border.thickness, 0, root.padding)

        topPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)
        bottomPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)

        placeholderText: qsTr("Type \"%1\" for commands").arg(GlobalConfig.launcher.actionPrefix)

        onAccepted: {
            const currentItem = list.currentList?.currentItem;
            if (currentItem) {
                if (list.showWallpapers) {
                    const chosenPath = currentItem.modelData.path;
                    if (Colours.scheme === "dynamic" && chosenPath !== Wallpapers.actualCurrent)
                        Wallpapers.previewColourLock = true;
                    Wallpapers.setWallpaper(chosenPath);
                    root.screenState.launcher = false;
                } else if (text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    if (text.startsWith(`${GlobalConfig.launcher.actionPrefix}calc `)) {
                        currentItem.onClicked();
                    } else {
                        currentItem.modelData.onClicked(list.currentList);
                    }
                } else {
                    Apps.launch(currentItem.modelData);
                    root.screenState.launcher = false;
                }
            }
        }

        Keys.onUpPressed: list.currentList?.decrementCurrentIndex()
        Keys.onDownPressed: list.currentList?.incrementCurrentIndex()
        Keys.onEscapePressed: root.screenState.launcher = false

        Keys.onPressed: event => {
            if (list.showWallpapers) {
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_B) {
                    Wallpapers.cycleBadgeMode();
                    event.accepted = true;
                    return;
                }

                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
                    if (list.currentList && list.currentList.count > 0) {
                        const randomIndex = Math.floor(Math.random() * list.currentList.count);
                        if (typeof list.currentList.jumpToIndex === "function") {
                            list.currentList.jumpToIndex(randomIndex);
                        } else {
                            list.currentList.currentIndex = randomIndex;
                        }
                    } else {
                        Wallpapers.setRandom();
                    }
                    event.accepted = true;
                    return;
                }

                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Tab) {
                    const forward = !(event.modifiers & Qt.ShiftModifier);
                    root.cycleFilterMode(forward);
                    event.accepted = true;
                    return;
                }

                if (event.modifiers & Qt.AltModifier) {
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        root.cycleCategory(false);
                        event.accepted = true;
                        return;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        root.cycleCategory(true);
                        event.accepted = true;
                        return;
                    }

                    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        const targetCatIndex = event.key - Qt.Key_1;
                        root.selectCategoryByIndex(targetCatIndex);
                        event.accepted = true;
                        return;
                    }
                }
            }

            if (!GlobalConfig.launcher.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab) {
                list.currentList?.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                list.currentList?.decrementCurrentIndex();
                event.accepted = true;
            }
        }

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher) {
                    search.text = "";
                    Wallpapers.stopPreview();
                }
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }
}
