#!/usr/bin/env bash
# Side Notification Panel - one-file installer for KDE Plasma 6.
# The widget itself is embedded in this script, so this is the only file you need.
#
#   ./install.sh                      show a menu: install, update, uninstall, test
#   ./install.sh install              install the widget and set up its panel. If a panel with
#                                     the widget already exists, it and its settings are kept
#   ./install.sh update               update the widget only; your panel and settings are kept
#   ./install.sh uninstall            remove the panel, the widget and the package
#   ./install.sh test                 send sample notifications to try the panel out
#
# Options (for install):
#   --edge  left|right|top|bottom     screen edge for the panel          (default: right)
#   --mode  handle|sidebar            handle = slim always-visible strip that opens a drawer
#                                     sidebar = wide auto-hiding panel   (default: handle)
#   --screen N                        screen number, starting at 0       (default: 0)
#   --size PX                         panel thickness in pixels          (handle 20, sidebar 360)
#   --length PX                       handle length in pixels            (default: 160)
#   --recreate                        build the panel again from scratch, even if one exists
#                                     (this resets its settings)
#   --no-restart                      do not restart the Plasma shell after updating

set -euo pipefail

ID="com.user.sidenotifications"
TMP=""
PKG=""
cleanup() { [[ -n $TMP ]] && rm -rf "$TMP"; return 0; }
trap cleanup EXIT

CMD=""
EDGE=""
MODE=""
SCREEN=0
SIZE=""
LENGTH=160
RESTART=1
UPGRADED=0
RECREATE=0
OPTS_GIVEN=0
KEEP=0

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^[^#]/{/^#/p}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --edge)   EDGE="${2:?--edge needs a value}"; OPTS_GIVEN=1; shift 2 ;;
        --mode)   MODE="${2:?--mode needs a value}"; OPTS_GIVEN=1; shift 2 ;;
        --screen) SCREEN="${2:?--screen needs a value}"; OPTS_GIVEN=1; shift 2 ;;
        --size)   SIZE="${2:?--size needs a value}"; OPTS_GIVEN=1; shift 2 ;;
        --length) LENGTH="${2:?--length needs a value}"; OPTS_GIVEN=1; shift 2 ;;
        --recreate) RECREATE=1; shift ;;
        --no-restart) RESTART=0; shift ;;
        -h|--help) usage; exit 0 ;;
        install|update|uninstall|test) CMD="$1"; shift ;;
        -*) usage >&2; die "Unknown option: $1" ;;
        *) usage >&2; die "Unknown command: $1" ;;
    esac
done

# True if the widget is already placed somewhere (in a panel or on the desktop).
# Plasma records every placed widget as "plugin=<id>" in its applets config file.
widget_in_use() {
    grep -qs "^plugin=$ID\$" "${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
}

ask() {   # ask "question" default  ->  answer in $REPLY
    local reply
    read -r -p "$1 [$2]: " reply || reply=""
    REPLY="${reply:-$2}"
}

menu() {
    local choice
    echo
    printf '\033[1mSide Notification Panel\033[0m\n\n'
    echo "  1) install     install the widget and set up its panel (keeps an existing one)"
    echo "  2) update      update the widget only, keep your panel as it is"
    echo "  3) uninstall   remove the panel, the widget and the package"
    echo "  4) test        send sample notifications to try the panel out"
    echo "  5) quit"
    echo
    while true; do
        read -r -p "Choose an option [1-5]: " choice || exit 0
        case "${choice,,}" in
            1|install)        CMD=install;   return ;;
            2|update)         CMD=update;    return ;;
            3|uninstall)      CMD=uninstall; return ;;
            4|test)           CMD=test;      return ;;
            5|q|quit|exit)    exit 0 ;;
            *) echo "Please enter a number from 1 to 5." ;;
        esac
    done
}

INTERACTIVE=0
[[ -t 0 && -t 1 ]] && INTERACTIVE=1

if [[ -z $CMD ]]; then
    if (( INTERACTIVE )); then menu; else CMD=install; fi
fi

# An existing panel (and the settings stored with it) is kept unless --recreate is given.
if [[ $CMD == install ]] && (( ! RECREATE )) && widget_in_use; then KEEP=1; fi

# For an interactive install of a new panel, ask for whatever was not given as an option.
if [[ $CMD == install ]] && (( INTERACTIVE )) && (( ! KEEP )); then
    if [[ -z $MODE ]]; then
        ask "Mode: handle (slim strip that opens a drawer) or sidebar (wide auto-hiding panel)" handle
        MODE="$REPLY"
    fi
    if [[ -z $EDGE ]]; then
        ask "Screen edge: left, right, top or bottom" right
        EDGE="$REPLY"
    fi
fi
EDGE="${EDGE:-right}"
MODE="${MODE:-handle}"

case "$CMD" in install|update|uninstall|test) ;; *) usage >&2; die "Unknown command: $CMD" ;; esac
case "$EDGE" in left|right|top|bottom) ;; *) die "--edge must be left, right, top or bottom" ;; esac
case "$MODE" in handle|sidebar) ;; *) die "--mode must be handle or sidebar" ;; esac
[[ $SCREEN =~ ^[0-9]+$ && $LENGTH =~ ^[0-9]+$ ]] || die "--screen and --length must be numbers"
if [[ -z $SIZE ]]; then [[ $MODE == handle ]] && SIZE=20 || SIZE=360; fi
[[ $SIZE =~ ^[0-9]+$ ]] || die "--size must be a number"

command -v kpackagetool6 >/dev/null || die "kpackagetool6 not found. This installer is for KDE Plasma 6."

QDBUS=""
for c in qdbus6 qdbus-qt6 qdbus; do
    if command -v "$c" >/dev/null; then QDBUS="$c"; break; fi
done

shell_running() { [[ -n $QDBUS ]] && "$QDBUS" org.kde.plasmashell >/dev/null 2>&1; }
run_script() { "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1" >/dev/null; }
run_script_retry() {
    local i
    for i in 1 2 3 4 5; do
        if run_script "$1"; then return 0; fi
        sleep 1.5
    done
    die "Could not talk to the Plasma shell (evaluateScript failed)."
}
wait_shell() {
    local i
    for i in $(seq 1 60); do
        if shell_running; then sleep 2; return 0; fi
        sleep 0.5
    done
    die "The Plasma shell did not come back after the restart."
}

is_installed() { kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q "$ID"; }

# Writes the embedded widget package to a temporary folder and sets PKG.
extract_package() {
    TMP="$(mktemp -d)"
    PKG="$TMP/$ID"
    mkdir -p "$PKG"
    cat > "$PKG/metadata.json" <<'__SNP_EOF__'
{
    "KPlugin": {
        "Id": "com.user.sidenotifications",
        "Name": "Side Notification Panel",
        "Description": "Notification history sidebar for a vertical Plasma panel",
        "Icon": "notification-active",
        "Category": "Utilities",
        "License": "GPL-2.0+",
        "Version": "2.1.3",
        "Authors": [
            {
                "Name": "You"
            }
        ]
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0"
}
__SNP_EOF__
    mkdir -p "$PKG/contents/config"
    cat > "$PKG/contents/config/main.xml" <<'__SNP_EOF__'
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0 http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
    <kcfgfile name=""/>
    <group name="General">
        <!-- 0 = by date, 1 = by app, 2 = none -->
        <entry name="groupMode" type="Int">
            <default>1</default>
        </entry>
        <entry name="bodyLines" type="Int">
            <default>4</default>
        </entry>
        <entry name="relativeTimes" type="Bool">
            <default>true</default>
        </entry>
        <entry name="markReadOnHover" type="Bool">
            <default>true</default>
        </entry>
        <!-- keep a history of notifications that survives Clear All and restarts -->
        <entry name="historyEnabled" type="Bool">
            <default>true</default>
        </entry>
        <!-- how many days back the history is kept -->
        <entry name="historyDays" type="Int">
            <default>30</default>
        </entry>
        <!-- internal: the stored history (JSON) -->
        <entry name="historyData" type="String">
            <default></default>
        </entry>
        <!-- internal: the release whose Readme was last shown automatically -->
        <entry name="seenVersion" type="String">
            <default></default>
        </entry>
        <!-- show Plasma's own pop-ups for new notifications -->
        <entry name="popupsEnabled" type="Bool">
            <default>true</default>
        </entry>
        <!-- internal: pop-ups are currently held back by this widget -->
        <entry name="inhibitOwned" type="Bool">
            <default>false</default>
        </entry>
        <!-- Do Not Disturb end time in ms since epoch; 0 = off -->
        <entry name="dndUntil" type="Double">
            <default>0</default>
        </entry>
    </group>
    <group name="Opening">
        <!-- an icon in the system tray that opens and closes the panel too -->
        <entry name="trayIcon" type="Bool">
            <default>true</default>
        </entry>
        <!-- 0 = drawer attached to the screen edge with the handle on top of it,
             1 = Plasma popup next to the handle -->
        <entry name="drawerStyle" type="Int">
            <default>0</default>
        </entry>
        <!-- 0 = click the handle, 1 = hover the handle (after a delay) or click -->
        <entry name="revealMode" type="Int">
            <default>0</default>
        </entry>
        <!-- milliseconds the pointer must rest on the handle before the drawer opens -->
        <entry name="hoverDelay" type="Int">
            <default>400</default>
        </entry>
        <!-- close a hover-opened drawer when the pointer leaves it -->
        <entry name="closeOnLeave" type="Bool">
            <default>true</default>
        </entry>
        <!-- milliseconds the pointer must be away before it closes -->
        <entry name="closeDelay" type="Int">
            <default>700</default>
        </entry>
        <!-- drawer width in grid units (about 18 px each) -->
        <entry name="drawerWidth" type="Int">
            <default>22</default>
        </entry>
        <!-- drawer height as a percentage of the available screen height -->
        <entry name="drawerHeight" type="Int">
            <default>100</default>
        </entry>
    </group>
    <group name="Handle">
        <!-- 0 = number (bell when none), 1 = bell and number, 2 = bell only -->
        <entry name="handleFace" type="Int">
            <default>0</default>
        </entry>
        <!-- 0 = new (unread) notifications, 1 = all notifications -->
        <entry name="handleCountMode" type="Int">
            <default>0</default>
        </entry>
        <entry name="handleCustomColors" type="Bool">
            <default>false</default>
        </entry>
        <entry name="handleColor" type="Color">
            <default>#5c616c</default>
        </entry>
        <entry name="handleUnreadColor" type="Color">
            <default>#3daee9</default>
        </entry>
        <!-- icons of the apps that have unread notifications -->
        <entry name="handleAppIcons" type="Bool">
            <default>true</default>
        </entry>
        <entry name="handleMaxIcons" type="Int">
            <default>5</default>
        </entry>
        <!-- 0 = don't blink, 1 = blink a few times, 2 = blink until the panel is opened -->
        <entry name="handleBlink" type="Int">
            <default>1</default>
        </entry>
    </group>
</kcfg>

__SNP_EOF__
    mkdir -p "$PKG/contents/config"
    cat > "$PKG/contents/config/config.qml" <<'__SNP_EOF__'
import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Readme")
        icon: "help-about"
        source: "configReadme.qml"
    }
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Opening")
        icon: "window-pin"
        source: "configOpening.qml"
    }
    ConfigCategory {
        name: i18n("Handle")
        icon: "preferences-desktop-color"
        source: "configHandle.qml"
    }
}
__SNP_EOF__
    mkdir -p "$PKG/contents/ui"
    cat > "$PKG/contents/ui/main.qml" <<'__SNP_EOF__'
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as NotificationManager

