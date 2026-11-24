import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MuseScore 3.0
import Muse.Ui

MuseScore {
    id: root

    title: "Accidental Color – Sight-Reading Assistant"
    description: "Colors notes by their displayed spelling."
    version: "1.0.1"
    thumbnailName: "AccidentalColor.png"
    pluginType: "dialog"
    requiresScore: true
    width: 510
    height: 370

    readonly property bool japanese: /^ja(?:_|-|$)/i.test(Qt.locale().name)
    readonly property string defaultSharp: "#D52E35"
    readonly property string defaultFlat: "#3478C6"
    readonly property string defaultNatural: "#000000"
    readonly property int voicesPerStaff: 4
    property bool confirmBlack: false

    Settings {
        id: settings
        category: "AccidentalColorSightReading"
    }

    function ui(ja, en) {
        return japanese ? ja : en
    }

    function validHex(value) {
        return /^#[0-9a-f]{6}$/i.test(value)
    }

    function readColor(key, fallback) {
        const value = String(settings.value(key, fallback))
        return validHex(value) ? value.toUpperCase() : fallback
    }

    function saveColors() {
        settings.setValue("sharp", sharp.text.toUpperCase())
        settings.setValue("flat", flat.text.toUpperCase())
        settings.setValue("natural", natural.text.toUpperCase())
        settings.sync()
    }

    onRun: {
        scope.currentIndex = 0
        confirmBlack = false
        status.text = ""
        sharp.text = readColor("sharp", defaultSharp)
        flat.text = readColor("flat", defaultFlat)
        natural.text = readColor("natural", defaultNatural)
    }

    function setDefaults() {
        confirmBlack = false
        sharp.text = defaultSharp
        flat.text = defaultFlat
        natural.text = defaultNatural
        saveColors()
        status.text = ui("初期配色を保存しました。", "Default colors saved.")
    }

    function addChord(notes, chord) {
        for (const note of chord.notes)
            notes.push(note)
        for (const graceChord of chord.graceNotes) {
            for (const graceNote of graceChord.notes)
                notes.push(graceNote)
        }
    }

    function selectedStaves(selection) {
        const staves = new Set()
        if (selection.isRange) {
            // staffEnd() is exclusive in the engraving selection.
            for (let i = selection.startStaff; i < selection.endStaff; ++i)
                staves.add(i)
        } else {
            for (const item of selection.elements) {
                if (item.staffIdx >= 0 && item.staffIdx < curScore.nstaves)
                    staves.add(item.staffIdx)
            }
        }
        return staves
    }

    function collectNotes(score, mode) {
        const selection = score.selection
        const notes = []
        if (mode === 0)
            mode = selection.isRange || selection.elements.length ? 2 : 1

        if (mode === 2 && !selection.isRange) {
            const elements = selection.elements
            for (const item of elements) {
                if (item.type === Element.NOTE)
                    notes.push(item)
            }
            for (const item of elements) {
                if (item.type === Element.CHORD) {
                    // A list selection can contain both the chord and its notes.
                    for (const note of item.notes) {
                        if (!notes.some(existing => existing.is(note)))
                            notes.push(note)
                    }
                }
            }
            return notes
        }

        let segment = score.firstSegment()
        let endSegment = null
        let firstTrack = 0
        let endTrack = score.ntracks
        let staves = null
        if (mode === 2) {
            segment = selection.startSegment
            endSegment = selection.endSegment
            firstTrack = selection.startStaff * voicesPerStaff
            endTrack = selection.endStaff * voicesPerStaff
        } else if (mode === 3 || mode === 4) {
            staves = selectedStaves(selection)
            if (staves.size === 0)
                return notes

            if (mode === 4) {
                const parts = Array.from(staves, index => score.staves[index].part)
                for (let i = 0; i < score.nstaves; ++i) {
                    const part = score.staves[i].part
                    if (parts.some(selected => selected.is(part)))
                        staves.add(i)
                }
            }
        }

        const tracks = []
        for (let track = firstTrack; track < endTrack; ++track) {
            if (!staves || staves.has(Math.floor(track / voicesPerStaff)))
                tracks.push(track)
        }
        while (segment && (!endSegment || !segment.is(endSegment))) {
            if (segment.segmentType === Segment.ChordRest) {
                for (const track of tracks) {
                    const chord = segment.elementAt(track)
                    if (chord && chord.type === Element.CHORD)
                        addChord(notes, chord)
                }
            }
            segment = segment.next
        }
        return notes
    }

    function setNoteColors(black) {
        confirmBlack = false
        const score = curScore
        let count = 0
        let started = false
        try {
            const notes = collectNotes(score, black ? 1 : scope.currentIndex)
            if (!notes.length) {
                status.text = ui("対象の音符がありません。", "No notes in the target scope.")
                return
            }
            if (!black)
                saveColors()

            const colors = [flat.text, natural.text, sharp.text]
            for (const note of notes) {
                // tpc uses the current concert/transposed view. F through B
                // naturals are 13–19; each accidental shifts TPC by seven.
                const tpc = black ? 13 : note.tpc
                if (!Number.isInteger(tpc) || tpc < -8 || tpc > 40)
                    continue
                const color = black ? defaultNatural : colors[Math.sign(Math.floor((tpc - 13) / 7)) + 1]
                if (Qt.colorEqual(note.color, color))
                    continue
                if (!started) {
                    score.startCmd(black ? ui("全音符を黒に戻す", "Reset all notes to black")
                                         : ui("変化音の色分け", "Color accidentals"))
                    started = true
                }
                note.color = color
                ++count
            }
            if (started) {
                score.endCmd()
                started = false
            }
            status.text = count
                ? ui("%1個の音符の色を変更しました。", "Changed %1 note colors.").arg(count)
                : ui("変更が必要な音符はありませんでした。", "No note colors needed changing.")
        } catch (error) {
            if (started)
                score.endCmd(true)
            console.warn("Accidental Color: " + error)
            status.text = ui("処理に失敗しました。", "Could not complete the operation.")
        }
    }

    component ColorInput: RowLayout {
        property alias label: caption.text
        property alias text: field.text

        Label {
            id: caption
            Layout.preferredWidth: 120
        }
        TextField {
            id: field
            Layout.preferredWidth: 120
            maximumLength: 7
            selectByMouse: true
            placeholderText: "#RRGGBB"
            Accessible.name: caption.text
        }
        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 24
            radius: 3
            color: root.validHex(field.text) ? field.text : "transparent"
            border.color: caption.color
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10

        Label { text: root.ui("処理対象", "Scope") }
        ComboBox {
            id: scope
            Layout.fillWidth: true
            model: [
                root.ui("自動（選択なしの場合は楽譜全体）", "Automatic (whole score if nothing is selected)"),
                root.ui("楽譜全体", "Whole score"),
                root.ui("選択した範囲・音符", "Selected range or notes"),
                root.ui("選択した五線の全小節", "Entire selected staves"),
                root.ui("選択したパートの全小節", "Entire selected parts")
            ]
            onActivated: root.confirmBlack = false
        }

        ColorInput { id: sharp; label: root.ui("シャープ系", "Sharps") }
        ColorInput { id: flat; label: root.ui("フラット系", "Flats") }
        ColorInput { id: natural; label: root.ui("ナチュラル", "Naturals") }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.ui("配色は #RRGGBB で入力します。実音表示を切り替えた後は再適用してください。",
                          "Enter colors as #RRGGBB. Reapply after switching concert pitch.")
        }

        Item { Layout.fillHeight: true }

        Label {
            id: status
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Button {
                text: root.ui("色分けを適用", "Apply colors")
                enabled: root.validHex(sharp.text) && root.validHex(flat.text) && root.validHex(natural.text)
                onClicked: root.setNoteColors(false)
            }
            Button {
                text: root.confirmBlack ? root.ui("全音符を黒にする", "Confirm reset")
                                        : root.ui("色分けを解除", "Reset colors")
                onClicked: {
                    if (root.confirmBlack) {
                        root.setNoteColors(true)
                    } else {
                        root.confirmBlack = true
                        status.text = root.ui("楽譜全体の音符を黒にします。既存の独自色も黒になります。",
                                              "This sets all notes to black, including previously customized notes.")
                    }
                }
            }
            Button {
                text: root.ui("初期設定に戻す", "Restore defaults")
                onClicked: root.setDefaults()
            }
            Item { Layout.fillWidth: true }
            Button {
                text: root.ui("閉じる", "Close")
                onClicked: quit()
            }
        }
    }
}
