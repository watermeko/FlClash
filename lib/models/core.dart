import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/core.freezed.dart';
part 'generated/core.g.dart';

@freezed
abstract class SetupParams with _$SetupParams {
  const factory SetupParams({
    @JsonKey(name: 'selected-map') required Map<String, String> selectedMap,
    @JsonKey(name: 'test-url') required String testUrl,
    @Default(false) @JsonKey(name: 'skip-cert-verify') bool skipCertVerify,
    @JsonKey(includeIfNull: false) SetupBase? base,
    @JsonKey(includeIfNull: false) TailscaleInject? tailscale,
  }) = _SetupParams;

  factory SetupParams.fromJson(Map<String, dynamic> json) =>
      _$SetupParamsFromJson(json);
}

@freezed
abstract class SetupBase with _$SetupBase {
  const factory SetupBase({required String path, required String overlay}) =
      _SetupBase;

  factory SetupBase.fromJson(Map<String, dynamic> json) =>
      _$SetupBaseFromJson(json);
}

@freezed
abstract class ProfileBase with _$ProfileBase {
  const factory ProfileBase({
    required Map<String, dynamic> config,
    required String digest,
    @Default([]) @JsonKey(name: 'match-rules') List<String> matchRules,
    @Default(0) int proxies,
    @Default(0) @JsonKey(name: 'proxy-groups') int proxyGroups,
    @Default(0) int rules,
  }) = _ProfileBase;

  factory ProfileBase.fromJson(Map<String, dynamic> json) =>
      _$ProfileBaseFromJson(json);
}

@freezed
abstract class UpdateParams with _$UpdateParams {
  const factory UpdateParams({
    @JsonKey(toJson: _tunCoreJson) required Tun tun,
    @JsonKey(name: 'mixed-port') required int mixedPort,
    @JsonKey(name: 'allow-lan') required bool allowLan,
    @JsonKey(name: 'find-process-mode')
    required FindProcessMode findProcessMode,
    required Mode mode,
    @JsonKey(name: 'log-level') required LogLevel logLevel,
    bool? ipv6,
    @JsonKey(name: 'tcp-concurrent') bool? tcpConcurrent,
    @JsonKey(name: 'external-controller')
    required ExternalControllerStatus externalController,
    @Default('') String secret,
    @JsonKey(name: 'unified-delay') bool? unifiedDelay,
    @Default([]) List<String> authentication,
    @Default(false) @JsonKey(name: 'geo-auto-update') bool geoAutoUpdate,
    @Default(24) @JsonKey(name: 'geo-update-interval') int geoUpdateInterval,
    @Default({}) @JsonKey(name: 'geox-url') Map<String, String> geoXUrl,
    @Default(false) @JsonKey(name: 'skip-cert-verify') bool skipCertVerify,
  }) = _UpdateParams;

  factory UpdateParams.fromJson(Map<String, dynamic> json) =>
      _$UpdateParamsFromJson(json);
}

Map<String, Object?> _tunCoreJson(Tun tun) => tun.coreJson;

@freezed
abstract class VpnOptions with _$VpnOptions {
  const factory VpnOptions({
    required bool enable,
    required int port,
    required bool ipv6,
    required bool dnsHijacking,
    required AccessControlProps accessControlProps,
    required bool allowBypass,
    required bool systemProxy,
    required List<String> bypassDomain,
    required String stack,
    @Default([]) List<String> routeAddress,
    @Default(0) int mtu,
    @Default('') String congestionController,
  }) = _VpnOptions;

  factory VpnOptions.fromJson(Map<String, Object?> json) =>
      _$VpnOptionsFromJson(json);
}

extension VpnOptionsExt on VpnOptions {
  /// Only what `ServiceController.start` and `VpnService.handleStart` read.
  VpnOptions get effective {
    if (!enable) {
      return const VpnOptions(
        enable: false,
        port: 0,
        ipv6: false,
        dnsHijacking: false,
        accessControlProps: AccessControlProps(),
        allowBypass: false,
        systemProxy: false,
        bypassDomain: [],
        stack: '',
      );
    }
    final accessControl = accessControlProps;
    final accepts = accessControl.mode == AccessControlMode.acceptSelected;
    return copyWith(
      port: systemProxy ? port : 0,
      bypassDomain: systemProxy ? bypassDomain : const [],
      accessControlProps: accessControl.enable
          ? AccessControlProps(
              enable: true,
              mode: accessControl.mode,
              acceptList: accepts ? accessControl.acceptList : const [],
              rejectList: accepts ? const [] : accessControl.rejectList,
            )
          : const AccessControlProps(),
    );
  }
}

