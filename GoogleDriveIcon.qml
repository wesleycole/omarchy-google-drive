import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize * 1.12
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    // Three interlocking ribbons echo the Google Drive mark while inheriting
    // the current Omarchy foreground color.
    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      startX: root.width * 0.48
      startY: root.height * 0.04
      PathLine { x: root.width * 0.17; y: root.height * 0.60 }
      PathLine { x: root.width * 0.31; y: root.height * 0.84 }
      PathLine { x: root.width * 0.62; y: root.height * 0.28 }
      PathLine { x: root.width * 0.48; y: root.height * 0.04 }
    }

    ShapePath {
      fillColor: Qt.lighter(root.color, 1.22)
      strokeWidth: 0
      startX: root.width * 0.48
      startY: root.height * 0.04
      PathLine { x: root.width * 0.62; y: root.height * 0.28 }
      PathLine { x: root.width * 0.90; y: root.height * 0.77 }
      PathLine { x: root.width * 0.76; y: root.height * 0.99 }
      PathLine { x: root.width * 0.48; y: root.height * 0.50 }
      PathLine { x: root.width * 0.34; y: root.height * 0.27 }
      PathLine { x: root.width * 0.48; y: root.height * 0.04 }
    }

    ShapePath {
      fillColor: Qt.darker(root.color, 1.18)
      strokeWidth: 0
      startX: root.width * 0.17
      startY: root.height * 0.60
      PathLine { x: root.width * 0.31; y: root.height * 0.84 }
      PathLine { x: root.width * 0.76; y: root.height * 0.84 }
      PathLine { x: root.width * 0.90; y: root.height * 0.60 }
      PathLine { x: root.width * 0.45; y: root.height * 0.60 }
      PathLine { x: root.width * 0.17; y: root.height * 0.60 }
    }
  }
}
