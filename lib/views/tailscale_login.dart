import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The Tailscale sign-in page, kept inside the app so the login can end where
/// it started.
///
/// The page itself does not hand control back: it stops on "Login successful"
/// and offers nothing to tap that returns here, so a browser leaves the user to
/// find their own way. Opening it here means this page can watch for that
/// landing, and the closing of the page *is* the report that the login ended.
///
/// Only the state of the node settles anything. A page that says it succeeded
/// while the node still needs a login would close onto the same "sign-in
/// required" it started from, which is why the watch is on [tailscaleStatus]
/// rather than on what the document happens to say.
class _TailscaleLoginPage extends ConsumerStatefulWidget {
  const _TailscaleLoginPage({required this.url});

  final String url;

  @override
  ConsumerState<_TailscaleLoginPage> createState() =>
      _TailscaleLoginPageState();
}

class _TailscaleLoginPageState extends ConsumerState<_TailscaleLoginPage> {
  late final WebViewController _controller;
  Timer? _settlePoll;
  var _finished = false;
  var _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
          // The login page sends the browser to the account's own console once
          // control signs the node in. That navigation is the sign the page is
          // done with; every navigation is allowed, and this only starts the
          // read that ends the flow.
          onNavigationRequest: (request) {
            if (tailscaleLoginSettled(request.url)) {
              _confirm();
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
    // Control can take a few seconds to report the node, and the page lands on
    // its own success screen in that window. Polling while this page is open
    // keeps the close from waiting on the next change the core pushes.
    _settlePoll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _readStatus(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _readStatus());
  }

  @override
  void dispose() {
    _settlePoll?.cancel();
    super.dispose();
  }

  Future<void> _readStatus() async {
    if (!mounted || _finished) {
      return;
    }
    try {
      await ref.read(tailscalesProvider.notifier).readAll();
    } catch (_) {
      // A read that fails leaves the page up, and the next tick tries again.
      return;
    }
    if (!mounted || _finished) {
      return;
    }
    if (ref.read(tailscaleStatusProvider)?.isRunning == true) {
      _finish();
    }
  }

  /// Confirms a navigation that looks like the end of the flow, since the
  /// status can lag the page by a moment.
  Future<void> _confirm() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      if (!mounted || _finished) {
        return;
      }
      if (ref.read(tailscaleStatusProvider)?.isRunning == true) {
        _finish();
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  void _finish() {
    if (_finished) {
      return;
    }
    _finished = true;
    _settlePoll?.cancel();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    // The page draws before it loads, and a white flash under a dark theme is
    // the one thing the WebView would show of its own.
    _controller.setBackgroundColor(context.colorScheme.surface);
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: AppBar(
        title: Text(appLocalizations.tailscaleLogin),
        leading: IconButton(
          icon: const GlyphIcon(AppGlyphs.close),
          tooltip: appLocalizations.close,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress / 100,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}

/// Whether a navigation left the sign-in flow, which is what control does once
/// the node is signed in.
///
/// The login page lives under `/a/`; every step of the flow stays there,
/// including the one that ends it. Landing anywhere else on the host means the
/// flow moved on, and the console the account is sent to afterwards is the
/// clearest case.
bool tailscaleLoginSettled(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority) {
    return false;
  }
  if (!uri.host.endsWith('tailscale.com')) {
    return false;
  }
  return !uri.path.startsWith('/a/');
}

/// Opens the sign-in page and reports whether the login finished, so the caller
/// can say what happened rather than leaving the user to guess.
Future<bool> showTailscaleLogin(BuildContext context, String url) async {
  final finished = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _TailscaleLoginPage(url: url),
    ),
  );
  return finished ?? false;
}