@freezed
abstract class InitParams with _$InitParams {
  const factory InitParams({
    @JsonKey(name: 'home-dir') required String homeDir,
    required int version,
  }) = _InitParams;

  factory InitParams.fromJson(Map<String, Object?> json) =>
      _$InitParamsFromJson(json);
}

@freezed
abstract class ChangeProxyParams with _$ChangeProxyParams {
  const factory ChangeProxyParams({
    @JsonKey(name: 'group-name') required String groupName,
    @JsonKey(name: 'proxy-name') required String proxyName,
  }) = _ChangeProxyParams;

  factory ChangeProxyParams.fromJson(Map<String, Object?> json) =>
      _$ChangeProxyParamsFromJson(json);
}

@freezed
abstract class ChangeProxyResult with _$ChangeProxyResult {
  const factory ChangeProxyResult({
    @Default('') String message,
    @Default(false) bool changed,
  }) = _ChangeProxyResult;

  factory ChangeProxyResult.fromJson(Map<String, Object?> json) =>
      _$ChangeProxyResultFromJson(json);
}

@freezed
abstract class RouteSnapshot with _$RouteSnapshot {
  const factory RouteSnapshot({
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
  }) = _RouteSnapshot;

  factory RouteSnapshot.fromJson(Map<String, Object?> json) =>
      _$RouteSnapshotFromJson(json);
}

/// [exit] is the Core's name for where a connection left, only compared whole.
@freezed
abstract class RouteHit with _$RouteHit {
  const factory RouteHit({
    @Default('') String host,
    @Default('') String proxy,
    @Default('') String exit,
  }) = _RouteHit;

  factory RouteHit.fromJson(Map<String, Object?> json) =>
      _$RouteHitFromJson(json);
}

@freezed
abstract class CheckRoutesParams with _$CheckRoutesParams {
  const factory CheckRoutesParams({@Default([]) List<List<RouteHit>> routes}) =
      _CheckRoutesParams;

  factory CheckRoutesParams.fromJson(Map<String, Object?> json) =>
      _$CheckRoutesParamsFromJson(json);
}

@freezed
abstract class RouteCheck with _$RouteCheck {
  const factory RouteCheck({
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<bool> held,
  }) = _RouteCheck;

  factory RouteCheck.fromJson(Map<String, Object?> json) =>
      _$RouteCheckFromJson(json);
}

/// The Tailscale node the app keeps in every profile. Absent from a setup
/// means the user turned the mesh off, and the core writes nothing.
@freezed
abstract class TailscaleInject with _$TailscaleInject {
  const factory TailscaleInject({
    required String name,
    @JsonKey(name: 'auth-key') @Default('') String authKey,
    @Default('') String hostname,
    @JsonKey(name: 'control-url') @Default('') String controlUrl,
    @JsonKey(name: 'state-dir') @Default('') String stateDir,
    @Default(false) bool ephemeral,
    @Default(true) bool udp,
    @JsonKey(name: 'accept-routes') @Default(false) bool acceptRoutes,
    @JsonKey(name: 'exit-node') @Default('') String exitNode,
    @JsonKey(name: 'exit-node-allow-lan-access')
    @Default(false)
    bool exitNodeAllowLanAccess,
    @JsonKey(name: 'magic-dns-suffix') @Default('') String magicDnsSuffix,
  }) = _TailscaleInject;

  factory TailscaleInject.fromJson(Map<String, Object?> json) =>
      _$TailscaleInjectFromJson(json);
}

@freezed
abstract class CoreEvent with _$CoreEvent {
  const factory CoreEvent({required CoreEventType type, dynamic data}) =
      _CoreEvent;

