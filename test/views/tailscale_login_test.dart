import 'package:fl_clash/views/tailscale_login.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page ends a login by watching where it navigated to, so what counts as
/// the end is the whole trigger. Getting it wrong either closes the page on
/// the first step of the flow or never closes it at all.
void main() {
  test('a step of the sign-in flow is not the end of it', () {
    expect(
      tailscaleLoginSettled('https://login.tailscale.com/a/eef750010c83'),
      isFalse,
    );
    expect(
      tailscaleLoginSettled('https://login.tailscale.com/a/abc123/success'),
      isFalse,
    );
  });

  test('leaving the flow for the console is the end of it', () {
    expect(
      tailscaleLoginSettled('https://login.tailscale.com/admin/machines'),
      isTrue,
    );
  });

  test('no page at all is not the end of anything', () {
    // A document that never parsed is not a navigation that finished, and
    // treating it as one would close the page on the way in.
    expect(tailscaleLoginSettled(''), isFalse);
    expect(tailscaleLoginSettled('about:blank'), isFalse);
    expect(tailscaleLoginSettled('https://example.com/a/abc'), isFalse);
  });
}
