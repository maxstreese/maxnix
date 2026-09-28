// A scratchpad for learning Quickshell, and the thing `qs-dev` runs.
//
// This is not the desktop shell: DankMaterialShell is (see ../dms.nix), and it
// runs from its own systemd service. Nothing starts this file automatically —
// `programs.quickshell.systemd.enable` is false and `activeConfig` is null — so
// it only appears when you ask for it, and it cannot fight DMS for the screen.
//
// The loop, from inside the guest:
//
//     qs-dev            # then edit this file and save; it reloads itself
//
// PanelWindow comes from Quickshell._Window, which the Quickshell module
// imports by default (see its qmldir), so plain `import Quickshell` is enough.
import Quickshell
import QtQuick

ShellRoot {
    PanelWindow {
        // Bottom-left, small, and claiming no exclusive zone — so it overlaps
        // nothing and DMS's bar keeps its reserved strip at the top.
        anchors {
            left: true
            bottom: true
        }
        margins {
            left: 16
            bottom: 16
        }
        exclusiveZone: 0

        implicitWidth: 220
        implicitHeight: 64
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "#1e1e2e"
            border.width: 2
            border.color: "#89b4fa"

            Text {
                anchors.centerIn: parent
                text: "edit me and save"
                color: "#cdd6f4"
                font.pixelSize: 16
            }
        }
    }
}
