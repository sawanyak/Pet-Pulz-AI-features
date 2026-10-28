/// The verdict of a rate-limit check.
class RateDecision {
  const RateDecision.allowed() : allowed = true, retryAfter = Duration.zero;
  const RateDecision.blocked(this.retryAfter) : allowed = false;

  final bool allowed;

  /// How long until the caller may try again (for the Retry-After header).
  final Duration retryAfter;
}

/// "At most [limit] hits per [window] for each key."
///
/// A fixed window: hits are counted in consecutive slots of [window] length
/// (00:00-00:01, 00:01-00:02, ...) and the count resets when a new slot
/// starts. Simple and cheap; it can allow up to 2x [limit] around a slot
/// boundary, which is fine for cost control.
///
/// State lives in memory, so with several server instances each has its own
/// counters (use Redis or similar to share them).
class WindowLimiter {
  WindowLimiter({
    required this.limit,
    required this.window,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final int limit;
  final Duration window;
  final DateTime Function() _now;

  final Map<String, _Slot> _slots = {};
  int _hitsSincePurge = 0;

  /// Counts one hit for [key] and says whether it is allowed.
  RateDecision hit(String key) {
    final now = _now().toUtc();
    final start = _slotStart(now);
    _maybePurge(start);

    final slot = _slots[key];
    if (slot == null || slot.start != start) {
      _slots[key] = _Slot(start, 1);
      return const RateDecision.allowed();
    }
    if (slot.count >= limit) {
      return RateDecision.blocked(start.add(window).difference(now));
    }
    slot.count++;
    return const RateDecision.allowed();
  }

  /// Checks without counting (used to peek at a quota).
  int used(String key) {
    final slot = _slots[key];
    return slot != null && slot.start == _slotStart(_now().toUtc())
        ? slot.count
        : 0;
  }

  DateTime _slotStart(DateTime now) {
    final ms = now.millisecondsSinceEpoch;
    final w = window.inMilliseconds;
    return DateTime.fromMillisecondsSinceEpoch(ms - ms % w, isUtc: true);
  }

  /// Forget keys from finished slots now and then, so memory stays bounded.
  void _maybePurge(DateTime currentStart) {
    if (++_hitsSincePurge < 500) return;
    _hitsSincePurge = 0;
    _slots.removeWhere((_, s) => s.start != currentStart);
  }
}

class _Slot {
  _Slot(this.start, this.count);
  final DateTime start;
  int count;
}

/// One shared counter for the whole service, reset every UTC day.
/// This is the wallet guard: whatever else happens, the service will not
/// make more than [cap] provider calls per day.
class DailyBudget {
  DailyBudget({required this.cap, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final int cap;
  final DateTime Function() _now;

  int _day = -1;
  int _used = 0;

  int get used {
    _rollover();
    return _used;
  }

  /// Takes one unit if any is left.
  bool tryTake() {
    _rollover();
    if (_used >= cap) return false;
    _used++;
    return true;
  }

  /// Time until the budget refills (next UTC midnight).
  Duration get untilReset {
    final now = _now().toUtc();
    final next = DateTime.utc(now.year, now.month, now.day + 1);
    return next.difference(now);
  }

  void _rollover() {
    final day = _now().toUtc().millisecondsSinceEpoch ~/ 86400000;
    if (day != _day) {
      _day = day;
      _used = 0;
    }
  }
}
