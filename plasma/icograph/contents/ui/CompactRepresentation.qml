/*
    SPDX-FileCopyrightText: 2019 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2019 David Edmundson <davidedmundson@kde.org>
    SPDX-FileCopyrightText: 2019 Arjen Hiemstra <ahiemstra@heimr.nl>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import org.kde.ksysguard.sensors as Sensors
import org.kde.ksysguard.faces as Faces
import org.kde.ksysguard.formatter as Formatter

import org.kde.quickcharts as Charts
import org.kde.quickcharts.controls as ChartsControls


Faces.CompactSensorFace {
    id: root

    function customIconString() {
        var icon = root.controller.faceConfiguration.customIcon
        if (icon === undefined || icon === null) return ""
        return icon
    }

    function showBarChartBool() {
        var val = root.controller.faceConfiguration.showBarChart
        return val === true
    }

    Layout.minimumWidth: horizontalFormFactor ? Math.max(contentItem.Layout.minimumWidth, defaultMinimumSize) : defaultMinimumSize
    Layout.minimumHeight: verticalFormFactor ? Math.max(contentItem.Layout.minimumHeight, defaultMinimumSize) : defaultMinimumSize
    Layout.preferredWidth: horizontalFormFactor ? contentItem.preferredWidth : -1
    Layout.maximumWidth: horizontalFormFactor ? Math.max(contentItem.preferredWidth, defaultMinimumSize) : -1

    FontMetrics {
        id: defaultMetrics
        font: Kirigami.Theme.defaultFont
    }

    FontMetrics {
        id: smallMetrics
        font: Kirigami.Theme.smallFont
    }

    readonly property bool useSmallFont: (horizontalFormFactor && height < defaultMetrics.lineSpacing + 2) || (verticalFormFactor && width < defaultMetrics.averageCharacterWidth * 6 + Kirigami.Units.smallSpacing)
    readonly property real lineHeight: useSmallFont ? smallMetrics.lineSpacing : defaultMetrics.lineSpacing

    function sensorIcon(sensorId) {
        var custom = customIconString()
        if (custom.length > 0) {
            return custom
        }
        if (!sensorId) return "system-monitor"
        if (sensorId.startsWith("cpu/")) return "cpu"
        if (sensorId.startsWith("memory/")) return "memory"
        if (sensorId.startsWith("gpu/")) return "gpu"
        if (sensorId.startsWith("disk/")) return "drive-harddisk"
        if (sensorId.startsWith("network/")) return "network-wired"
        if (sensorId.startsWith("temperature/")) return "temperature"
        if (sensorId.startsWith("fan/")) return "fan"
        if (sensorId.startsWith("power/")) return "power"
        return "system-monitor"
    }

    clip: true

    contentItem: GridLayout {
        id: layout

        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: 1

        flow: GridLayout.TopToBottom
        rows: root.verticalFormFactor ? -1 : Math.max(Math.floor(root.height / (root.lineHeight + rowSpacing)), 1)

        property real preferredWidth: {
            if (repeater.count == 0) {
                return 0
            }

            const columns = Math.ceil(repeater.count / rows)
            let width = 0
            for (let i = 0; i < columns; ++i) {
                width += repeater.itemAt(i).Layout.preferredWidth
            }
            width += (columns - 1) * columnSpacing
            return width
        }

        Repeater {
            id: repeater
            model: root.controller.highPrioritySensorIds

            RowLayout {
                spacing: Kirigami.Units.smallSpacing / 2

                Layout.preferredWidth: {
                    var w = 0
                    if (icon.visible) {
                        w += icon.Layout.preferredWidth + spacing
                    }
                    if (barChart.visible) {
                        w += barChart.Layout.preferredWidth + spacing
                    }
                    w += legend.Layout.preferredWidth
                    return w
                }

                Kirigami.Icon {
                    id: icon
                    visible: root.controller.faceConfiguration.showIcon
                    Layout.preferredWidth: root.useSmallFont ? Kirigami.Units.iconSizeSmall : Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Layout.preferredWidth
                    source: root.sensorIcon(modelData)
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                }

                Charts.BarChart {
                    id: barChart
                    visible: root.showBarChartBool()
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                    Layout.minimumWidth: Kirigami.Units.gridUnit
                    Layout.preferredHeight: root.lineHeight
                    Layout.alignment: Qt.AlignVCenter
                    orientation: Charts.BarChart.HorizontalOrientation
                    spacing: 0

                    Charts.ModelSource {
                        id: barValueSource
                        model: Sensors.SensorDataModel {
                            sensors: [modelData]
                            updateRateLimit: root.controller.updateRateLimit
                        }
                        roleName: "Value"
                        column: 0
                    }

                    valueSources: [barValueSource]

                    colorSource: Charts.SingleValueSource {
                        value: root.colorSource.map[modelData] !== undefined
                              ? root.colorSource.map[modelData]
                              : Kirigami.Theme.textColor
                    }

                    yRange {
                        from: root.controller.faceConfiguration.rangeFrom
                              * root.controller.faceConfiguration.rangeFromMultiplier
                        to: root.controller.faceConfiguration.rangeTo
                            * root.controller.faceConfiguration.rangeToMultiplier
                        automatic: root.controller.faceConfiguration.rangeAuto
                    }
                }

                ChartsControls.LegendDelegate {
                    id: legend
                    Layout.fillWidth: true
                    Layout.minimumWidth: root.horizontalFormFactor ? minimumWidth : Kirigami.Units.gridUnit
                    Layout.preferredWidth: root.horizontalFormFactor ? preferredWidth : minimumWidth
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                    name: root.controller.sensorLabels[modelData] || sensor.name
                    shortName: root.controller.sensorLabels[modelData] || sensor.shortName
                    value: sensor.formattedValue
                    color: root.colorSource.map[modelData]

                    font: root.useSmallFont ? Kirigami.Theme.smallFont : Kirigami.Theme.defaultFont

                    maximumValueWidth: Formatter.Formatter.maximumLength(sensor.unit, root.useSmallFont ? Kirigami.Theme.smallFont : Kirigami.Theme.defaultFont)

                    Sensors.Sensor {
                        id: sensor
                        sensorId: modelData
                        updateRateLimit: root.controller.updateRateLimit
                    }
                }
            }
        }
    }
}
