package icu.watermeko.clash.service.models

data class NotificationParams(
    val title: String = "FlClash",
    val stopText: String = "STOP",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
)