PlasmoidItem {
    id: root

    readonly property bool onSideEdge: Plasmoid.location === PlasmaCore.Types.LeftEdge
                                       || Plasmoid.location === PlasmaCore.Types.RightEdge
    // Inline list on a wide side panel; bell icon + popup everywhere else.
    readonly property bool wideSidebar: onSideEdge && width >= Kirigami.Units.gridUnit * 14

    // ---- state ----------------------------------------------------------
    property double nowMs: Date.now()
    property double lastSeen: Date.now()      // notifications newer than this are "unread"
    property int unreadCount: 0
    property int totalCount: 0
    property string filterText: ""
    property var collapsed: ({})              // section key -> true when collapsed
    property var sectionInfo: ({})            // section key -> {name, icon, count}
    property bool dndPicking: false
    property bool compactHover: false         // pointer over the handle
    property bool popupHover: false           // pointer over the opened drawer
    property bool replyTyping: false          // a reply field has keyboard focus
    property bool searchTyping: false         // the search field has keyboard focus
    property bool openedByHover: false        // drawer was opened by hovering the handle
    property bool drawerOpen: false           // the edge drawer (own window) is shown
    property double closedAt: 0               // when the edge drawer last closed
    // true: the drawer is drawn in its own window, attached to the screen edge.
    // false (or inside a wide sidebar panel): the normal Plasma popup / inline list.
    readonly property bool edgeDrawer: !wideSidebar && Plasmoid.configuration.drawerStyle === 0
    readonly property bool isOpen: edgeDrawer ? drawerOpen : expanded
    signal newNotification()                  // an unread notification has arrived
    property int prevUnread: 0
    // Do Not Disturb is "until <time>" (Plasma's own model); 0 = off. Kept in our config so
    // it survives restarts, and pushed to Plasma's notification settings by applyInhibition().
    property double dndNow: Date.now()
    readonly property bool dndActive: Plasmoid.configuration.dndUntil > dndNow
    readonly property double foreverMs: 4102444800000     // 1 Jan 2100
    property string historyFilter: ""                   // search text of the history view
    property bool showHistory: false                      // the history view replaces the list
    property var archive: []                              // kept history, [{k, s, b, a, i, t}]
    property var archiveMap: ({})
    property bool archiveDirty: false
    property int historyCount: 0
    property var unreadApps: []                           // [{icon, name}] of apps with unread notifications

    preferredRepresentation: wideSidebar ? fullRepresentation : compactRepresentation
    Layout.fillHeight: true
    Layout.fillWidth: true

    Plasmoid.icon: dndActive ? "notification-disabled" : "notification-active"
    Plasmoid.status: unreadCount > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: i18n("Notifications")
    toolTipSubText: dndActive ? i18n("Do Not Disturb is on")
                              : (unreadCount > 0 ? i18np("%1 new notification", "%1 new notifications", unreadCount)
                                                 : (totalCount > 0 ? i18np("%1 notification", "%1 notifications", totalCount)
                                                                   : i18n("No notifications")))

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Do Not Disturb")
            icon.name: "notification-disabled"
            checkable: true
            checked: root.dndActive
            onTriggered: root.setDnd(!root.dndActive, 0)
        },
        PlasmaCore.Action {
            text: i18n("Clear All Notifications")
            icon.name: "edit-clear-history"
            enabled: root.totalCount > 0
            onTriggered: root.clearEverything()
        }
    ]

    // ---- data -----------------------------------------------------------
    NotificationManager.Notifications {
        id: historyModel
        showExpired: true
        showDismissed: true
        showJobs: true
        sortMode: NotificationManager.Notifications.SortByDate
        sortOrder: Qt.DescendingOrder
        groupMode: NotificationManager.Notifications.GroupDisabled
        limit: 200
    }

    NotificationManager.Settings {
        id: nmSettings
    }

    // Mirrors the history model into plain objects so we can read roles by name
    // and build a diffed, section-able list model out of them.
    Instantiator {
        id: mirror
        model: historyModel
        onObjectAdded: syncTimer.restart()
        onObjectRemoved: syncTimer.restart()
        delegate: QtObject {
            readonly property string nid: String(model.notificationId ?? "")
            readonly property string summary: model.summary ?? ""
            readonly property string body: model.body ?? ""
            readonly property string appName: model.applicationName ?? ""
            readonly property string appIcon: model.applicationIconName ?? ""
            readonly property string iconName: model.iconName ?? ""
            readonly property var image: model.image
            readonly property var created: model.created
            readonly property var updated: model.updated
            readonly property bool closable: model.closable ?? true
            readonly property bool hasDefault: model.hasDefaultAction ?? false
            readonly property var actionNames: model.actionNames ?? []
            readonly property var actionLabels: model.actionLabels ?? []
            readonly property var urls: model.urls ?? []
            readonly property bool hasReply: model.hasReplyAction ?? false
            readonly property string replyPlaceholder: model.replyPlaceholderText ?? ""
            readonly property int urgency: model.urgency ?? 1
            readonly property int type: model.type ?? 1
            readonly property int jobState: model.jobState ?? 0
            readonly property int percentage: model.percentage ?? 0
        }
    }

    ListModel {
        id: viewModel
        dynamicRoles: true
    }

    Connections {
        target: historyModel
        function onDataChanged() { syncTimer.restart() }
        function onRowsMoved() { syncTimer.restart() }
        function onModelReset() { syncTimer.restart() }
        function onLayoutChanged() { syncTimer.restart() }
    }

    Connections {
        target: Plasmoid.configuration
        function onGroupModeChanged() { syncTimer.restart() }
        function onPopupsEnabledChanged() { root.applyInhibition() }
    }

    onFilterTextChanged: syncTimer.restart()
    onLastSeenChanged: syncTimer.restart()

    Timer {
        id: syncTimer
        interval: 40
        onTriggered: root.sync()
    }

    // Keeps relative times fresh and rolls "Today/Yesterday" over at midnight.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            root.nowMs = Date.now()
            syncTimer.restart()
        }
    }

    // ---- history: a copy of every notification, kept for N days -----------------
    function loadArchive() {
        let list = []
        try {
            list = JSON.parse(Plasmoid.configuration.historyData || "[]")
        } catch (e) {
            list = []
        }
        archive = Array.isArray(list) ? list : []
        const m = {}
        for (const e of archive) {
            m[e.k] = e
        }
        archiveMap = m
        pruneArchive()
    }

    function pruneArchive() {
        const cutoff = Date.now() - Math.max(1, Plasmoid.configuration.historyDays) * 86400000
        let kept = archive.filter(e => e.t >= cutoff)
        if (kept.length > 1500) {
            kept.sort((x, y) => y.t - x.t)
            kept = kept.slice(0, 1500)
        }
        if (kept.length !== archive.length) {
            archive = kept
            const m = {}
            for (const e of kept) {
                m[e.k] = e
            }
            archiveMap = m
            archiveDirty = true
        }
    }

    function archiveAdd(o, ms) {
        if (!Plasmoid.configuration.historyEnabled || o.type === 2 || (o.summary === "" && o.body === "")) {
            return
        }
        const c = (o.created && o.created.getTime) ? o.created.getTime() : ms
        const key = c + "|" + o.nid
        const e = archiveMap[key]
        if (!e) {
            const n = { k: key, s: o.summary, b: o.body, a: o.appName || i18n("System"), i: o.appIcon || o.iconName, t: ms }
            archive.push(n)
            archiveMap[key] = n
            archiveDirty = true
        } else if (e.s !== o.summary || e.b !== o.body) {
            e.s = o.summary
            e.b = o.body
            e.t = ms
            archiveDirty = true
        }
        if (archiveDirty) {
            archiveSaveTimer.restart()
        }
    }

    Timer {
        id: archiveSaveTimer
        interval: 5000
        onTriggered: root.saveArchive()
    }

    function saveArchive() {
        pruneArchive()
        Plasmoid.configuration.historyData = JSON.stringify(archive)
        archiveDirty = false
    }

    function clearHistory() {
        archive = []
        archiveMap = ({})
        saveArchive()
        refreshHistory()
    }

    function dayLabel(ms) {
        if (ms >= dayStart(0)) return i18n("Today")
        if (ms >= dayStart(-1)) return i18n("Yesterday")
        return Qt.formatDate(new Date(ms), Qt.locale().dateFormat(Locale.LongFormat))
    }

    function refreshHistory() {
        historyView.clear()
        historyCount = archive.length
        if (!showHistory) {
            return
        }
        const q = historyFilter.trim().toLowerCase()
        const list = archive.slice().sort((x, y) => y.t - x.t)
        for (const e of list) {
            if (q && (e.s + " " + e.b + " " + e.a + " " + dayLabel(e.t)).toLowerCase().indexOf(q) === -1) {
                continue
            }
            historyView.append({ summary: e.s, body: e.b, appName: e.a, appIcon: e.i, ms: e.t, day: dayLabel(e.t) })
        }
    }

    onShowHistoryChanged: {
        historyFilter = ""
        refreshHistory()
    }
    onHistoryFilterChanged: refreshHistory()

    ListModel {
        id: historyView
    }

    Connections {
        target: Plasmoid.configuration
        function onHistoryDaysChanged() { root.pruneArchive(); root.saveArchive(); root.refreshHistory() }
    }

    function dayStart(offsetDays) {
        const n = new Date()
        return new Date(n.getFullYear(), n.getMonth(), n.getDate() + offsetDays).getTime()
    }

    function bucketOf(ms) {
        if (ms >= dayStart(0)) return i18n("Today")
        if (ms >= dayStart(-1)) return i18n("Yesterday")
        if (ms >= dayStart(-6)) return i18n("Earlier this week")
        return i18n("Older")
    }

    function timeOf(o) {
        const d = o.updated || o.created
        return (d && d.getTime) ? d.getTime() : Date.now()
    }

    function formatTime(ms, nowMs) {
        const d = new Date(ms)
        const clock = Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat))
        if (Plasmoid.configuration.relativeTimes) {
            const mins = Math.floor((nowMs - ms) / 60000)
            if (mins < 1) return i18n("Just now")
            if (mins < 60) return i18n("%1 min ago", mins)
        }
        if (ms >= dayStart(0)) return clock
        if (ms >= dayStart(-1)) return i18n("Yesterday %1", clock)
        return Qt.formatDate(d, Qt.locale().dateFormat(Locale.ShortFormat)) + " " + clock
    }

    function sync() {
        const mode = Plasmoid.configuration.groupMode   // 0 = date, 1 = app, 2 = none
        const q = filterText.trim().toLowerCase()
        let rows = []
        let unread = 0
        const apps = []
        const seenApps = {}

        for (let i = 0; i < mirror.count; ++i) {
            const o = mirror.objectAt(i)
            if (!o) {
                continue
            }
            const ms = timeOf(o)
            const isUnread = ms > lastSeen
            archiveAdd(o, ms)
            const appName = o.appName || i18n("System")
            if (isUnread) {
                unread++
                if (!seenApps[appName]) {
                    seenApps[appName] = true
                    apps.push({ icon: o.appIcon || o.iconName, name: appName })
                }
            }
            if (q && (o.summary + " " + o.body + " " + appName).toLowerCase().indexOf(q) === -1) {
                continue
            }
            const urls = []
            for (const u of (o.urls || [])) {
                urls.push(u.toString())
            }
            const row = {
                key: o.nid !== "" ? o.nid : (ms + "|" + o.summary + "|" + appName),
                summary: o.summary,
                body: o.body,
                appName: appName,
                appIcon: o.appIcon || o.iconName,
                hasImage: !!o.image,
                ms: ms,
                unread: isUnread,
                closable: o.closable,
                hasDefault: o.hasDefault,
                // ListModel turns arrays into nested models, so keep them as JSON text
                actionNames: JSON.stringify(Array.from(o.actionNames || [])),
                actionLabels: JSON.stringify(Array.from(o.actionLabels || [])),
                urls: JSON.stringify(urls),
                hasReply: o.hasReply,
                replyPlaceholder: o.replyPlaceholder,
                urgency: o.urgency,
                isJob: o.type === 2,
                jobRunning: o.jobState === 1,
                percentage: o.percentage,
                bucket: bucketOf(ms),
                appKey: appName
            }
            row.sig = JSON.stringify(row)
            row.image = o.image || ""
            row.srcRow = i
            rows.push(row)
        }

        if (mode === 1) {   // keep each app's notifications together, newest app first
            const order = []
            const groups = {}
            for (const r of rows) {
                if (!groups[r.appKey]) {
                    groups[r.appKey] = []
                    order.push(r.appKey)
                }
                groups[r.appKey].push(r)
            }
            rows = []
            for (const k of order) {
                rows = rows.concat(groups[k])
            }
        }

        const info = {}
        for (const r of rows) {
            const k = mode === 1 ? r.appKey : r.bucket
            if (!info[k]) {
                info[k] = { name: k, icon: r.appIcon, count: 0 }
            }
            info[k].count++
        }

        // Diff into viewModel: remove, then insert/move/update in order.
        const keep = {}
        for (const r of rows) {
            keep[r.key] = true
        }
        for (let i = viewModel.count - 1; i >= 0; --i) {
            if (!keep[viewModel.get(i).key]) {
                viewModel.remove(i)
            }
        }
        for (let p = 0; p < rows.length; ++p) {
            const r = rows[p]
            let found = -1
            if (p < viewModel.count && viewModel.get(p).key === r.key) {
                found = p
            } else {
                for (let j = p + 1; j < viewModel.count; ++j) {
                    if (viewModel.get(j).key === r.key) {
                        found = j
                        break
                    }
                }
            }
            if (found === -1) {
                viewModel.insert(p, r)
                continue
            }
            if (found !== p) {
                viewModel.move(found, p, 1)
            }
            const cur = viewModel.get(p)
            if (cur.sig !== r.sig) {
                viewModel.set(p, r)
            } else if (cur.srcRow !== r.srcRow) {
                viewModel.setProperty(p, "srcRow", r.srcRow)
            }
        }

        if (unread > prevUnread && !dndActive && !isOpen) {
            newNotification()
        }
        prevUnread = unread
        root.sectionInfo = info
        root.unreadCount = unread
        root.unreadApps = apps
        if (showHistory) {
            refreshHistory()
        } else {
            historyCount = archive.length
        }
        root.totalCount = mirror.count
    }

    // ---- actions --------------------------------------------------------
    function srcIndex(row) {
        return historyModel.index(row, 0)
    }

    // Closes view rows [from, to) — highest source row first so indexes stay valid.
    function clearRows(from, to, key, mode) {
        const srcRows = []
        for (let i = from; i < to; ++i) {
            const r = viewModel.get(i)
            if (key === undefined || (mode === 1 ? r.appKey : r.bucket) === key) {
                srcRows.push(r.srcRow)
            }
        }
        srcRows.sort((a, b) => b - a)
        for (const s of srcRows) {
            historyModel.close(srcIndex(s))
        }
    }

    // Closes every notification in the history, whatever the search box currently shows.
    function clearEverything() {
        for (let i = mirror.count - 1; i >= 0; --i) {
            historyModel.close(srcIndex(i))
        }
    }

    function toggleCollapsed(key) {
        const c = Object.assign({}, collapsed)
        c[key] = !c[key]
        collapsed = c
    }

    // 0 = off, a time = until then, root.foreverMs = until turned off
    function setDnd(on, untilMs) {
        dndNow = Date.now()
        Plasmoid.configuration.dndUntil = on ? (untilMs > 0 ? untilMs : foreverMs) : 0
        dndPicking = false
        scheduleDnd()
    }

    // Plasma holds back pop-ups (and sounds) while its "inhibited until" time is in the future.
    // We set it for Do Not Disturb, and also when the pop-ups option is switched off.
    function applyInhibition() {
        dndNow = Date.now()
        const cfg = Plasmoid.configuration
        const want = dndActive || !cfg.popupsEnabled
        if (want) {
            nmSettings.notificationsInhibitedUntil = new Date(dndActive ? cfg.dndUntil : foreverMs)
            nmSettings.save()
            cfg.inhibitOwned = true
        } else if (cfg.inhibitOwned) {
            // only undo what we set ourselves, never a Do Not Disturb the user turned on elsewhere
            nmSettings.notificationsInhibitedUntil = undefined
            nmSettings.save()
            cfg.inhibitOwned = false
        }
    }

    function scheduleDnd() {
        const until = Plasmoid.configuration.dndUntil
        dndNow = Date.now()
        if (until > dndNow && until < foreverMs) {
            dndTimer.interval = Math.min(until - dndNow + 500, 2147483647)
            dndTimer.restart()
        } else {
            dndTimer.stop()
        }
        if (until > 0 && until <= dndNow) {
            Plasmoid.configuration.dndUntil = 0
        }
        applyInhibition()
    }

    Timer {
        id: dndTimer
        onTriggered: root.scheduleDnd()
    }

    // After an install or update, open the settings once (on the Readme, its first page)
    // so the list of what is new is seen. Keep in step with metadata.json.
    readonly property string releaseVersion: "2.1.3"
    Timer {
        id: readmeTimer
        interval: 4000
        onTriggered: {
            Plasmoid.configuration.seenVersion = root.releaseVersion
            Plasmoid.internalAction("configure").trigger()
        }
    }

    Component.onCompleted: {
        loadArchive()
        if (Plasmoid.configuration.seenVersion !== releaseVersion) {
            readmeTimer.start()
        }
        scheduleDnd()
        syncTimer.restart()
    }

    // ---- opening and closing ---------------------------------------------
    readonly property bool pointerInside: compactHover || popupHover
    onPointerInsideChanged: pointerInside ? leaveTimer.stop() : leaveTimer.restart()

    function setOpen(open, byHover) {
        if (edgeDrawer) {
            drawerOpen = open
        } else {
            expanded = open
        }
        openedByHover = open && !!byHover
    }

    onExpandedChanged: {
        if (edgeDrawer && expanded) {
            // Opened by something other than the handle (a shortcut, say):
            // show the edge drawer instead of Plasma's popup.
            expanded = false
            drawerOpen = true
        }
        if (!expanded && !drawerOpen) {
            openedByHover = false
            leaveTimer.stop()
        }
    }

    onDrawerOpenChanged: {
        if (drawerOpen) {
            placeDrawer()
        } else {
            showHistory = false
            openedByHover = false
            replyTyping = false
            searchTyping = false
            leaveTimer.stop()
        }
    }

    // Opens after the pointer has rested on the handle for hoverDelay.
    Timer {
        id: openTimer
        interval: Plasmoid.configuration.hoverDelay
        onTriggered: {
            if (!root.isOpen) {
                root.setOpen(true, true)
            }
        }
    }

    // Closes a hover-opened drawer once the pointer has been away for closeDelay.
    Timer {
        id: leaveTimer
        interval: Plasmoid.configuration.closeDelay
        onTriggered: {
            if (root.isOpen && root.openedByHover && Plasmoid.configuration.closeOnLeave
                    && !root.pointerInside && !root.replyTyping && !root.searchTyping) {
                root.setOpen(false, false)
            }
        }
    }

    // ---- how the handle looks -------------------------------------------------
    // number shown on the handle: unread only, or everything in the history
    readonly property int handleCount: Plasmoid.configuration.handleCountMode === 0 ? unreadCount : totalCount
    // icon names of the apps with unread notifications, newest first (empty when switched off)
    readonly property var handleIcons: {
        const out = []
        if (Plasmoid.configuration.handleAppIcons) {
            for (const a of unreadApps) {
                out.push(a.icon)
            }
        }
        return out
    }
    readonly property bool handleHasNew: unreadCount > 0 && !dndActive

    function handleFill(open, hovered) {
        const cfg = Plasmoid.configuration
        if (cfg.handleCustomColors) {
            const base = handleHasNew ? cfg.handleUnreadColor : cfg.handleColor
            return hovered ? Qt.lighter(base, 1.15) : base
        }
        if (handleHasNew) {
            return Qt.alpha(Kirigami.Theme.highlightColor, hovered ? 1 : 0.9)
        }
        if (open) {
            return Qt.alpha(Kirigami.Theme.highlightColor, 0.35)
        }
        return hovered ? Qt.alpha(Kirigami.Theme.highlightColor, 0.25)
                       : Qt.alpha(Kirigami.Theme.textColor, 0.12)
    }

    // Text and bell colour that stays readable on the chosen background.
    function handleText(fill) {
        if (Plasmoid.configuration.handleCustomColors) {
            const lum = 0.299 * fill.r + 0.587 * fill.g + 0.114 * fill.b
            return lum > 0.6 ? "#232629" : "#fcfcfc"
        }
        return handleHasNew ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
    }

    // ---- handle: the always-visible strip on the screen edge ------------
    compactRepresentation: MouseArea {
        id: handle
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        property real blinkAmount: 0
        // While the edge drawer is open it draws its own copy of the handle.
        opacity: (root.edgeDrawer && root.drawerOpen) ? 0 : 1
        onClicked: {
            openTimer.stop()
            // A click that only closed the drawer by taking its focus away must not reopen it.
            if (!root.isOpen && Date.now() - root.closedAt < 250) {
                return
            }
            root.setOpen(!root.isOpen, false)
        }
        onContainsMouseChanged: {
            root.compactHover = containsMouse
            if (containsMouse) {
                // revealMode: 0 = click only, 1 = hover (after a delay) or click
                if (Plasmoid.configuration.revealMode >= 1 && !root.isOpen) {
                    openTimer.restart()
                }
            } else {
                openTimer.stop()
            }
        }

        HandleFace {
            id: face
            anchors.fill: parent
            fill: root.handleFill(root.isOpen, handle.containsMouse)
            textColor: root.handleText(face.fill)
            iconName: root.dndActive ? "notification-disabled" : "notification-active"
            count: root.handleCount
            mode: Plasmoid.configuration.handleFace
            horizontal: root.horizontalEdge
            blinkAmount: handle.blinkAmount
            appIcons: root.handleIcons
            maxIcons: Plasmoid.configuration.handleMaxIcons
        }

        // Blink a few times when a new notification arrives ...
        SequentialAnimation {
            id: blinkFew
            loops: 6
            onStopped: handle.blinkAmount = 0
            NumberAnimation { target: handle; property: "blinkAmount"; to: 1; duration: 350; easing.type: Easing.InOutSine }
            NumberAnimation { target: handle; property: "blinkAmount"; to: 0; duration: 350; easing.type: Easing.InOutSine }
        }

        // ... or keep blinking until the panel is opened
        SequentialAnimation {
            id: blinkUntilOpened
            loops: Animation.Infinite
            running: Plasmoid.configuration.handleBlink === 2 && root.handleHasNew && !root.isOpen
            onStopped: handle.blinkAmount = 0
            NumberAnimation { target: handle; property: "blinkAmount"; to: 1; duration: 450; easing.type: Easing.InOutSine }
            NumberAnimation { target: handle; property: "blinkAmount"; to: 0; duration: 450; easing.type: Easing.InOutSine }
        }

        Connections {
            target: root
            function onNewNotification() {
                if (Plasmoid.configuration.handleBlink === 1) {
                    blinkFew.restart()
                }
            }
            function onIsOpenChanged() {
                if (root.isOpen) {
                    blinkFew.stop()
                }
            }
        }
    }

    // ---- full panel (shown inline, in Plasma's popup, or in the edge drawer) ----
    fullRepresentation: panelComponent

    Component {
        id: panelComponent

        ColumnLayout {
            id: panel

            // Size of the opened drawer. In popup mode the size is pinned (minimum =
            // maximum = preferred), because Plasma can otherwise keep a size it has
            // stored for the popup and ignore a changed preferred size. Inside a wide
            // sidebar panel the item stays flexible.
            readonly property bool fixedSize: !root.wideSidebar
            readonly property real screenHeight: Screen.desktopAvailableHeight > 0 ? Screen.desktopAvailableHeight
                                                 : (Screen.height > 0 ? Screen.height : 900)
            readonly property real wantedWidth: Kirigami.Units.gridUnit * Plasmoid.configuration.drawerWidth
            readonly property real wantedHeight: Math.round(Math.min(screenHeight * Plasmoid.configuration.drawerHeight / 100,
                                                                     screenHeight * 0.95))
            Layout.minimumWidth: fixedSize ? wantedWidth : Kirigami.Units.gridUnit * 14
            Layout.minimumHeight: fixedSize ? wantedHeight : Kirigami.Units.gridUnit * 20
            Layout.preferredWidth: wantedWidth
            Layout.preferredHeight: wantedHeight
            Layout.maximumWidth: fixedSize ? wantedWidth : Infinity
            Layout.maximumHeight: fixedSize ? wantedHeight : Infinity
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            property bool confirmClear: false
            property bool confirmHistoryClear: false

            Binding { target: root; property: "popupHover"; value: panelHover.hovered; when: !root.edgeDrawer }
            Binding { target: root; property: "searchTyping"; value: searchField.activeFocus || historySearch.activeFocus }

            // Mark everything as seen once the panel has been looked at for a moment.
            HoverHandler { id: panelHover }
            Timer {
                interval: 1500
                running: Plasmoid.configuration.markReadOnHover
                         && root.unreadCount > 0
                         && (panelHover.hovered || root.isOpen)
                onTriggered: root.lastSeen = Date.now()
            }
            Timer {
                id: confirmTimer
                interval: 3000
                onTriggered: panel.confirmClear = false
            }
            Timer {
                id: pickTimer
                interval: 8000
                running: root.dndPicking
                onTriggered: root.dndPicking = false
            }

            Shortcut {
                sequences: [StandardKey.Find]
                enabled: panelHover.hovered || root.isOpen
                onActivated: root.showHistory ? historySearch.forceActiveFocus() : searchButton.checked = true
            }

            // Header
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    level: 3
                    text: root.showHistory ? i18n("History") : i18n("Notifications")
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    visible: root.unreadCount > 0 && !root.showHistory
                    text: i18n("%1 new", root.unreadCount)
                    color: Kirigami.Theme.highlightColor
                    font: Kirigami.Theme.smallFont
                    Layout.alignment: Qt.AlignBaseline
                }
                Item { Layout.fillWidth: true }

                PlasmaComponents3.ToolButton {
                    icon.name: "view-history"
                    checkable: true
                    checked: root.showHistory
                    visible: Plasmoid.configuration.historyEnabled
                    text: root.showHistory ? i18n("Back to notifications") : i18n("History")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    onClicked: root.showHistory = !root.showHistory
                }
                PlasmaComponents3.ToolButton {
                    id: searchButton
                    visible: !root.showHistory
                    icon.name: "edit-find"
                    checkable: true
                    text: i18n("Search")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                }
                PlasmaComponents3.ToolButton {
                    icon.name: root.dndActive ? "notification-disabled" : "notification-inactive"
                    checked: root.dndActive || root.dndPicking
                    checkable: false
                    text: i18n("Do Not Disturb")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    onClicked: root.dndActive ? root.setDnd(false, 0) : root.dndPicking = !root.dndPicking
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "edit-clear-history"
                    text: panel.confirmClear ? i18n("Clear all?") : i18n("Clear All")
                    display: panel.confirmClear ? PlasmaComponents3.AbstractButton.TextBesideIcon
                                                : PlasmaComponents3.AbstractButton.IconOnly
                    enabled: viewModel.count > 0
                    visible: !root.showHistory
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered && !panel.confirmClear
                    onClicked: {
                        if (panel.confirmClear) {
                            panel.confirmClear = false
                            root.clearRows(0, viewModel.count)
                        } else {
                            panel.confirmClear = true
                            confirmTimer.restart()
                        }
                    }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "configure"
                    text: i18n("Configure…")
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }
            }

            // Search
            Kirigami.SearchField {
                id: searchField
                visible: searchButton.checked && !root.showHistory
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                onTextChanged: root.filterText = text
                onVisibleChanged: {
                    if (visible) {
                        forceActiveFocus()
                    } else {
                        text = ""
                    }
                }
                Keys.onEscapePressed: searchButton.checked = false
            }

            // Do Not Disturb strip: duration picker, or status while active
            RowLayout {
                visible: root.dndPicking || root.dndActive
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    text: root.dndActive
                          ? (Plasmoid.configuration.dndUntil < root.foreverMs
                             ? i18n("Do Not Disturb until %1",
                                    Qt.formatTime(new Date(Plasmoid.configuration.dndUntil),
                                                  Qt.locale().timeFormat(Locale.ShortFormat)))
                             : i18n("Do Not Disturb is on"))
                          : i18n("Silence for:")
                }
                PlasmaComponents3.Button {
                    visible: root.dndActive
                    text: i18n("Turn off")
                    onClicked: root.setDnd(false, 0)
                }
                PlasmaComponents3.Button {
                    visible: !root.dndActive
                    text: i18n("1 hour")
                    onClicked: root.setDnd(true, Date.now() + 3600000)
                }
                PlasmaComponents3.Button {
                    visible: !root.dndActive
                    text: i18n("Until tomorrow")
                    onClicked: {
                        const n = new Date()
                        root.setDnd(true, new Date(n.getFullYear(), n.getMonth(), n.getDate() + 1, 8, 0).getTime())
                    }
                }
                PlasmaComponents3.Button {
                    visible: !root.dndActive
                    text: i18n("Until I turn it off")
                    onClicked: root.setDnd(true, 0)
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // List
            PlasmaComponents3.ScrollView {
                visible: !root.showHistory
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    model: viewModel
                    clip: true
                    spacing: 0
                    topMargin: Kirigami.Units.smallSpacing
                    bottomMargin: Kirigami.Units.smallSpacing
                    keyNavigationEnabled: true
                    activeFocusOnTab: true
                    currentIndex: -1
                    reuseItems: false

                    readonly property int groupMode: Plasmoid.configuration.groupMode

                    section.property: groupMode === 0 ? "bucket" : (groupMode === 1 ? "appKey" : "")
                    section.criteria: ViewSection.FullString

                    Keys.onDeletePressed: {
                        const r = viewModel.get(currentIndex)
                        if (r && r.closable) {
                            historyModel.close(root.srcIndex(r.srcRow))
                        }
                    }
                    Keys.onReturnPressed: {
                        const r = viewModel.get(currentIndex)
                        if (r && r.hasDefault) {
                            historyModel.invokeDefaultAction(root.srcIndex(r.srcRow))
                        }
                    }

                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Kirigami.Units.longDuration }
                            NumberAnimation { property: "x"; from: list.width * 0.25; to: 0
                                              duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                        }
                    }
                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: Kirigami.Units.shortDuration }
                            NumberAnimation { property: "scale"; to: 0.9; duration: Kirigami.Units.shortDuration }
                        }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "x,y"; duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                    }

                    section.delegate: Item {
                        id: header
                        required property string section
                        readonly property var info: root.sectionInfo[section] || ({ name: section, icon: "", count: 0 })
                        readonly property bool byApp: list.groupMode === 1
                        readonly property bool isCollapsed: byApp && !!root.collapsed[section]

                        width: ListView.view.width
                        height: headerRow.implicitHeight + Kirigami.Units.largeSpacing

                        TapHandler {
                            enabled: header.byApp
                            onTapped: root.toggleCollapsed(header.section)
                        }

                        RowLayout {
                            id: headerRow
                            anchors {
                                left: parent.left; right: parent.right
                                bottom: parent.bottom
                                leftMargin: Kirigami.Units.largeSpacing
                                rightMargin: Kirigami.Units.smallSpacing
                            }
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                visible: header.byApp
                                source: header.info.icon || "dialog-information"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }
                            Kirigami.Heading {
                                level: 5
                                text: header.info.name
                                opacity: 0.8
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PlasmaComponents3.Label {
                                text: header.info.count
                                font: Kirigami.Theme.smallFont
                                opacity: 0.6
                            }
                            PlasmaComponents3.ToolButton {
                                visible: header.byApp
                                icon.name: "edit-clear-history"
                                text: i18n("Clear %1", header.info.name)
                                display: PlasmaComponents3.AbstractButton.IconOnly
                                PlasmaComponents3.ToolTip.text: text
                                PlasmaComponents3.ToolTip.visible: hovered
                                onClicked: root.clearRows(0, viewModel.count, header.section, 1)
                            }
                            Kirigami.Icon {
                                visible: header.byApp
                                source: header.isCollapsed ? "arrow-right" : "arrow-down"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }
                        }
                    }

                    delegate: Item {
                        id: wrapper
                        readonly property bool isCollapsed: list.groupMode === 1 && !!root.collapsed[model.appKey]
                        readonly property int gutter: Kirigami.Units.smallSpacing

                        width: ListView.view.width
                        height: isCollapsed ? 0 : card.height + gutter
                        visible: height > 0.5
                        clip: true

                        Behavior on height {
                            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
                        }

                        NotificationCard {
                            id: card
                            x: wrapper.gutter
                            width: wrapper.width - wrapper.gutter * 2

                            summary: model.summary
                            body: model.body
                            appName: model.appName
                            appIcon: model.appIcon
                            image: model.image
                            timeText: root.formatTime(model.ms, root.nowMs)
                            unread: model.unread
                            closable: model.closable
                            hasDefault: model.hasDefault
                            actionNames: JSON.parse(model.actionNames || "[]")
                            actionLabels: JSON.parse(model.actionLabels || "[]")
                            urls: JSON.parse(model.urls || "[]")
                            hasReply: model.hasReply
                            replyPlaceholder: model.replyPlaceholder
                            urgency: model.urgency
                            isJob: model.isJob
                            jobRunning: model.jobRunning
                            percentage: model.percentage
                            bodyLines: Plasmoid.configuration.bodyLines
                            showAppName: list.groupMode !== 1
                            isCurrent: wrapper.ListView.isCurrentItem && list.activeFocus

                            onDismissed: historyModel.close(root.srcIndex(model.srcRow))
                            onDefaultInvoked: historyModel.invokeDefaultAction(root.srcIndex(model.srcRow))
                            onActionInvoked: name => historyModel.invokeAction(root.srcIndex(model.srcRow), name)
                            onReplied: text => historyModel.reply(root.srcIndex(model.srcRow), text, 0)
                            onReplyFocusedChanged: root.replyTyping = replyFocused
                        }
                    }

                    Kirigami.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 2
                        visible: list.count === 0
                        icon.name: root.dndActive ? "notification-disabled" : "notification-inactive"
                        text: root.filterText.length > 0 ? i18n("No matching notifications")
                                                         : (root.dndActive ? i18n("Do Not Disturb is on")
                                                                           : i18n("No notifications"))
                    }
                }
            }

            // History: everything received in the last N days, also after Clear All
            RowLayout {
                visible: root.showHistory
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    text: i18np("%1 notification from the last %2 days", "%1 notifications from the last %2 days",
                                root.historyCount, Plasmoid.configuration.historyDays)
                }
                PlasmaComponents3.Button {
                    text: panel.confirmHistoryClear ? i18n("Really clear?") : i18n("Clear history")
                    icon.name: "edit-delete"
                    enabled: root.historyCount > 0
                    onClicked: {
                        if (panel.confirmHistoryClear) {
                            panel.confirmHistoryClear = false
                            root.clearHistory()
                        } else {
                            panel.confirmHistoryClear = true
                            historyConfirmTimer.restart()
                        }
                    }
                }
                Timer {
                    id: historyConfirmTimer
                    interval: 3000
                    onTriggered: panel.confirmHistoryClear = false
                }
            }

            Kirigami.SearchField {
                id: historySearch
                visible: root.showHistory
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                placeholderText: i18n("Search the history…")
                onTextChanged: root.historyFilter = text
                Keys.onEscapePressed: text.length > 0 ? text = "" : root.showHistory = false
                Connections {
                    target: root
                    function onShowHistoryChanged() { if (!root.showHistory) historySearch.text = "" }
                }
            }

            PlasmaComponents3.ScrollView {
                visible: root.showHistory
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: historyList
                    model: historyView
                    clip: true
                    spacing: 0
                    section.property: "day"
                    section.delegate: Kirigami.Heading {
                        required property string section
                        level: 5
                        text: section
                        width: historyList.width
                        topPadding: Kirigami.Units.smallSpacing
                        bottomPadding: Kirigami.Units.smallSpacing
                        leftPadding: Kirigami.Units.largeSpacing
                        opacity: 0.8
                    }
                    delegate: ColumnLayout {
                        required property string summary
                        required property string body
                        required property string appName
                        required property string appIcon
                        required property double ms
                        property bool expanded: false
                        width: historyList.width
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: Kirigami.Units.smallSpacing
                            Layout.leftMargin: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: appIcon
                                fallback: "preferences-desktop-notification"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                Layout.alignment: Qt.AlignTop
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        text: appName
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.7
                                        elide: Text.ElideRight
                                    }
                                    PlasmaComponents3.Label {
                                        text: Qt.formatTime(new Date(ms), Qt.locale().timeFormat(Locale.ShortFormat))
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.7
                                    }
                                }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: summary
                                    font.bold: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                PlasmaComponents3.Label {
                                    id: histBody
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: body
                                    textFormat: Text.StyledText
                                    wrapMode: Text.Wrap
                                    maximumLineCount: expanded ? 1000 : Plasmoid.configuration.bodyLines
                                    elide: Text.ElideRight
                                    opacity: 0.85
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }
                                PlasmaComponents3.Label {
                                    visible: histBody.truncated || expanded
                                    text: expanded ? i18n("Show less") : i18n("Show more")
                                    color: Kirigami.Theme.highlightColor
                                    font: Kirigami.Theme.smallFont
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: expanded = !expanded
                                    }
                                }
                            }
                        }
                        Kirigami.Separator {
                            Layout.fillWidth: true
                            opacity: 0.5
                        }
                    }

                    Kirigami.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 2
                        visible: historyList.count === 0
                        icon.name: "view-history"
                        text: root.historyFilter.length > 0 ? i18n("No matching notifications")
                                                            : i18n("No history yet")
                    }
                }
            }
        }
    }

    // ---- system tray icon ----------------------------------------------------
    function toggleFromTray() {
        // A click that only closed the drawer by taking its focus away must not reopen it.
        if (!isOpen && Date.now() - closedAt < 400) {
            return
        }
        setOpen(!isOpen, false)
    }

    Loader {
        id: trayLoader
        active: Plasmoid.configuration.trayIcon
        source: "TrayIcon.qml"
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("Side Notification Panel: no system tray icon, the Qt Labs Platform QML module is not installed")
            }
        }
    }

    Binding { target: trayLoader.item; property: "dnd"; value: root.dndActive; when: trayLoader.item !== null }
    Binding { target: trayLoader.item; property: "count"; value: root.unreadCount; when: trayLoader.item !== null }
    Binding { target: trayLoader.item; property: "open"; value: root.isOpen; when: trayLoader.item !== null }
    Binding {
        target: trayLoader.item
        property: "tip"
        value: root.toolTipMainText + ": " + root.toolTipSubText
        when: trayLoader.item !== null
    }

    Connections {
        target: trayLoader.item
        ignoreUnknownSignals: true
        function onToggleRequested() { root.toggleFromTray() }
        function onDndRequested(on) { root.setDnd(on, 0) }
        function onClearRequested() { root.clearEverything() }
        function onConfigureRequested() { Plasmoid.internalAction("configure").trigger() }
    }

    // ---- drawer attached to the screen edge ---------------------------------
    // Plasma always opens a widget's popup beside the widget, with a gap, and a widget
    // cannot change that. So the drawer is drawn in a window of its own, placed by hand
    // against the screen edge. A copy of the handle is drawn on top of it (in a strip
    // along the edge), so the handle stays visible and clicking it closes the drawer.
    property real drawerX: 0
    property real drawerY: 0
    property real drawerW: 400
    property real drawerH: 600
    property real railW: 20            // thickness of the strip along the edge
    property real handleLen: 160       // length of the handle along the edge
    property real handleCenter: 300    // handle centre along the edge, inside the drawer

    readonly property bool horizontalEdge: Plasmoid.location === PlasmaCore.Types.TopEdge
                                           || Plasmoid.location === PlasmaCore.Types.BottomEdge
    readonly property bool atStart: Plasmoid.location === PlasmaCore.Types.LeftEdge
                                    || Plasmoid.location === PlasmaCore.Types.TopEdge

    onWidthChanged: if (drawerOpen) placeDrawer()
    onHeightChanged: if (drawerOpen) placeDrawer()

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }

    function placeDrawer() {
        const sx = Screen.virtualX
        const sy = Screen.virtualY
        const sw = Screen.width > 0 ? Screen.width : 1920
        const sh = Screen.height > 0 ? Screen.height : 1080

        // Area not taken by other panels (the handle panel itself does not reserve space).
        let ax = sx, ay = sy, aw = sw, ah = sh
        const a = Plasmoid.availableScreenRect
        if (a && a.width > 0 && a.height > 0) {
            ax = sx + a.x
            ay = sy + a.y
            aw = a.width
            ah = a.height
        }

        // Where the handle is, in screen coordinates. Trusted only if it is really on the
        // expected edge; otherwise the middle of the screen is assumed.
        let hx = sx + sw / 2
        let hy = sy + sh / 2
        const p = root.mapToGlobal(root.width / 2, root.height / 2)
        const loc = Plasmoid.location
        const onEdge = loc === PlasmaCore.Types.LeftEdge ? p.x < sx + 60
                     : loc === PlasmaCore.Types.TopEdge ? p.y < sy + 60
                     : loc === PlasmaCore.Types.BottomEdge ? p.y > sy + sh - 60
                     : p.x > sx + sw - 60
        // Distance from the screen edge to the middle of the handle. The panel can have
        // margins around the widget, so the strip to keep free is twice that, not just the
        // widget's own width.
        let edgeToCentre = 0
        if (onEdge && p.x >= sx && p.x <= sx + sw && p.y >= sy && p.y <= sy + sh) {
            hx = p.x
            hy = p.y
            edgeToCentre = loc === PlasmaCore.Types.LeftEdge ? p.x - sx
                         : loc === PlasmaCore.Types.TopEdge ? p.y - sy
                         : loc === PlasmaCore.Types.BottomEdge ? sy + sh - p.y
                         : sx + sw - p.x
        }

        const vertical = !horizontalEdge
        const thickness = vertical ? root.width : root.height
        const length = vertical ? root.height : root.width
        const measured = thickness >= 8 ? thickness : 20
        railW = Math.ceil(Math.max(measured, Math.min(edgeToCentre * 2, measured + 40)))
        handleLen = length >= 40 ? length : 160

        const wanted = Kirigami.Units.gridUnit * Plasmoid.configuration.drawerWidth
        const pct = Plasmoid.configuration.drawerHeight / 100
        let W, H, X, Y
        if (vertical) {
            W = Math.round(Math.min(wanted, sw * 0.95))
            H = Math.round(Math.min(ah * pct, ah))
            X = atStart ? sx : sx + sw - W              // flush with the screen edge
            Y = ay + Math.round((ah - H) / 2)
            handleCenter = clamp(hy - Y, handleLen / 2, H - handleLen / 2)
        } else {
            W = Math.round(Math.min(wanted, aw))
            H = Math.round(Math.min(ah * pct, ah))
            X = clamp(Math.round(hx - W / 2), ax, ax + aw - W)
            Y = atStart ? sy : sy + sh - H              // flush with the screen edge
            handleCenter = clamp(hx - X, handleLen / 2, W - handleLen / 2)
        }
        drawerW = W
        drawerH = H
        drawerX = X
        drawerY = Y
    }

    PlasmaCore.Dialog {
        id: drawer
        visible: root.drawerOpen
        location: PlasmaCore.Types.Floating
        backgroundHints: PlasmaCore.Types.NoBackground
        hideOnWindowDeactivate: true
        x: root.drawerX
        y: root.drawerY

        onVisibleChanged: {
            if (visible) {
                requestActivate()
            } else {
                root.closedAt = Date.now()
                root.drawerOpen = false
            }
        }

        mainItem: FocusScope {
            id: drawerScope
            focus: true
            implicitWidth: root.drawerW
            implicitHeight: root.drawerH
            Layout.minimumWidth: root.drawerW
            Layout.maximumWidth: root.drawerW
            Layout.preferredWidth: root.drawerW
            Layout.minimumHeight: root.drawerH
            Layout.maximumHeight: root.drawerH
            Layout.preferredHeight: root.drawerH

            Kirigami.Theme.colorSet: Kirigami.Theme.Window
            Kirigami.Theme.inherit: false

            Keys.onEscapePressed: root.drawerOpen = false

            HoverHandler { id: drawerHover }
            Binding {
                target: root
                property: "popupHover"
                value: drawerHover.hovered
                when: root.edgeDrawer && root.drawerOpen
            }

            Rectangle {
                anchors.fill: parent
                color: Kirigami.Theme.backgroundColor
            }

            // thin line along the inner edge of the drawer
            Kirigami.Separator {
                x: root.horizontalEdge ? 0 : (root.atStart ? parent.width - width : 0)
                y: root.horizontalEdge ? (root.atStart ? parent.height - height : 0) : 0
                width: root.horizontalEdge ? parent.width : 1
                height: root.horizontalEdge ? 1 : parent.height
            }

            // the notifications, leaving the strip along the screen edge free for the handle
            Loader {
                active: root.drawerOpen
                sourceComponent: panelComponent
                x: (!root.horizontalEdge && root.atStart) ? root.railW : 0
                y: (root.horizontalEdge && root.atStart) ? root.railW : 0
                width: root.drawerW - (root.horizontalEdge ? 0 : root.railW)
                height: root.drawerH - (root.horizontalEdge ? root.railW : 0)
            }

            // the handle, in the same place as the real one; clicking it closes the drawer
            MouseArea {
                id: drawerHandle
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                width: root.horizontalEdge ? root.handleLen : root.railW
                height: root.horizontalEdge ? root.railW : root.handleLen
                x: root.horizontalEdge ? root.handleCenter - width / 2
                                       : (root.atStart ? 0 : parent.width - width)
                y: root.horizontalEdge ? (root.atStart ? 0 : parent.height - height)
                                       : root.handleCenter - height / 2
                onClicked: root.drawerOpen = false

                HandleFace {
                    id: drawerFace
                    anchors.fill: parent
                    fill: root.handleFill(true, drawerHandle.containsMouse)
                    textColor: root.handleText(drawerFace.fill)
                    iconName: root.dndActive ? "notification-disabled" : "notification-active"
                    count: root.handleCount
                    mode: Plasmoid.configuration.handleFace
                    horizontal: root.horizontalEdge
                    appIcons: root.handleIcons
                    maxIcons: Plasmoid.configuration.handleMaxIcons
                }
            }
        }
    }
}
__SNP_EOF__
    mkdir -p "$PKG/contents/ui"
    cat > "$PKG/contents/ui/NotificationCard.qml" <<'__SNP_EOF__'
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// One notification card. Swipe horizontally to dismiss, click for the default
// action, click the text to expand it, hover to reveal the close button.
//
// Layout note: the content uses a plain Column with explicit widths instead of
// nested Layouts, so wrapped text always reports an exact height (no stray
// empty space under the card).
Item {
    id: card

    property string summary
    property string body
    property string appName
    property string appIcon
    property var image
    property string timeText
    property bool unread: false
    property bool closable: true
    property bool hasDefault: false
    property var actionNames: []
    property var actionLabels: []
    property var urls: []
    property bool hasReply: false
    property string replyPlaceholder
    property int urgency: 1
    property bool isJob: false
    property bool jobRunning: false
    property int percentage: 0
    property int bodyLines: 4
    property bool showAppName: true
    property bool isCurrent: false

    signal dismissed()
    signal defaultInvoked()
    signal actionInvoked(string name)
    signal replied(string text)

    property bool expanded: false
    readonly property bool canExpand: measure.lineCount > card.bodyLines
    readonly property bool replyFocused: replyField.activeFocus

    readonly property var imageUrls: {
        const out = []
        for (const u of urls) {
            if (/\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(u.toString())) {
                out.push(u.toString())
            }
        }
        return out
    }

    readonly property real leftPad: Kirigami.Units.smallSpacing + 3
    readonly property real rightPad: Kirigami.Units.smallSpacing
    readonly property real vPad: Kirigami.Units.smallSpacing
    readonly property bool showIcon: !!card.image || card.showAppName

    height: frame.height

    function linkify(t) {
        if (!t) {
            return ""
        }
        if (t.indexOf("<a ") !== -1) {
            return t
        }
        return t.replace(/(https?:\/\/[^\s<>"']+)/g, '<a href="$1">$1</a>')
    }

    function fileName(u) {
        const s = decodeURIComponent(u.toString())
        return s.substring(s.lastIndexOf("/") + 1) || s
    }

    Timer {
        id: dismissTimer
        interval: Kirigami.Units.longDuration
        onTriggered: card.dismissed()
    }

    Rectangle {
        id: frame
        width: parent.width
        height: content.height + card.vPad * 2
        radius: Kirigami.Units.cornerRadius
        color: hover.hovered
               ? Qt.alpha(Kirigami.Theme.highlightColor, 0.14)
               : Qt.alpha(Kirigami.Theme.textColor, 0.06)
        border.width: card.isCurrent ? 2 : 0
        border.color: Kirigami.Theme.highlightColor
        opacity: 1 - Math.min(Math.abs(x) / (width * 0.9), 1)

        Behavior on x {
            enabled: !drag.active
            NumberAnimation {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on color {
            ColorAnimation { duration: Kirigami.Units.shortDuration }
        }
        Behavior on height {
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        // Accent bar: red for critical, accent colour for unread
        Rectangle {
            // urgency values are flags in plasma-workspace: low=1, normal=2, critical=4
            readonly property bool critical: card.urgency >= 4
            visible: critical || card.unread
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 3
            radius: 1.5
            color: critical ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
        }

        HoverHandler {
            id: hover
            cursorShape: card.hasDefault ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            onTapped: eventPoint => {
                if (bodyLabel.hoveredLink) {
                    return   // a link was clicked; Text handles it
                }
                const p = bodyLabel.mapFromItem(frame, eventPoint.position)
                const onBody = bodyLabel.visible && bodyLabel.contains(p)
                if (onBody && card.canExpand) {
                    card.expanded = !card.expanded
                } else if (card.hasDefault) {
                    card.defaultInvoked()
                }
            }
        }

        DragHandler {
            id: drag
            target: frame
            yAxis.enabled: false
            xAxis.enabled: card.closable
            onActiveChanged: {
                if (active) {
                    return
                }
                if (Math.abs(frame.x) > frame.width * 0.35) {
                    frame.x = (frame.x > 0 ? 1 : -1) * frame.width
                    dismissTimer.start()
                } else {
                    frame.x = 0
                }
            }
        }

        // Invisible copy of the body without a line limit, used only to find
        // out whether the real label would need more than bodyLines lines.
        PlasmaComponents3.Label {
            id: measure
            visible: false
            width: bodyLabel.width
            text: bodyLabel.text
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
        }

        Column {
            id: content
            x: card.leftPad
            y: card.vPad
            width: frame.width - card.leftPad - card.rightPad
            spacing: Kirigami.Units.smallSpacing

            // Icon + texts + close button
            Item {
                id: mainRow
                width: parent.width
                height: Math.max(iconItem.visible ? iconItem.height : 0, textCol.height)

                Kirigami.Icon {
                    id: iconItem
                    visible: card.showIcon
                    source: card.image ? card.image : (card.appIcon || "dialog-information")
                    width: card.image ? Kirigami.Units.iconSizes.large : Kirigami.Units.iconSizes.medium
                    height: width
                    anchors { left: parent.left; top: parent.top }
                }

                // The close button's space is always reserved (only its opacity
                // changes), so hovering never makes the text reflow.
                PlasmaComponents3.ToolButton {
                    id: closeButton
                    visible: card.closable
                    opacity: (hover.hovered || closeHover.hovered || Kirigami.Settings.isMobile) ? 1 : 0
                    enabled: opacity > 0
                    icon.name: "window-close"
                    anchors { right: parent.right; top: parent.top }
                    onClicked: card.dismissed()
                    HoverHandler { id: closeHover }
                    Behavior on opacity {
                        NumberAnimation { duration: Kirigami.Units.shortDuration }
                    }
                }

                Column {
                    id: textCol
                    anchors {
                        left: iconItem.visible ? iconItem.right : parent.left
                        leftMargin: iconItem.visible ? Kirigami.Units.smallSpacing : 0
                        right: closeButton.visible ? closeButton.left : parent.right
                        top: parent.top
                    }
                    spacing: 0

                    // app name (left) + time (right)
                    Item {
                        width: parent.width
                        height: Math.max(timeLabel.implicitHeight, appLabel.implicitHeight)

                        PlasmaComponents3.Label {
                            id: appLabel
                            visible: card.showAppName
                            anchors { left: parent.left; right: timeLabel.left; rightMargin: Kirigami.Units.smallSpacing }
                            text: card.appName
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            elide: Text.ElideRight
                        }
                        PlasmaComponents3.Label {
                            id: timeLabel
                            anchors.right: parent.right
                            text: card.timeText
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                        }
                    }

                    PlasmaComponents3.Label {
                        visible: text.length > 0
                        width: parent.width
                        text: card.summary
                        font.bold: true
                        wrapMode: Text.Wrap
                    }

                    PlasmaComponents3.Label {
                        id: bodyLabel
                        visible: text.length > 0
                        width: parent.width
                        text: card.linkify(card.body)
                        textFormat: Text.StyledText
                        linkColor: Kirigami.Theme.linkColor
                        wrapMode: Text.Wrap
                        maximumLineCount: card.expanded ? 1000 : card.bodyLines
                        elide: Text.ElideRight
                        onLinkActivated: link => Qt.openUrlExternally(link)

                        HoverHandler {
                            cursorShape: bodyLabel.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                    }

                    PlasmaComponents3.ProgressBar {
                        visible: card.isJob && card.jobRunning
                        width: parent.width
                        from: 0
                        to: 100
                        value: card.percentage
                    }
                }
            }

            // Photo preview for attached image files; click to open
            Rectangle {
                visible: card.imageUrls.length > 0
                width: parent.width
                height: Kirigami.Units.gridUnit * 8
                radius: Kirigami.Units.cornerRadius
                color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                clip: true

                Image {
                    anchors.fill: parent
                    source: card.imageUrls.length > 0 ? card.imageUrls[0] : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 800
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: Qt.openUrlExternally(card.imageUrls[0])
                }
            }

            // Notification actions ("Reply", "Open", ...)
            Flow {
                visible: card.actionNames.length > 0
                width: parent.width
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: card.actionNames.length
                    PlasmaComponents3.Button {
                        required property int index
                        text: card.actionLabels[index] || card.actionNames[index]
                        onClicked: card.actionInvoked(card.actionNames[index])
                    }
                }
            }

            // Files attached to the notification (e.g. a screenshot)
            Flow {
                visible: card.urls.length > 0
                width: parent.width
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: Math.min(card.urls.length, 3)
                    PlasmaComponents3.Button {
                        required property int index
                        flat: true
                        icon.name: "document-open"
                        text: card.fileName(card.urls[index])
                        onClicked: Qt.openUrlExternally(card.urls[index])
                    }
                }
            }

            // Inline reply
            Item {
                visible: card.hasReply
                width: parent.width
                height: replyField.implicitHeight

                PlasmaComponents3.TextField {
                    id: replyField
                    anchors { left: parent.left; right: sendButton.left; rightMargin: Kirigami.Units.smallSpacing }
                    placeholderText: card.replyPlaceholder || i18n("Reply…")
                    onAccepted: sendReply()
                    function sendReply() {
                        if (text.length > 0) {
                            card.replied(text)
                            text = ""
                        }
                    }
                }
                PlasmaComponents3.ToolButton {
                    id: sendButton
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    icon.name: "mail-send"
                    enabled: replyField.text.length > 0
                    onClicked: replyField.sendReply()
                }
            }

            Item {
                visible: card.canExpand
                width: parent.width
                height: showMoreButton.implicitHeight

                PlasmaComponents3.ToolButton {
                    id: showMoreButton
                    anchors.horizontalCenter: parent.horizontalCenter
                    flat: true
                    text: card.expanded ? i18n("Show less") : i18n("Show more")
                    icon.name: card.expanded ? "arrow-up" : "arrow-down"
                    onClicked: card.expanded = !card.expanded
                }
            }
        }
    }
}
__SNP_EOF__
    mkdir -p "$PKG/contents/ui"
    cat > "$PKG/contents/ui/HandleFace.qml" <<'__SNP_EOF__'
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// How the handle looks: a rounded background with a bell and/or the number of
// notifications at its centre. Used by the real handle and by its copy in the drawer.
Item {
    id: face

    property color fill
    property color textColor
    property string iconName: "notification-active"
    property int count: 0
    // 0 = number only (bell when there is nothing to count), 1 = bell and number, 2 = bell only
    property int mode: 0
    property bool horizontal: false     // the handle lies along the top or bottom edge
    property real blinkAmount: 0        // 0..1, how far the blink has dimmed the background
    property var appIcons: []           // icon names of the apps with unread notifications
    property int maxIcons: 3

    readonly property bool showNumber: mode !== 2 && count > 0
    readonly property bool showBell: mode !== 0 || !showNumber
    readonly property real thickness: horizontal ? height : width
    readonly property real inner: Math.max(8, thickness - 6)       // room for the bell
    readonly property real textRoom: Math.max(8, thickness - 4)    // room for the number

    readonly property real length: horizontal ? width : height
    readonly property real iconSize: Math.max(8, Math.min(Kirigami.Units.iconSizes.small, thickness - 6))
    // room taken by what sits in the middle: the bell and/or the number
    readonly property real centerLength: (showBell ? iconSize : 0) + (showNumber ? 14 : 0)
                                         + (showBell && showNumber ? 3 : 0)
    // icons are split above/below (or left/right of) the middle, so the number stays centred
    readonly property int fitPerSide: Math.max(0, Math.floor((length - centerLength - 8) / 2 / (iconSize + 2)))
    readonly property int slots: Math.min(appIcons.length, maxIcons, fitPerSide * 2)
    // when more apps have unread notifications than fit, the last slot says how many are not shown
    readonly property bool overflow: slots >= 2 && appIcons.length > slots
    readonly property int iconCount: overflow ? slots - 1 : slots
    readonly property int hiddenApps: appIcons.length - iconCount
    readonly property int firstHalf: Math.ceil(slots / 2)
    readonly property real sideLength: firstHalf * (iconSize + 2)

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Math.min(width, height) / 2
        color: face.fill
        opacity: 1 - 0.65 * face.blinkAmount
        Behavior on color {
            ColorAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    GridLayout {
        anchors.centerIn: parent
        flow: face.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
        rowSpacing: 1
        columnSpacing: 3

        // first half of the app icons
        Item {
            visible: face.slots > 0
            Layout.preferredWidth: face.horizontal ? face.sideLength : face.iconSize
            Layout.preferredHeight: face.horizontal ? face.iconSize : face.sideLength
            Layout.alignment: Qt.AlignCenter
            GridLayout {
                anchors.right: face.horizontal ? parent.right : undefined
                anchors.bottom: face.horizontal ? undefined : parent.bottom
                anchors.verticalCenter: face.horizontal ? parent.verticalCenter : undefined
                anchors.horizontalCenter: face.horizontal ? undefined : parent.horizontalCenter
                flow: face.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
                rowSpacing: 2
                columnSpacing: 2
                Repeater {
                    model: Math.min(face.firstHalf, face.iconCount)
                    Kirigami.Icon {
                        source: face.appIcons[index]
                        fallback: "preferences-desktop-notification"
                        Layout.preferredWidth: face.iconSize
                        Layout.preferredHeight: face.iconSize
                    }
                }
            }
        }

        Kirigami.Icon {
            visible: face.showBell
            source: face.iconName
            isMask: true
            color: face.textColor
            Layout.preferredWidth: Math.min(face.inner, Kirigami.Units.iconSizes.smallMedium)
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignCenter
        }

        PlasmaComponents3.Label {
            visible: face.showNumber
            text: face.count > 99 ? "99+" : String(face.count)
            color: face.textColor
            font.bold: text.length <= 2          // three characters need the narrower, regular weight
            font.pixelSize: 12
            fontSizeMode: Text.Fit
            minimumPixelSize: 7
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignCenter
            Layout.maximumWidth: face.horizontal ? 1000 : face.textRoom
            Layout.maximumHeight: face.horizontal ? face.textRoom : 1000
        }

        // second half of the app icons
        Item {
            visible: face.slots > 0
            Layout.preferredWidth: face.horizontal ? face.sideLength : face.iconSize
            Layout.preferredHeight: face.horizontal ? face.iconSize : face.sideLength
            Layout.alignment: Qt.AlignCenter
            GridLayout {
                anchors.left: face.horizontal ? parent.left : undefined
                anchors.top: face.horizontal ? undefined : parent.top
                anchors.verticalCenter: face.horizontal ? parent.verticalCenter : undefined
                anchors.horizontalCenter: face.horizontal ? undefined : parent.horizontalCenter
                flow: face.horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
                rowSpacing: 2
                columnSpacing: 2
                Repeater {
                    model: Math.max(0, face.iconCount - face.firstHalf)
                    Kirigami.Icon {
                        source: face.appIcons[face.firstHalf + index]
                        fallback: "preferences-desktop-notification"
                        Layout.preferredWidth: face.iconSize
                        Layout.preferredHeight: face.iconSize
                    }
                }
                PlasmaComponents3.Label {
                    visible: face.overflow
                    text: "+" + face.hiddenApps
                    color: face.textColor
                    font.pixelSize: 9
                    font.bold: true
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 6
                    horizontalAlignment: Text.AlignHCenter
                    Layout.alignment: Qt.AlignCenter
                    Layout.preferredWidth: face.horizontal ? face.iconSize + 2 : face.thickness - 4
                    Layout.preferredHeight: face.iconSize
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
__SNP_EOF__
    mkdir -p "$PKG/contents/ui"
    cat > "$PKG/contents/ui/TrayIcon.qml" <<'__SNP_EOF__'
import QtQuick
import Qt.labs.platform as Platform

// An icon in Plasma's system tray (a StatusNotifierItem). Left click opens or closes the
// panel; right click shows a small menu.
//
// This file is loaded optionally: the Qt Labs Platform module is packaged separately on
// some distributions. If it is missing, loading this file fails and the rest of the widget
// carries on without a tray icon.
Platform.SystemTrayIcon {
    id: tray

    property bool dnd: false
    property int count: 0            // unread notifications
    property string tip: ""
    property bool open: false

    signal toggleRequested()
    signal dndRequested(bool on)
    signal clearRequested()
    signal configureRequested()

    visible: true
    icon.name: dnd ? "notification-disabled" : (count > 0 ? "notification-active" : "notification-inactive")
    tooltip: tip

    onActivated: reason => {
        if (reason === Platform.SystemTrayIcon.Trigger) {
            tray.toggleRequested()
        }
    }

    menu: Platform.Menu {
        Platform.MenuItem {
            text: tray.open ? i18n("Close Notifications") : i18n("Open Notifications")
            onTriggered: tray.toggleRequested()
        }
        Platform.MenuItem {
            text: i18n("Do Not Disturb")
            checkable: true
            checked: tray.dnd
            onTriggered: tray.dndRequested(!tray.dnd)
        }
        Platform.MenuItem {
            text: i18n("Clear All Notifications")
            onTriggered: tray.clearRequested()
        }
        Platform.MenuSeparator {}
        Platform.MenuItem {
            text: i18n("Configure…")
            onTriggered: tray.configureRequested()
        }
    }
}
__SNP_EOF__
    mkdir -p "$PKG/contents/ui"
    cat > "$PKG/contents/ui/configGeneral.qml" <<'__SNP_EOF__'
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_groupMode: groupCombo.currentIndex
    property alias cfg_bodyLines: linesSpin.value
    property alias cfg_relativeTimes: relativeCheck.checked
    property alias cfg_markReadOnHover: hoverCheck.checked
    property alias cfg_popupsEnabled: popupCheck.checked
    property alias cfg_historyEnabled: historyCheck.checked
    property alias cfg_historyDays: historyDaysSpin.value

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: groupCombo
            Kirigami.FormData.label: i18n("Group notifications:")
            model: [i18n("By date"), i18n("By application"), i18n("Don't group")]
        }

        QQC2.SpinBox {
            id: linesSpin
            Kirigami.FormData.label: i18n("Lines of text before \"Show more\":")
            from: 1
            to: 12
        }

        QQC2.CheckBox {
            id: relativeCheck
            Kirigami.FormData.label: i18n("Times:")
            text: i18n("Show relative times (\"5 min ago\")")
        }

        QQC2.CheckBox {
            id: hoverCheck
            Kirigami.FormData.label: i18n("Unread:")
            text: i18n("Mark as read after hovering the panel")
        }

        QQC2.CheckBox {
            id: popupCheck
            Kirigami.FormData.label: i18n("Pop-ups:")
            text: i18n("Show Plasma's pop-up for each new notification")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18n("Switched off, notifications still arrive here and the handle still counts and blinks, but Plasma shows no pop-up. This works by holding Plasma's notifications back, the same way as Do Not Disturb, so notification sounds are silenced too, and urgent (critical) notifications may still pop up if Plasma is set to allow that in Do Not Disturb mode.")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("History")
        }

        QQC2.CheckBox {
            id: historyCheck
            Kirigami.FormData.label: i18n("Keep a history:")
            text: i18n("Remember notifications, also after Clear All and restarts")
        }

        QQC2.SpinBox {
            id: historyDaysSpin
            Kirigami.FormData.label: i18n("Keep for:")
            enabled: historyCheck.checked
            from: 1
            to: 365
            editable: true
            textFromValue: function(value) { return i18np("%1 day", "%1 days", value) }
            valueFromText: function(text) { return parseInt(text) || 30 }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18n("Open it with the history button at the top of the panel. Only text is kept (not images or actions), at most 1500 entries; older ones are removed automatically.")
        }
    }
}
__SNP_EOF__
    mkdir -p "$PKG/contents/ui"
    cat > "$PKG/contents/ui/configOpening.qml" <<'__SNP_EOF__'
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_drawerStyle: styleCombo.currentIndex
    property alias cfg_trayIcon: trayCheck.checked
    property alias cfg_revealMode: revealCombo.currentIndex
    property alias cfg_hoverDelay: delaySpin.value
    property alias cfg_closeOnLeave: leaveCheck.checked
    property alias cfg_closeDelay: closeDelaySpin.value
    property alias cfg_drawerWidth: widthSpin.value
    property alias cfg_drawerHeight: heightSpin.value

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: styleCombo
            Kirigami.FormData.label: i18n("Opened panel:")
            model: [i18n("Attached to the screen edge, handle on top"), i18n("Popup next to the handle")]
        }

        QQC2.CheckBox {
            id: trayCheck
            Kirigami.FormData.label: i18n("System tray:")
            text: i18n("Also open the panel from an icon in the system tray")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18n("If the icon does not show, set it to \"Always shown\" in the system tray's settings. It needs the Qt Labs Platform QML module, which some distributions package separately.")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Showing the panel")
        }

        QQC2.ComboBox {
            id: revealCombo
            Kirigami.FormData.label: i18n("Open the panel by:")
            model: [i18n("Clicking the handle"), i18n("Hovering the handle, or clicking it")]
        }

        QQC2.SpinBox {
            id: delaySpin
            Kirigami.FormData.label: i18n("Delay before opening:")
            enabled: revealCombo.currentIndex >= 1
            from: 0
            to: 3000
            stepSize: 50
            editable: true
            textFromValue: function(value) { return i18n("%1 ms", value) }
            valueFromText: function(text) { return parseInt(text) || 0 }
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Hiding the panel")
        }

        QQC2.CheckBox {
            id: leaveCheck
            Kirigami.FormData.label: i18n("When opened by hovering:")
            text: i18n("Close when the pointer leaves")
            enabled: revealCombo.currentIndex >= 1
        }

        QQC2.SpinBox {
            id: closeDelaySpin
            Kirigami.FormData.label: i18n("Delay before closing:")
            enabled: revealCombo.currentIndex >= 1 && leaveCheck.checked
            from: 0
            to: 5000
            stepSize: 100
            editable: true
            textFromValue: function(value) { return i18n("%1 ms", value) }
            valueFromText: function(text) { return parseInt(text) || 0 }
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Size of the opened panel")
        }

        QQC2.SpinBox {
            id: widthSpin
            Kirigami.FormData.label: i18n("Width:")
            from: 14
            to: 48
            editable: true
            textFromValue: function(value) { return i18n("%1 units", value) }
            valueFromText: function(text) { return parseInt(text) || 22 }
        }

        QQC2.SpinBox {
            id: heightSpin
            Kirigami.FormData.label: i18n("Height:")
            from: 30
            to: 100
            stepSize: 5
            editable: true
            textFromValue: function(value) { return i18n("%1 % of the screen", value) }
            valueFromText: function(text) { return parseInt(text) || 100 }
        }

        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18n("The width includes the strip along the screen edge that holds the handle. These options apply when the widget sits in a thin handle panel; in a wide, auto-hiding sidebar panel, Plasma itself controls when the panel appears.")
        }
    }
}
__SNP_EOF__
    mkdir -p "$PKG/contents/ui"
    cat > "$PKG/contents/ui/configHandle.qml" <<'__SNP_EOF__'
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

KCM.SimpleKCM {
    property alias cfg_handleFace: faceCombo.currentIndex
    property alias cfg_handleCountMode: countCombo.currentIndex
    property alias cfg_handleCustomColors: customCheck.checked
    property alias cfg_handleColor: normalColor.color
    property alias cfg_handleUnreadColor: unreadColor.color
    property alias cfg_handleBlink: blinkCombo.currentIndex
    property alias cfg_handleAppIcons: iconsCheck.checked
    property alias cfg_handleMaxIcons: maxIconsSpin.value

    Kirigami.FormLayout {
        QQC2.Label {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("What the handle shows")
        }

        QQC2.ComboBox {
            id: faceCombo
            Kirigami.FormData.label: i18n("Handle shows:")
            model: [i18n("The number (a bell when there is none)"), i18n("A bell and the number"), i18n("Only a bell")]
        }

        QQC2.ComboBox {
            id: countCombo
            Kirigami.FormData.label: i18n("The number counts:")
            enabled: faceCombo.currentIndex < 2
            model: [i18n("New (unread) notifications"), i18n("All notifications")]
        }

        QQC2.CheckBox {
            id: iconsCheck
            Kirigami.FormData.label: i18n("Application icons:")
            text: i18n("Show the icons of apps that have unread notifications")
        }

        QQC2.SpinBox {
            id: maxIconsSpin
            Kirigami.FormData.label: i18n("At most:")
            enabled: iconsCheck.checked
            from: 1
            to: 12
            textFromValue: function(value) { return i18np("%1 icon", "%1 icons", value) }
            valueFromText: function(text) { return parseInt(text) || 5 }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18n("The icons sit above and below the number. Only as many as fit are shown; if more apps have unread notifications, the last slot shows \"+N\" for the rest. A longer handle shows more.")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Colours")
        }

        QQC2.CheckBox {
            id: customCheck
            text: i18n("Use custom colours (otherwise they follow the Plasma theme)")
        }

        KQuickControls.ColorButton {
            id: normalColor
            Kirigami.FormData.label: i18n("Normal:")
            enabled: customCheck.checked
            showAlphaChannel: true
        }

        KQuickControls.ColorButton {
            id: unreadColor
            Kirigami.FormData.label: i18n("New notifications:")
            enabled: customCheck.checked
            showAlphaChannel: true
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Blinking")
        }

        QQC2.ComboBox {
            id: blinkCombo
            Kirigami.FormData.label: i18n("When a new notification arrives:")
            model: [i18n("Don't blink"), i18n("Blink a few times"), i18n("Blink until I open the panel")]
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            opacity: 0.7
            text: i18n("The handle does not blink while Do Not Disturb is on, or while the panel is open.")
        }
    }
}
__SNP_EOF__
    mkdir -p "$PKG/contents/ui"
    cat > "$PKG/contents/ui/configReadme.qml" <<'__SNP_EOF__'
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    readonly property var news: [
        i18n("Notification history: a history button at the top of the panel shows everything you received in the last N days, grouped by day, with its own search box. It survives Clear All and restarts."),
        i18n("History settings (General): turn it on or off and choose how many days back it is kept."),
        i18n("Fixed: long notifications in the history were cut off; they now have a \"Show more\" link."),
        i18n("Fixed: notification text in the history showed raw markup; it now displays like in the list."),
        i18n("Fixed: with a wider handle panel, the handle no longer covers part of the notifications in the opened drawer.")
    ]


    readonly property var sections: [
        { title: i18n("General"), items: [
            [i18n("Group notifications"), i18n("How the list is organised: by date (Today, Yesterday...), by application, or not grouped.")],
            [i18n("Lines before \"Show more\""), i18n("How many lines of a long message are shown before it is folded.")],
            [i18n("Relative times"), i18n("Show \"5 min ago\" instead of the clock time.")],
            [i18n("Mark as read on hover"), i18n("Notifications count as read once you hover the open panel.")],
            [i18n("Keep a history"), i18n("Remembers notifications after Clear All and restarts. Open it with the history button at the top of the panel.")],
            [i18n("Keep for"), i18n("How many days back the history is kept (1 to 365).")],
            [i18n("Pop-ups"), i18n("Turns Plasma's own pop-up for each new notification on or off. Off holds notifications back like Do Not Disturb, so sounds are silenced too; they still arrive in this panel.")]
        ]},
        { title: i18n("Opening"), items: [
            [i18n("Opened panel"), i18n("Drawer attached to the screen edge with the handle on top, or a Plasma popup next to the handle.")],
            [i18n("System tray"), i18n("Adds a tray icon that opens and closes the panel too.")],
            [i18n("Open the panel by"), i18n("Clicking the handle only, or also hovering it.")],
            [i18n("Delay before opening"), i18n("How long the pointer must rest on the handle before it opens (hover mode).")],
            [i18n("Close when the pointer leaves"), i18n("Closes a panel that was opened by hovering, after the closing delay.")],
            [i18n("Width and height"), i18n("Size of the opened panel: width in grid units, height as a share of the screen.")]
        ]},
        { title: i18n("Handle"), items: [
            [i18n("Handle shows"), i18n("The number of notifications (a bell when none), a bell and the number, or only a bell.")],
            [i18n("The number counts"), i18n("Only new (unread) notifications, or everything in the history.")],
            [i18n("Application icons"), i18n("Shows the icons of apps with unread notifications above and below the number, up to the chosen maximum; the rest show as \"+N\". A longer handle fits more.")],
            [i18n("Colours"), i18n("Follow the Plasma theme, or pick your own for the normal and new-notification states.")],
            [i18n("Blinking"), i18n("Never, a few times, or until you open the panel when a new notification arrives.")]
        ]}
    ]

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            level: 2
            text: i18n("Side Notification Panel")
            Layout.fillWidth: true
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18n("A notification history that slides out from the edge of your screen. A small handle stays visible on the edge: click it (or the tray icon) to open the panel. In the panel you can search, group, expand long messages, open links and images, use actions and inline replies, swipe a notification sideways to dismiss it, clear all, and turn on Do Not Disturb (also in the right-click menu of the handle).")
        }

        Kirigami.Heading {
            level: 3
            text: i18n("What's new in 2.1.3")
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
        Kirigami.Separator { Layout.fillWidth: true }
        Repeater {
            model: page.news
            delegate: QQC2.Label {
                required property string modelData
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "\u2022  " + modelData
            }
        }

        Repeater {
            model: page.sections
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    level: 3
                    text: i18n("%1 tab", modelData.title)
                    Layout.topMargin: Kirigami.Units.largeSpacing
                }
                Kirigami.Separator { Layout.fillWidth: true }

                Repeater {
                    model: modelData.items
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        QQC2.Label {
                            text: modelData[0]
                            font.bold: true
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                        QQC2.Label {
                            text: modelData[1]
                            opacity: 0.8
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
__SNP_EOF__
}

install_pkg() {
    extract_package
    if is_installed; then
        say "Updating the widget"
        kpackagetool6 -t Plasma/Applet -u "$PKG" >/dev/null
        UPGRADED=1
    else
        say "Installing the widget"
        kpackagetool6 -t Plasma/Applet -i "$PKG" >/dev/null
    fi
}

restart_shell() {
    shell_running || return 0
    if (( ! RESTART )); then
        say "Not restarting Plasma. Run 'plasmashell --replace' or log out and in to load the new version."
        return 0
    fi
    say "Restarting the Plasma shell so the new version loads"
    if systemctl --user is-active --quiet plasma-plasmashell.service 2>/dev/null; then
        systemctl --user restart plasma-plasmashell.service
    else
        kquitapp6 plasmashell >/dev/null 2>&1 || true
        sleep 1
        ( setsid kstart plasmashell >/dev/null 2>&1 || setsid plasmashell >/dev/null 2>&1 ) &
    fi
    wait_shell
}

# Plasma scripting: remove every panel / desktop widget that hosts our widget.
js_remove() {
    cat <<'JS'
var ID = "com.user.sidenotifications";
var pids = panelIds;
for (var i = 0; i < pids.length; ++i) {
    var p = panelById(pids[i]);
    var wids = p.widgetIds, hit = false;
    for (var j = 0; j < wids.length; ++j) {
        if (p.widgetById(wids[j]).type == ID) { hit = true; }
    }
    if (hit) { p.remove(); }
}
var ds = desktops();
for (var k = 0; k < ds.length; ++k) {
    var ws = ds[k].widgets();
    for (var m = 0; m < ws.length; ++m) {
        if (ws[m].type == ID) { ws[m].remove(); }
    }
}
JS
}

# Plasma scripting: create the panel and add the widget.
js_create() {
    cat <<JS
var panel = new Panel;
panel.location = "$EDGE";
panel.screen = $SCREEN;
panel.height = $SIZE;
panel.floating = false;
JS
    if [[ $MODE == handle ]]; then
        cat <<JS
panel.hiding = "windowsbelow";
panel.alignment = "center";
panel.minimumLength = $LENGTH;
panel.maximumLength = $LENGTH;
panel.length = $LENGTH;
JS
    else
        echo 'panel.hiding = "autohide";'
    fi
    echo "panel.addWidget(\"$ID\");"
}

# Sends a mix of sample notifications (also tests grouping, urgency, images, actions).
run_tests() {
    # Needs gdbus (package: glib2 / libglib2.0-bin) and python3.
    NOTIFY=(gdbus call --session --dest org.freedesktop.Notifications
            --object-path /org/freedesktop/Notifications
            --method org.freedesktop.Notifications.Notify)

    # send APP ICON SUMMARY BODY ACTIONS HINTS   (ACTIONS/HINTS are GVariant text)
    send() {
        "${NOTIFY[@]}" "$1" 0 "$2" "$3" "$4" "${5:-[]}" "${6:-{\}}" 0 >/dev/null
        sleep 0.5
    }

    # --- make a real "photo" (gradient PNG) with plain python, no extra packages ---
    PHOTO=/tmp/sidepanel-test-photo.png
    python3 - "$PHOTO" <<'PY'
import sys, struct, zlib
w, h = 640, 360
rows = b""
for y in range(h):
    rows += b"\x00" + b"".join(
        bytes((int(255 * x / w), int(255 * y / h), 160)) for x in range(w))
def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(rows))
       + chunk(b"IEND", b""))
open(sys.argv[1], "wb").write(png)
PY

    # Several notifications from the same app (tests grouping by app)
    send "Mail" mail-unread "Anna: Dinner tomorrow?" "Hi! Are we still on for dinner tomorrow evening? I booked a table at 20:00."
    send "Mail" mail-unread "Newsletter" "Your weekly digest is here."
    send "Mail" mail-unread "Invoice #1042" "Your invoice for November is ready."

    # Other apps
    send "Calendar" appointment-soon "Meeting in 10 minutes" "Team sync, room 4"

    # Critical / low urgency
    send "System Updates" system-software-update "Security update available" "Please restart soon to finish installing updates." "[]" "{'urgency': <byte 2>}"
    send "Backup" drive-harddisk "Backup completed" "Last backup: just now" "[]" "{'urgency': <byte 0>}"

    # Clickable links: markup link plus a plain URL (the panel auto-links plain URLs)
    send "Browser" internet-web-browser "Download finished" \
      "Read the <a href=\"https://kde.org/plasma-desktop/\">Plasma release notes</a> or visit https://kde.org"

    # Long body (tests "Show more")
    send "Notes" accessories-text-editor "Long note" "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

    # Real photo: shown both as the notification image and as a preview via attached file
    send "Gallery" folder-pictures "New photo" "Sunset at the beach" "[]" \
      "{'image-path': <'$PHOTO'>, 'x-kde-urls': <['file://$PHOTO']>}"

    # Screenshot-style notification with an attached file (preview + open button)
    send "Spectacle" spectacle "Screenshot taken" "Saved to /tmp" "[]" \
      "{'x-kde-urls': <['file://$PHOTO']>}"

    # Action buttons (default action = click on the card)
    send "Chat" dialog-information "Bob" "Want to grab lunch?" \
      "['default', 'Open', 'mute', 'Mute']" "{}"

    # Inline reply field
    send "Chat" dialog-messages "Carol" "Are you coming tonight?" \
      "['inline-reply', 'Reply']" "{'x-kde-reply-placeholder-text': <'Write a reply…'>}"

    echo "Sent 12 test notifications (photo at $PHOTO)."
}

# Printed after an install or update. $1 = 1 for a freshly created panel, 0 when an existing
# panel and its settings were kept.
print_note() {
    local b="" r=""
    if [[ -t 1 ]]; then b=$'\033[1m'; r=$'\033[0m'; fi
    if [[ ${1:-0} == 1 ]]; then
        cat <<NOTE

${b}Pre-selected settings${r}
  - Opens when you click the handle (or the system tray icon).
  - The panel is attached to the screen edge, with the handle on top of it.
  - The handle shows the number of unread notifications (a bell when none).
  - The handle blinks a few times when a new notification arrives.
  - Notifications are grouped by application.
  - Plasma's own pop-ups stay on.
  - A history of notifications is kept for 30 days (history button at the top
    of the panel).
  - The icons of apps with unread notifications show on the handle (up to 5, then "+N").
NOTE
    else
        cat <<NOTE

${b}Your settings were not changed.${r}
  Options added in this version start at their defaults; you can review them
  under Configure.
NOTE
    fi
    cat <<NOTE

${b}Other options${r}  (right-click the handle, then Configure)
  General  group by date, by application or not at all; lines of text
           before "Show more"; relative times; mark as read on hover;
           Plasma's pop-ups on or off (off holds them back like Do Not
           Disturb, so sounds are silenced too); keep a history on or off
           and for how many days (1-365).
  Opening  open by click only, or also by hovering (with a delay);
           close when the pointer leaves; panel as a popup next to the
           handle instead of attached to the edge; width and height;
           the system tray icon on or off.
  Handle   show the number, a bell and the number, or only a bell; count
           unread or all notifications; icons of apps with unread
           notifications (and how many); custom colours; blink never,
           a few times, or until you open the panel.
  Readme   a short description of the app and of every option.
  Also     right-click the handle or the tray icon for Do Not Disturb and
           Clear All. In the panel: search (Ctrl+F), timed Do Not Disturb,
           swipe a notification sideways to dismiss it.

  After an install or update the settings window opens once on the Readme
  (first page), which lists what is new in this release.

  Run './install.sh' again for the menu (update, uninstall, test).
  Other edge or a wide sidebar:  ./install.sh install --edge left --mode sidebar

NOTE
}

case "$CMD" in
    install)
        install_pkg
        if (( KEEP )); then
            (( UPGRADED )) && restart_shell
            echo
            echo "A panel with the widget already exists, so it was kept as it is."
            if (( OPTS_GIVEN )); then
                echo "(--edge, --mode, --screen, --size and --length were ignored."
                echo " Use --recreate to build the panel again from scratch.)"
            fi
            print_note 0
        elif shell_running; then
            (( UPGRADED )) && restart_shell
            say "Setting up the $MODE panel on the $EDGE edge of screen $SCREEN"
            run_script_retry "$(js_remove)
$(js_create)"
            echo
            if [[ $MODE == handle ]]; then
                echo "Done. Look for the small bell handle on the $EDGE edge."
                echo "Click it to open the notification drawer."
            else
                echo "Done. Move the pointer to the $EDGE edge to reveal the sidebar."
            fi
            echo "Right-click the widget > Configure to change the opening delay and more."
            echo "A bell icon also appears in the system tray (set it to Always shown if it is hidden)."
            print_note 1
        else
            echo
            echo "The widget is installed, but the Plasma shell is not reachable from here,"
            echo "so the panel was not created. Run './install.sh' again from a terminal"
            echo "inside your Plasma session."
            print_note 1
        fi
        ;;
    update)
        install_pkg
        restart_shell
        say "Done. Your panel and settings were kept."
        print_note 0
        ;;
    uninstall)
        if shell_running; then
            say "Removing the panel and widget instances"
            run_script_retry "$(js_remove)"
        fi
        if is_installed; then
            say "Removing the widget package"
            kpackagetool6 -t Plasma/Applet -r "$ID" >/dev/null
        fi
        say "Done."
        ;;
    test)
        command -v gdbus >/dev/null || die "gdbus not found (package glib2 / libglib2.0-bin)."
        run_tests
        ;;
esac
