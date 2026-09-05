// The drop shadow behind every framed surface -- currently NO shadow at all
// (user call, 2026-08-25): surfaces sit flat on the field, their 2px rules
// doing all the separating. The component and its call sites stay so a
// future skin can bring a shadow back by drawing here; the hard 8px console
// slab (2026-08-24) and the 2026-08-20 soft three-ring stack both live in
// git history.

import QtQuick

Item {
    id: root

    // Kept for call-site compatibility.
    property int offsetY: 8
}
