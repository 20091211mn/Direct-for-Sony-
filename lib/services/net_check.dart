import 'dart:io';

/// Small helpers used for the checks before sending.
class NetCheck {
  static final _ipv4 = RegExp(r'^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}$');

  static bool validIpv4(String s) => _ipv4.hasMatch(s);

  /// True when both addresses share the same /24 network (first three numbers).
  static bool sameLan(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    if (pa.length != 4 || pb.length != 4) return false;
    return pa[0] == pb[0] && pa[1] == pb[1] && pa[2] == pb[2];
  }

  /// True when the phone currently has a mobile-data interface with an address,
  /// so a proxied download could use the mobile data plan.
  static Future<bool> hasCellular() async {
    try {
      final ifaces = await NetworkInterface.list(
          includeLoopback: false, includeLinkLocal: false);
      final re = RegExp(r'^(rmnet|ccmni|pdp_ip|wwan|v4-rmnet|rev_rmnet)');
      return ifaces.any((i) => re.hasMatch(i.name) && i.addresses.isNotEmpty);
    } catch (_) {
      return false;
    }
  }
}
