/// 全局域名黑名单：规范化裸域名 / 常见 URL，并按整域（含子域）匹配。
class DomainBlocklist {
  DomainBlocklist([Iterable<String> entries = const []]) {
    replaceAll(entries);
  }

  final List<String> _hosts = [];

  /// 已规范化、去重、稳定排序的拦截主机。
  List<String> get hosts => List.unmodifiable(_hosts);

  bool get isEmpty => _hosts.isEmpty;

  /// 解析并加入一条；非法或已存在返回 false。
  bool add(String raw) {
    final host = normalize(raw);
    if (host == null || _hosts.contains(host)) return false;
    _hosts
      ..add(host)
      ..sort();
    return true;
  }

  /// 按规范化主机删除；未命中返回 false。
  bool remove(String raw) {
    final host = normalize(raw) ?? _canonHost(raw.trim());
    if (host == null) return false;
    return _hosts.remove(host);
  }

  void replaceAll(Iterable<String> entries) {
    final next = <String>{};
    for (final raw in entries) {
      final host = normalize(raw);
      if (host != null) next.add(host);
    }
    _hosts
      ..clear()
      ..addAll(next)
      ..sort();
  }

  /// 规范化用户输入或 URL：
  /// `evil.com`、`https://evil.com/path`、`//evil.com`、`*.evil.com`、带端口/认证信息。
  /// 无法识别返回 null。
  static String? normalize(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('*.')) text = text.substring(2).trim();
    if (text.isEmpty) return null;

    final host = hostOf(text);
    if (host == null || host.isEmpty) return null;
    if (!_isValidHost(host)) return null;
    return host;
  }

  /// 从 URL / 裸域名 / 协议相对地址取出规范化主机；失败返回 null。
  static String? hostOf(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('*.')) text = text.substring(2).trim();
    if (text.isEmpty) return null;

    final parsed = Uri.tryParse(text);
    if (parsed != null && parsed.hasScheme) {
      if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
      return _canonHost(parsed.host);
    }

    if (text.startsWith('//')) {
      return _hostFromUri(Uri.tryParse('https:$text'));
    }

    final cut = text.split(RegExp(r'[/?#]')).first.trim();
    if (cut.isEmpty || cut.contains('://') || cut.contains(' ')) return null;
    return _hostFromUri(Uri.tryParse('https://$cut'));
  }

  /// [url] 命中的黑名单主机；未命中返回 null。
  String? match(String url) {
    final host = hostOf(url);
    if (host == null) return null;
    return matchHost(host);
  }

  bool matches(String url) => match(url) != null;

  /// 主机（已小写、去尾点）是否被拦截：精确匹配或对方是条目的子域。
  String? matchHost(String host) {
    final canon = _canonHost(host);
    if (canon == null) return null;
    for (final blocked in _hosts) {
      if (canon == blocked || canon.endsWith('.$blocked')) return blocked;
    }
    return null;
  }

  /// 跟随跳转链（相对 Location 按当前 URL 解析），返回首个被拦主机。
  String? matchRedirects(String url, Iterable<String> locations) {
    var current = url;
    final first = match(current);
    if (first != null) return first;
    for (final location in locations) {
      final loc = location.trim();
      if (loc.isEmpty) continue;
      final base = Uri.tryParse(current);
      current = base?.resolve(loc).toString() ?? loc;
      final hit = match(current);
      if (hit != null) return hit;
    }
    return null;
  }

  static String? _hostFromUri(Uri? uri) {
    if (uri == null) return null;
    if (uri.host.isNotEmpty) return _canonHost(uri.host);
    if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }
    return null;
  }

  static String? _canonHost(String host) {
    var h = host.trim().toLowerCase();
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    if (h.isEmpty) return null;
    return h;
  }

  static bool _isValidHost(String host) {
    if (_ipv4.hasMatch(host)) {
      return host.split('.').every((part) {
        final n = int.tryParse(part);
        return n != null && n >= 0 && n <= 255;
      });
    }
    if (host.startsWith('[') && host.endsWith(']')) {
      return host.length > 2;
    }
    return _dnsLabel.hasMatch(host);
  }

  static final _ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  static final _dnsLabel = RegExp(
    r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$',
  );
}

/// 可变网络策略：给抓取层查询 / 断言当前黑名单。
class NetworkPolicy {
  NetworkPolicy({Iterable<String> domains = const []})
    : blocklist = DomainBlocklist(domains);

  final DomainBlocklist blocklist;

  List<String> get hosts => blocklist.hosts;

  bool add(String raw) => blocklist.add(raw);

  bool remove(String raw) => blocklist.remove(raw);

  void replaceAll(Iterable<String> domains) => blocklist.replaceAll(domains);

  bool isBlocked(String url) => blocklist.matches(url);

  String? blockedHost(String url) => blocklist.match(url);

  void assertAllowed(String url) {
    final host = blocklist.match(url);
    if (host != null) {
      throw BlockedHostException(host, url: url);
    }
  }
}

/// 命中黑名单时抛出；文案可直接展示给用户。
class BlockedHostException implements Exception {
  BlockedHostException(this.host, {this.url = ''});

  final String host;
  final String url;

  String get userMessage => '域名已被屏蔽：$host';

  @override
  String toString() => 'BlockedHostException: $userMessage';
}
