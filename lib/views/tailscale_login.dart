import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Control finishes a login on a page of its own, and the node is signed in by
/// the time that page says so. The page has to be in the app rather than in an
/// external browser: a browser takes the app off screen, and the registration
/// the node is waiting on is only answered while it waits.
class TailscaleLoginView extends ConsumerStatefulWidget {
  const TailscaleLoginView({super.key, required this.url});

  final String url;

  @override
  ConsumerState<TailscaleLoginView> createState() => _TailscaleLoginViewState();
}

class _TailscaleLoginViewState extends ConsumerState<TailscaleLoginView> {
  late final WebViewController _controller;
  Timer? _poll;
  var _signedIn = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
    // The page belongs to control, so its own idea of success is not what this
    // waits for: the node saying it runs is.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
  }

  Future<void> _check() async {
    if (_signedIn || !mounted) {
      return;
    }
    try {
      await ref.read(tailscalesProvider.notifier).readAll();
    } catch (_) {
      return;
    }
    if (!mounted || _signedIn) {
      return;
    }
    final status = ref.read(tailscaleStatusProvider);
    if (status == null || !status.isRunning) {
      return;
    }
    _signedIn = true;
    _poll?.cancel();
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.appLocalizations.tailscaleLogin,
      body: WebViewWidget(controller: _controller),
    );
  }
}
