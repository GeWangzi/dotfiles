// The soft drop shadow behind every framed surface. Design decision
// 2026-08-20: window borders carry ONLY soft shadows -- the hard 5px
// shadow-token halo and the hard offset drop are retired everywhere.
//
// QML has no cheap blur, so "soft" is three stacked translucent rings with
// decreasing spread -- three static rectangles, no QtQuick.Effects layer,
// nothing for the GPU to keep warm. Size it to the face it shadows and put
// it behind (declare it before the face, or give it z: -1 as a child).

import QtQuick

Item {
    id: root

    property int offsetY: 6

    Repeater {
        model: [
            { pad: 12, a: 0.07 },
            { pad: 7,  a: 0.12 },
            { pad: 3,  a: 0.18 }
        ]

        Rectangle {
            required property var modelData

            x: -modelData.pad
            y: -modelData.pad + root.offsetY
            width: root.width + 2 * modelData.pad
            height: root.height + 2 * modelData.pad
            radius: Skin.radius + modelData.pad
            color: Qt.rgba(0, 0, 0, modelData.a)
        }
    }
}
