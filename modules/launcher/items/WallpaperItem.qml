pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Images
import Caelestia.Models
import qs.components
import qs.components.effects
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    required property FileSystemEntry modelData
    required property ScreenState screenState

    scale: 0.5
    opacity: 0
    z: PathView.z ?? 0 // qmllint disable missing-property

    Component.onCompleted: {
        scale = Qt.binding(() => PathView.isCurrentItem ? 1 : PathView.onPath ? 0.8 : 0);
        opacity = Qt.binding(() => PathView.onPath ? 1 : 0);
    }

    readonly property bool isVid: Wallpapers.isVideo(root.modelData.path)

    readonly property var fileProperties: {
        const _ = Wallpapers.cacheBuster;
        return Wallpapers.getParsedProperty(root.modelData.path);
    }

    readonly property string formatIcon: root.isVid ? "smart_display" : "image"
    readonly property string formatText: fileProperties.format
    readonly property string fpsText: fileProperties.fps
    readonly property string bitrateText: fileProperties.bitrate

    readonly property string formatCorner: Wallpapers.badgesConfig?.formatCorner ?? "topLeft"
    readonly property string fpsCorner: Wallpapers.badgesConfig?.fpsCorner ?? "topRight"
    readonly property string bitrateCorner: Wallpapers.badgesConfig?.bitrateCorner ?? "bottomLeft"

    readonly property string thumbSource: {
        const _ = Wallpapers.cacheBuster;
        const p = root.modelData.path;
        if (!root.isVid) {
            return IUtils.urlForPath(p, Image.PreserveAspectCrop);
        }
        const clean = String(p).replace(/^file:\/\//, "");
        const b = (Wallpapers.itemBusters && (Wallpapers.itemBusters[clean] || Wallpapers.itemBusters[p])) || Wallpapers.cacheBuster || "";
        return Wallpapers.getWallpaperThumb(p, b);
    }

    implicitWidth: image.width + Tokens.padding.medium * 2
    implicitHeight: image.height + label.height + Tokens.spacing.extraSmall + Tokens.padding.large + Tokens.padding.medium

    component Badge: StyledRect {
        id: bRoot
        property string badgeType: ""
        property string corner: "none"
        property string iconName: ""
        property string badgeText: ""

        readonly property bool modeAllowed: Wallpapers.badgeMode === 0

        z: 5
        visible: modeAllowed && corner !== "none" && badgeText !== ""
        color: badgeMouse.containsMouse ? Qt.rgba(Colours.palette.m3primary.r, Colours.palette.m3primary.g, Colours.palette.m3primary.b, 0.9) : Qt.rgba(Colours.palette.m3surfaceContainer.r, Colours.palette.m3surfaceContainer.g, Colours.palette.m3surfaceContainer.b, 0.82)
        radius: Tokens.rounding.small
        implicitWidth: bLayout.implicitWidth + Tokens.padding.small * 2
        implicitHeight: bLayout.implicitHeight + Tokens.padding.extraSmall * 2
        width: implicitWidth
        height: implicitHeight

        x: (corner === "topLeft" || corner === "bottomLeft") ? Tokens.spacing.small : (parent ? (parent.width - width - Tokens.spacing.small) : 0)
        y: (corner === "topLeft" || corner === "topRight") ? Tokens.spacing.small : (parent ? (parent.height - height - Tokens.spacing.small) : 0)

        Behavior on x {
            Anim {
                type: Anim.DefaultEffects
            }
        }
        Behavior on y {
            Anim {
                type: Anim.DefaultEffects
            }
        }
        Behavior on color {
            CAnim {}
        }

        Row {
            id: bLayout
            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                visible: bRoot.iconName !== ""
                text: bRoot.iconName
                fontStyle: Tokens.font.icon.small
                color: badgeMouse.containsMouse ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color {
                    CAnim {}
                }
            }
            StyledText {
                text: bRoot.badgeText
                font: Tokens.font.label.small
                color: badgeMouse.containsMouse ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color {
                    CAnim {}
                }
            }
        }

        MouseArea {
            id: badgeMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: function (mouse) {
                mouse.accepted = true;
                if (mouse.button === Qt.RightButton) {
                    Wallpapers.hideBadge(bRoot.badgeType);
                } else {
                    Wallpapers.cycleBadgeCorner(bRoot.badgeType);
                }
            }
        }
    }

    Item {
        id: popContainer
        anchors.fill: parent

        StateLayer {
            radius: Tokens.rounding.large
            anchors.fill: parent
            onClicked: {
                Wallpapers.setWallpaper(root.modelData.path);
                root.screenState.launcher = false;
            }
        }

        Elevation {
            anchors.fill: image
            radius: image.radius
            opacity: root.PathView.isCurrentItem ? 1 : 0
            level: 4
            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        StyledClippingRect {
            id: image
            anchors.horizontalCenter: parent.horizontalCenter
            y: Tokens.padding.large
            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            implicitWidth: Tokens.sizes.launcher.wallpaperWidth
            implicitHeight: implicitWidth / 16 * 9
            width: implicitWidth
            height: implicitHeight

            MaterialIcon {
                anchors.centerIn: parent
                text: "image"
                color: Colours.tPalette.m3outline
                fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.DemiBold).build()
            }

            Image {
                id: thumbImg
                anchors.fill: parent
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                source: root.thumbSource
                smooth: !root.PathView.view?.moving ?? true
                sourceSize: {
                    const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                    const w = image.implicitWidth > 0 ? image.implicitWidth : 200;
                    const h = image.implicitHeight > 0 ? image.implicitHeight : 112;
                    return Qt.size(w * dpr, h * dpr);
                }
                retainWhileLoading: true
                onStatusChanged: {
                    if (status === Image.Error && root.isVid) {
                        Wallpapers.requestThumbnail(root.modelData.path);
                    }
                }
            }

            Badge {
                badgeType: "format"
                corner: root.formatCorner
                iconName: root.formatIcon
                badgeText: root.formatText
            }

            Badge {
                badgeType: "fps"
                corner: root.fpsCorner
                iconName: "speed"
                badgeText: root.fpsText
            }

            Badge {
                badgeType: "bitrate"
                corner: root.bitrateCorner
                iconName: "equalizer"
                badgeText: root.bitrateText
            }
        }

        StyledText {
            id: label
            anchors.top: image.bottom
            anchors.topMargin: Tokens.spacing.extraSmall
            anchors.horizontalCenter: parent.horizontalCenter

            width: image.width - Tokens.padding.medium * 2
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            renderType: Text.QtRendering
            text: root.modelData.relativePath
            font: Tokens.font.label.medium
        }
    }

    Behavior on scale {
        Anim {}
    }
    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
