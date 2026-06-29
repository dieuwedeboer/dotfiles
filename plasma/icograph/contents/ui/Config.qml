/*
    SPDX-FileCopyrightText: 2019 Marco Martin <mart@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes

import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.faces as Faces

Kirigami.FormLayout {
    id: root

    property alias cfg_groupByTotal: groupCheckbox.checked
    property alias cfg_showIcon: showIconCheckbox.checked
    property string cfg_customIcon
    property alias cfg_showBarChart: showBarChartCheckbox.checked
    property alias cfg_rangeAuto: rangeAutoCheckbox.checked
    property alias cfg_rangeFrom: rangeFromSpin.value
    property alias cfg_rangeFromUnit: rangeFromSpin.unit
    property alias cfg_rangeFromMultiplier: rangeFromSpin.multiplier
    property alias cfg_rangeTo: rangeToSpin.value
    property alias cfg_rangeToUnit: rangeToSpin.unit
    property alias cfg_rangeToMultiplier: rangeToSpin.multiplier

    KIconThemes.IconDialog {
        id: iconDialog
        onIconNameChanged: iconName => root.cfg_customIcon = iconName
    }

    Controls.CheckBox {
        id: showIconCheckbox
        Layout.fillWidth: true
        text: i18nc("@option:check", "Show sensor icon")
    }

    RowLayout {
        Layout.fillWidth: true

        Kirigami.FormData.label: i18nc("@label:choose", "Custom icon:")

        Controls.Button {
            id: iconButton
            Layout.minimumWidth: Kirigami.Units.iconSizes.large + Kirigami.Units.smallSpacing * 2
            Layout.maximumWidth: Layout.minimumWidth
            Layout.minimumHeight: Layout.minimumWidth
            Layout.maximumHeight: Layout.minimumWidth
            enabled: showIconCheckbox.checked

            onClicked: iconDialog.open()

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                source: root.cfg_customIcon.length > 0 ? root.cfg_customIcon : "system-monitor"
            }
        }

        Controls.Label {
            Layout.fillWidth: true
            text: root.cfg_customIcon.length > 0 ? root.cfg_customIcon : i18nc("@info:placeholder", "Auto-detect")
            elide: Text.ElideRight
        }

        Controls.Button {
            text: i18nc("@action:button", "Clear")
            icon.name: "edit-clear"
            enabled: root.cfg_customIcon.length > 0
            onClicked: root.cfg_customIcon = ""
        }
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    Controls.CheckBox {
        id: showBarChartCheckbox
        Kirigami.FormData.label: i18nc("@title:group", "Bar chart:")
        text: i18nc("@option:check", "Show bar chart")
    }

    Controls.CheckBox {
        id: rangeAutoCheckbox
        text: i18nc("@option:check", "Automatic data range")
        enabled: showBarChartCheckbox.checked
    }

    Faces.SensorRangeSpinBox {
        id: rangeFromSpin
        Kirigami.FormData.label: i18nc("@label:spinbox data range", "From:")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        enabled: showBarChartCheckbox.checked && !rangeAutoCheckbox.checked
        sensors: controller.highPrioritySensorIds
    }

    Faces.SensorRangeSpinBox {
        id: rangeToSpin
        Kirigami.FormData.label: i18nc("@label:spinbox data range", "To:")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        enabled: showBarChartCheckbox.checked && !rangeAutoCheckbox.checked
        sensors: controller.highPrioritySensorIds
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    Controls.CheckBox {
        id: groupCheckbox
        Layout.fillWidth: true
        text: i18nc("@option:check", "Group sensors based on the value of the total sensors.")
    }
}
