/// 源健康状态：未知 / 最近成功 / 最近失败。
enum SourceHealthStatus { unknown, healthy, unhealthy }

/// 单源运行时健康记录（随源 JSON 持久化）。
class SourceHealth {
  SourceHealth({
    this.status = SourceHealthStatus.unknown,
    this.lastError = '',
    this.failCount = 0,
    this.lastCheckedMs,
  });

  SourceHealthStatus status;
  String lastError;
  int failCount;
  int? lastCheckedMs;

  bool get isUnhealthy => status == SourceHealthStatus.unhealthy;
  bool get isHealthy => status == SourceHealthStatus.healthy;
  bool get isDefault =>
      status == SourceHealthStatus.unknown && failCount == 0 && lastError.isEmpty;

  void markSuccess() {
    status = SourceHealthStatus.healthy;
    lastError = '';
    failCount = 0;
    lastCheckedMs = DateTime.now().millisecondsSinceEpoch;
  }

  void markFailure(Object error) {
    failCount += 1;
    var msg = error.toString();
    if (msg.length > 240) msg = '${msg.substring(0, 240)}…';
    lastError = msg;
    lastCheckedMs = DateTime.now().millisecondsSinceEpoch;
    status = SourceHealthStatus.unhealthy;
  }

  Map<String, dynamic> toJson() => {
        'status': status.name,
        if (lastError.isNotEmpty) 'lastError': lastError,
        if (failCount != 0) 'failCount': failCount,
        if (lastCheckedMs != null) 'lastCheckedMs': lastCheckedMs,
      };

  static SourceHealth fromJson(dynamic raw) {
    if (raw is! Map) return SourceHealth();
    final j = Map<String, dynamic>.from(raw);
    final name = j['status'] as String?;
    final status = SourceHealthStatus.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SourceHealthStatus.unknown,
    );
    return SourceHealth(
      status: status,
      lastError: (j['lastError'] ?? '') as String,
      failCount: (j['failCount'] is int) ? j['failCount'] as int : 0,
      lastCheckedMs: j['lastCheckedMs'] is int ? j['lastCheckedMs'] as int : null,
    );
  }
}
