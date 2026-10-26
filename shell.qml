pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property bool busy: false
    property bool storeBusy: false
    property bool storeStarted: false
    property bool posted: false
    property bool showDrafts: false
    property var drafts: []
    property var pendingDraft: null
    property var storeRequest: ({})
    property string activeDraftId: ""
    property string messageText: ""
    readonly property bool working: busy || storeBusy

    function store(action, id, text) {
        if (working)
            return;
        messageText = "";
        storeRequest = {
            action: action,
            id: id || "",
            text: text || ""
        };
        storeStarted = false;
        storeBusy = true;
        storage.stdinEnabled = true;
        storage.running = true;
    }

    function storageFinished(exitCode, output, error) {
        if (!storeBusy)
            return;
        storeBusy = false;
        if (exitCode !== 0) {
            messageText = (posted ? "Published, but the saved copy could not be removed. Do not post again. " : "Stash operation failed. ") + (error.trim() || "The stash helper exited unexpectedly.");
            return;
        }
        let result;
        try {
            result = JSON.parse(output);
        } catch (error) {
            messageText = posted ? "Published, but stash cleanup could not be confirmed. Do not post again." : "Could not read the stash helper response. Your current note has not been cleared.";
            return;
        }
        drafts = result.drafts;
        if (storeRequest.action === "stash") {
            editor.text = "";
            activeDraftId = "";
            showDrafts = false;
            messageText = "Stashed. Open Drafts to continue it later.";
        } else if (storeRequest.action === "delete") {
            if (posted) {
                Qt.quit();
                return;
            }
            if (activeDraftId === storeRequest.id)
                activeDraftId = "";
        }
        Qt.callLater(() => showDrafts ? draftList.forceActiveFocus() : editor.forceActiveFocus());
    }

    function stash() {
        if (!working && !posted && !showDrafts && editor.text.trim())
            store("stash", activeDraftId, editor.text);
    }

    function toggleDrafts() {
        if (working)
            return;
        pendingDraft = null;
        showDrafts = !showDrafts;
        if (showDrafts)
            store("list");
        else
            editor.forceActiveFocus();
    }

    function resume(draft) {
        if (working || !draft)
            return;
        if (editor.text.trim() && editor.text !== draft.text) {
            pendingDraft = draft;
            Qt.callLater(() => keepNoteButton.forceActiveFocus());
            return;
        }
        restore(draft);
    }

    function restore(draft) {
        editor.text = draft.text;
        editor.cursorPosition = editor.length;
        activeDraftId = draft.id;
        pendingDraft = null;
        showDrafts = false;
        messageText = "";
        editor.forceActiveFocus();
    }

    function submit() {
        if (working || posted || showDrafts || pendingDraft || !editor.text.trim())
            return;
        messageText = "";
        busy = true;
        poster.stdinEnabled = true;
        poster.running = true;
    }

    function dismiss() {
        if (working)
            return;
        if (pendingDraft) {
            pendingDraft = null;
            Qt.callLater(() => draftList.forceActiveFocus());
        } else if (showDrafts) {
            showDrafts = false;
            editor.forceActiveFocus();
        } else {
            Qt.quit();
        }
    }

    Component.onCompleted: store("list")

    IpcHandler {
        target: "composer"

        function ping(): string {
            return "ready";
        }

        function close(): void {
            root.dismiss();
        }
    }

    Process {
        id: poster
        command: [Quickshell.env("HOME") + "/.local/bin/microblog-post", "--stdin"]

        onStarted: {
            write(editor.text);
            stdinEnabled = false;
        }
        onRunningChanged: {
            if (!running && root.busy) {
                root.busy = false;
                root.messageText = "Posting stopped. Check notifications and your blog before retrying.";
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            if (exitCode === 0 && exitStatus === 0) {
                root.posted = true;
                editor.text = "";
                if (root.activeDraftId)
                    root.store("delete", root.activeDraftId);
                else
                    Qt.quit();
            } else {
                root.messageText = "Posting failed. Your draft is still here. Check notifications and your blog before retrying.";
                editor.forceActiveFocus();
            }
        }
    }

    Process {
        id: storage
        command: [Quickshell.env("HOME") + "/.local/bin/microblog-drafts"]
        stdout: StdioCollector {
            id: storageOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: storageError
            waitForEnd: true
        }
        onStarted: {
            root.storeStarted = true;
            write(JSON.stringify(root.storeRequest));
            stdinEnabled = false;
        }
        onRunningChanged: {
            if (!running && root.storeBusy && !root.storeStarted)
                root.storageFinished(1, "", "Could not start the stash helper.");
        }
        onExited: (exitCode, exitStatus) => {
            Qt.callLater(() => root.storageFinished(exitStatus === 0 ? exitCode : 1, storageOutput.text, storageError.text));
        }
    }

    SystemPalette {
        id: colors
        colorGroup: SystemPalette.Active
    }

    PanelWindow {
        id: panel
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "microblog-compose"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: "#66000000"
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(840, panel.width - 40)
            height: Math.min(520, panel.height - 40)
            radius: 12
            color: colors.window
            border.color: colors.mid
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 12

                Label {
                    text: root.showDrafts ? "Saved drafts" : (root.activeDraftId ? "Micro.blog - resumed draft" : "Micro.blog")
                    font.pixelSize: 22
                    font.bold: true
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.showDrafts
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    TextArea {
                        id: editor
                        objectName: "editor"
                        placeholderText: "Write a note..."
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        readOnly: root.working || root.posted
                        font.pixelSize: 18
                        focus: true

                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.dismiss();
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                                root.submit();
                                event.accepted = true;
                            }
                        }

                        Component.onCompleted: forceActiveFocus()
                    }
                }

                ListView {
                    id: draftList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.showDrafts
                    enabled: !root.working && !root.pendingDraft
                    clip: true
                    spacing: 8
                    model: root.drafts

                    Keys.onReturnPressed: root.resume(root.drafts[currentIndex])
                    Keys.onEnterPressed: root.resume(root.drafts[currentIndex])
                    Keys.onDeletePressed: {
                        if (root.drafts[currentIndex])
                            root.store("delete", root.drafts[currentIndex].id);
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: root.drafts.length === 0
                        text: root.storeBusy ? "Loading..." : "No stashed drafts yet."
                    }

                    delegate: Frame {
                        id: draftRow
                        required property var modelData
                        required property int index
                        width: ListView.view.width

                        contentItem: RowLayout {
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true

                                Label {
                                    Layout.fillWidth: true
                                    text: Qt.formatDateTime(new Date(draftRow.modelData.saved), "MMM d, yyyy h:mm AP")
                                    opacity: 0.7
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: draftRow.modelData.text.split("\n")[0] || "(blank first line)"
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    font.bold: draftRow.index === draftList.currentIndex
                                }
                            }
                            Button {
                                text: "Resume"
                                onClicked: root.resume(draftRow.modelData)
                            }
                            Button {
                                text: "Delete"
                                onClicked: root.store("delete", draftRow.modelData.id)
                            }
                        }
                    }
                }

                Frame {
                    Layout.fillWidth: true
                    visible: root.pendingDraft !== null

                    contentItem: ColumnLayout {

                        Label {
                            Layout.fillWidth: true
                            text: "Replace your unfinished note? Go back and stash it first if you want to keep it."
                            wrapMode: Text.WordWrap
                        }
                        RowLayout {
                            Button {
                                id: keepNoteButton
                                text: "Go back"
                                onClicked: {
                                    root.pendingDraft = null;
                                    root.showDrafts = false;
                                    editor.forceActiveFocus();
                                }
                            }
                            Button {
                                text: "Replace note"
                                onClicked: root.restore(root.pendingDraft)
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: root.messageText.length > 0
                    text: root.messageText
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        Layout.fillWidth: true
                        text: Array.from(editor.text).length + " / ~500 characters"
                        opacity: 0.7
                    }
                    Button {
                        text: "Stash"
                        enabled: !root.working && !root.posted && !root.showDrafts && editor.text.trim().length > 0
                        onClicked: root.stash()
                    }
                    Button {
                        text: root.showDrafts ? "Back" : "Drafts (" + root.drafts.length + ")"
                        enabled: !root.working && !root.posted
                        onClicked: root.toggleDrafts()
                    }
                    Button {
                        text: "Cancel"
                        enabled: !root.working
                        onClicked: root.dismiss()
                    }
                    Button {
                        text: root.busy ? "Posting..." : "Post"
                        enabled: !root.working && !root.posted && !root.showDrafts && editor.text.trim().length > 0
                        onClicked: root.submit()
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: "Ctrl+S: stash   |   Ctrl+O: drafts   |   Ctrl+Enter: publish   |   Esc: back / discard"
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                }
            }
        }

        Shortcut {
            sequence: "Ctrl+S"
            onActivated: root.stash()
        }

        Shortcut {
            sequence: "Ctrl+O"
            onActivated: root.toggleDrafts()
        }

        Shortcut {
            sequence: "Escape"
            onActivated: root.dismiss()
        }

        Shortcut {
            sequence: "Ctrl+Return"
            onActivated: root.submit()
        }
    }
}