  factory CoreEvent.fromJson(Map<String, Object?> json) =>
      _$CoreEventFromJson(json);
}

@freezed
abstract class Delay with _$Delay {
  const factory Delay({required String name, required String url, int? value}) =
      _Delay;

  factory Delay.fromJson(Map<String, Object?> json) => _$DelayFromJson(json);
}

@freezed
abstract class ProbeParams with _$ProbeParams {
  const factory ProbeParams({
    required String url,
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default({}) Map<String, String> headers,
    required int timeout,
    @JsonKey(name: 'max-body') @Default(0) int maxBody,
  }) = _ProbeParams;

  factory ProbeParams.fromJson(Map<String, Object?> json) =>
      _$ProbeParamsFromJson(json);
}

@freezed
abstract class ProbeResult with _$ProbeResult {
  const factory ProbeResult({
    @JsonKey(name: 'status-code') @Default(0) int statusCode,
    @Default(0) int delay,
    @Default('') String body,
    @Default('') String url,
    @Default([]) List<String> chains,
    @Default('') String rule,
    @JsonKey(name: 'rule-payload') @Default('') String rulePayload,
    String? error,
    String? message,
  }) = _ProbeResult;

  factory ProbeResult.fromJson(Map<String, Object?> json) =>
      _$ProbeResultFromJson(json);
}

@freezed
abstract class OutboundIpParams with _$OutboundIpParams {
  const factory OutboundIpParams({
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default([]) List<String> urls,
    required int timeout,
  }) = _OutboundIpParams;

  factory OutboundIpParams.fromJson(Map<String, Object?> json) =>
      _$OutboundIpParamsFromJson(json);
}

@freezed
abstract class OutboundIpResult with _$OutboundIpResult {
  const factory OutboundIpResult({
    @Default('') String url,
    @Default('') String body,
    @Default(0) int delay,
    @Default([]) List<String> chains,
    String? error,
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<RouteHit> hits,
    @JsonKey(name: 'node-hits') @Default([]) List<RouteHit> nodeHits,
  }) = _OutboundIpResult;

  factory OutboundIpResult.fromJson(Map<String, Object?> json) =>
      _$OutboundIpResultFromJson(json);
}

@freezed
abstract class ServiceCheckParams with _$ServiceCheckParams {
  const factory ServiceCheckParams({
    @JsonKey(name: 'proxy-name') @Default('') String proxyName,
    @Default([]) List<String> names,
    required int timeout,
  }) = _ServiceCheckParams;

  factory ServiceCheckParams.fromJson(Map<String, Object?> json) =>
      _$ServiceCheckParamsFromJson(json);
}

@freezed
abstract class ServiceCheckItem with _$ServiceCheckItem {
  const factory ServiceCheckItem({
    @Default('') String name,
    @Default('') String status,
    @Default('') String region,
    @Default(0) int delay,
    @Default([]) List<String> chains,
    @JsonKey(name: 'checked-at') @Default(0) int checkedAt,
    @JsonKey(name: 'core-epoch') @Default(0) int coreEpoch,
    @JsonKey(name: 'route-version') @Default(0) int routeVersion,
    @Default([]) List<RouteHit> hits,
  }) = _ServiceCheckItem;

  factory ServiceCheckItem.fromJson(Map<String, Object?> json) =>
      _$ServiceCheckItemFromJson(json);
}

@freezed
abstract class CoreMemoryStats with _$CoreMemoryStats {
  const factory CoreMemoryStats({
    @Default(0) int rss,
    @Default(0) int heapInuse,
    @Default(0) int heapIdle,
    @Default(0) int stackInuse,
    @Default(0) int runtimeOther,
  }) = _CoreMemoryStats;

  factory CoreMemoryStats.fromJson(Map<String, Object?> json) =>
      _$CoreMemoryStatsFromJson(json);
}

extension CoreMemoryStatsExt on CoreMemoryStats {
  int get runtimeTotal => heapInuse + heapIdle + stackInuse + runtimeOther;
}

