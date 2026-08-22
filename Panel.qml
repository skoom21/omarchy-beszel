import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "skoom.beszel"
  ipcTarget: "skoom.beszel"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Whole payload from the helper, which always prints valid JSON.
  // NOT named `data`: that is Item's default property (the child list), and
  // shadowing it stops every child of this widget from ever rendering while
  // still reserving its slot in the bar.
  property var payload: ({
    configured: true, ok: true, up: 0, total: 0, alerts: 0,
    label: "…", badge: "", summary: "Loading…", systems: [], firing: [],
    hubUrl: "", configPath: "", error: ""
  })
  // The theme's most legible red, recomputed by the helper on every poll.
  property color alertColor: "#de6145"

  // Declared in manifest.barWidget.schema, so these are editable from the
  // plugin settings UI rather than only by editing files.
  readonly property int refreshSec: Math.max(5, Number(setting("refreshIntervalSec", 30)))
  readonly property int openRefreshSec: Math.max(1, Number(setting("openRefreshIntervalSec", 5)))

  // Resolved against this file, so the plugin works from wherever it is cloned.
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helperPath: root.pluginDir + "/bin/beszel-status"

  readonly property bool configured: root.payload.configured === true
  readonly property bool problem: !root.payload.ok
  readonly property string errorText: String(root.payload.error || "")
  readonly property var systems: root.payload.systems || []
  readonly property var firing: root.payload.firing || []
  readonly property string hubUrl: String(root.payload.hubUrl || "")
  readonly property string configPath: String(root.payload.configPath || "")

  // Panel is a bare Item: without this the bar widget collapses to 0x0 and the
  // popup has nothing to anchor to.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function refreshNow() {
    if (!statusProc.running) statusProc.running = true
  }

  function meterColor(pct) {
    if (pct >= 90) return root.alertColor
    if (pct >= 75) return Color.accent
    return root.foreground
  }

  function openDashboard() {
    if (root.bar && root.hubUrl !== "")
      root.bar.run("omarchy-launch-webapp " + root.hubUrl)
  }

  Process {
    id: statusProc
    // Invoked through python3 rather than relying on the executable bit, so a
    // checkout with lost file modes still works.
    command: ["python3", root.helperPath]
    // Secrets go through the environment, never argv, so they never appear in
    // `ps`. Empty values are ignored by the helper, which then falls back to
    // the credentials file -- that is what makes "URL here, password in the
    // file" work.
    environment: ({
      "BESZEL_URL": String(root.setting("hubUrl", "")),
      "BESZEL_EMAIL": String(root.setting("email", "")),
      "BESZEL_PASSWORD": String(root.setting("password", "")),
      "BESZEL_CONFIG": String(root.setting("credentialsFile", ""))
    })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text || ""))
          root.payload = d
          if (d.alertColor) root.alertColor = d.alertColor
        } catch (e) {
          root.payload = {
            configured: true, ok: false, up: 0, total: 0, alerts: 0,
            label: "!", badge: "Error", summary: "Could not read helper output",
            systems: [], firing: [], hubUrl: "", configPath: "",
            error: "The helper did not return valid JSON."
          }
        }
      }
    }
  }

  Timer {
    // Poll faster while the panel is open so the meters move as you watch.
    interval: (root.opened ? root.openRefreshSec : root.refreshSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNow()
  }

  onOpenedChanged: if (opened) refreshNow()

  IpcHandler {
    target: "skoom.beszel"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-fa-server. Written as an escape, never a literal glyph: a raw
    // private-use codepoint can be silently stripped in transit, which leaves
    // an invisible bar widget that still reserves its slot.
    text: "\uf233"
    // Not `active`: the shell maps its urgent role from the theme's plain
    // `red`, which in some themes is a near-grey. The helper hands us whichever
    // theme red actually contrasts with the bar background instead.
    useActiveColor: false
    foreground: root.problem ? root.alertColor
                             : (root.bar ? root.bar.barForeground : Color.foreground)
    opacity: root.configured ? 1.0 : 0.55
    tooltipText: root.opened ? "" : "Beszel — " + root.payload.summary
    onPressed: function (b) {
      if (b === Qt.RightButton) root.openDashboard()
      else if (b === Qt.MiddleButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(370))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        if (dy !== 0)
          flick.contentY = root.clamp(flick.contentY + dy * Style.space(56), 0,
                                      Math.max(0, flick.contentHeight - flick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          // ---------- Hero: mark · name · up-count ----------
          PanelHero {
            width: parent.width
            title: "Beszel"
            meta: root.configured ? root.payload.up + "/" + root.payload.total + " UP"
                                  : "NOT CONFIGURED"
            detail: root.payload.badge
            foreground: root.problem ? root.alertColor : root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: "\uf233"
                color: root.problem ? root.alertColor : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // ---------- First run: tell them exactly what to do ----------
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.configured

            PanelSectionHeader {
              text: "SETUP"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: "Point this widget at your Beszel hub. Either fill in Hub URL, "
                  + "email, and password under Setup › Plugins › Beszel servers, "
                  + "or run the setup script once to keep the password out of "
                  + "shell.json:"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: cmd.implicitHeight + Style.space(16)
              radius: Style.space(6)
              color: root.track

              Text {
                id: cmd
                anchors.centerIn: parent
                width: parent.width - Style.space(16)
                text: root.pluginDir + "/setup"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAnywhere
              }
            }

            Text {
              width: parent.width
              text: "Needs a regular Beszel user account — not a PocketBase superuser."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Configured but unhappy ----------
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.configured && root.errorText !== ""

            PanelSectionHeader {
              text: "PROBLEM"
              foreground: root.alertColor
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: root.errorText
              color: root.alertColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              visible: root.hubUrl !== ""
              text: "Hub: " + root.hubUrl
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          // ---------- One card per server ----------
          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: root.systems.length > 0

            PanelSectionHeader {
              text: "SERVERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.systems
              ServerCard {
                width: column.width
                server: modelData
              }
            }
          }

          // ---------- Firing alerts, only when there are any ----------
          PanelSeparator {
            width: parent.width
            foreground: root.foreground
            visible: root.firing.length > 0
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.firing.length > 0

            PanelSectionHeader {
              text: "FIRING ALERTS"
              foreground: root.alertColor
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.firing
              Text {
                width: column.width
                text: "\uf071  " + modelData.system + " — " + (modelData.types || []).join(", ")
                color: root.alertColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Text {
            width: parent.width
            text: root.hubUrl !== "" ? "right-click the icon for the dashboard · r refreshes"
                                     : "r refreshes"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces

  // Name + reachability badge, the three meters, then the quiet facts.
  component ServerCard: Column {
    id: card
    property var server: null
    readonly property bool down: !card.server || card.server.status !== "up"

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(nameText.implicitHeight, statusText.implicitHeight)

      Text {
        id: nameText
        text: card.server ? card.server.name : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: statusText.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: statusText
        text: card.server ? String(card.server.status).toUpperCase() : ""
        color: card.down ? root.alertColor : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: card.down
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      width: parent.width
      visible: !!card.server && String(card.server.label) !== ""
      text: card.server ? card.server.label : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Item { width: 1; height: Style.space(2) }

    MetricRow { width: parent.width; label: "CPU";  value: card.server ? card.server.cpu : 0;  down: card.down }
    MetricRow { width: parent.width; label: "MEM";  value: card.server ? card.server.mem : 0;  down: card.down }
    MetricRow { width: parent.width; label: "DISK"; value: card.server ? card.server.disk : 0; down: card.down }

    Text {
      width: parent.width
      text: {
        if (!card.server) return ""
        var bits = []
        if (card.server.uptime) bits.push("up " + card.server.uptime)
        if (card.server.cores) bits.push(card.server.cores + (card.server.cores === 1 ? " core" : " cores"))
        if (card.server.load) bits.push("load " + card.server.load)
        return bits.join("   ·   ")
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // Label, rounded meter, percentage.
  component MetricRow: Item {
    id: metricRow
    property string label: ""
    property real value: 0
    property bool down: false

    implicitHeight: Math.max(rowLabel.implicitHeight, rowValue.implicitHeight)

    Text {
      id: rowLabel
      text: metricRow.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: Style.space(38)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Item {
      id: meter
      anchors.left: rowLabel.right
      anchors.right: rowValue.left
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      implicitHeight: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      height: implicitHeight

      Rectangle {
        id: meterTrack
        anchors.fill: parent
        radius: height / 2
        color: root.track
      }

      Rectangle {
        anchors.left: meterTrack.left
        anchors.verticalCenter: meterTrack.verticalCenter
        height: meterTrack.height
        radius: meterTrack.radius
        width: meterTrack.width * root.clamp(metricRow.value / 100, 0, 1)
        // A server we cannot reach has no live numbers; show the track empty
        // rather than freezing the last reading as if it were current.
        opacity: metricRow.down ? 0.25 : 1.0
        color: root.meterColor(metricRow.value)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: rowValue
      text: metricRow.down ? "—" : Math.round(metricRow.value) + "%"
      color: metricRow.down ? root.dim : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      width: Style.space(40)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
