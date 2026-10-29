
# Gson resolves these by reflection, so their names and fields have to survive:
# SharedState, SetupParams and VpnOptions cross the service channel as JSON.
-keep class icu.watermeko.clash.models.** { *; }

-keep class icu.watermeko.clash.service.models.** { *; }