SubscriptionInfo? subscriptionInfoFormCore(Map<String, Object?>? json) {
  if (json == null) return null;
  return SubscriptionInfo(
    upload: (json['Upload'] as num?)?.toInt() ?? 0,
    download: (json['Download'] as num?)?.toInt() ?? 0,
    total: (json['Total'] as num?)?.toInt() ?? 0,
    expire: (json['Expire'] as num?)?.toInt() ?? 0,
  );
}

@freezed
abstract class ExternalProvider with _$ExternalProvider {
  const factory ExternalProvider({
    required String name,
    required String type,
    String? path,
    required int count,
    @JsonKey(name: 'subscription-info', fromJson: subscriptionInfoFormCore)
    SubscriptionInfo? subscriptionInfo,
    @JsonKey(name: 'vehicle-type') required String vehicleType,
    @JsonKey(name: 'update-at') required DateTime updateAt,
  }) = _ExternalProvider;

  factory ExternalProvider.fromJson(Map<String, Object?> json) =>
      _$ExternalProviderFromJson(json);
}

extension ExternalProviderExt on ExternalProvider {
  String get updatingKey => 'provider_$name';
}

@freezed
abstract class ProxiesData with _$ProxiesData {
  const factory ProxiesData({
    required Map<String, dynamic> proxies,
    required List<String> all,
  }) = _ProxiesData;

  factory ProxiesData.fromJson(Map<String, Object?> json) =>
      _$ProxiesDataFromJson(json);
}

/// What the core's Tailscale backend knows about one outbound, read without
/// dialing through it. [backendState] is Tailscale's own: `NoState`,
/// `NeedsLogin`, `NeedsMachineAuth`, `Stopped`, `Starting` or `Running`.
@freezed
abstract class TailscaleStatus with _$TailscaleStatus {
  const factory TailscaleStatus({
    required String name,
    @JsonKey(name: 'backend-state') required String backendState,
    @JsonKey(name: 'auth-url') @Default('') String authUrl,
    @Default('') String hostname,
    @JsonKey(name: 'dns-name') @Default('') String dnsName,
    @JsonKey(name: 'magic-dns') @Default('') String magicDns,
    @Default(false) bool online,
    @JsonKey(name: 'have-node-key') @Default(false) bool haveNodeKey,
    @JsonKey(name: 'auth-method') @Default('') String authMethod,
    @Default([]) List<String> ips,
    @Default([]) List<String> health,
    @JsonKey(name: 'exit-node') TailscalePeer? exitNode,
    @Default([]) List<TailscalePeer> peers,
  }) = _TailscaleStatus;

  factory TailscaleStatus.fromJson(Map<String, Object?> json) =>
      _$TailscaleStatusFromJson(json);
}

@freezed
abstract class TailscalePeer with _$TailscalePeer {
  const factory TailscalePeer({
    @Default('') String hostname,
    @JsonKey(name: 'dns-name') @Default('') String dnsName,
    @Default('') String os,
    @Default([]) List<String> ips,
    @Default(false) bool online,
    @JsonKey(name: 'exit-node-option') @Default(false) bool exitNodeOption,
    @JsonKey(name: 'exit-node') @Default(false) bool exitNode,
    @Default('') String relay,
    @JsonKey(name: 'cur-addr') @Default('') String curAddr,
    @JsonKey(name: 'rx-bytes') @Default(0) int rxBytes,
    @JsonKey(name: 'tx-bytes') @Default(0) int txBytes,
  }) = _TailscalePeer;

  factory TailscalePeer.fromJson(Map<String, Object?> json) =>
      _$TailscalePeerFromJson(json);
}

extension TailscaleStatusExt on TailscaleStatus {
  /// Whether the node is signed in and reachable, as opposed to a backend that
  /// is still starting or one that needs a login.
  bool get isRunning => backendState == 'Running';

  bool get needsLogin =>
      backendState == 'NeedsLogin' || backendState == 'NeedsMachineAuth';

  /// The address a peer is reached at, preferring the tailnet address.
  String? get primaryIp => ips.firstOrNull;

  /// Whether a pre-auth key signed this node in, as opposed to a browser
  /// login. Control cannot tell the two apart once the node is up, so the
  /// outbound reports which one was used instead.
  bool get signedInWithKey => authMethod == 'auth-key';

  bool get signedInWithBrowser => authMethod == 'browser';
}
