/// Defensive readers for API JSON.
///
/// Mappers use these instead of raw casts so an unexpected or missing field
/// produces a sane default rather than a `TypeError` thrown in the middle of a
/// widget build. Several also accept a list of aliases, which makes the client
/// tolerant of camelCase and snake_case coming from the same backend.
class Json {
  const Json._();

  static Object? _raw(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null) return value;
    }
    return null;
  }

  static String str(
    Map<String, dynamic> json,
    List<String> keys, {
    String fallback = '',
  }) => _raw(json, keys)?.toString() ?? fallback;

  static String? strOrNull(Map<String, dynamic> json, List<String> keys) {
    final value = _raw(json, keys)?.toString();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static num number(
    Map<String, dynamic> json,
    List<String> keys, {
    num fallback = 0,
  }) => numberOrNull(json, keys) ?? fallback;

  static num? numberOrNull(Map<String, dynamic> json, List<String> keys) =>
      switch (_raw(json, keys)) {
        final num value => value,
        // Money arrives as a decimal string to avoid float drift in transit.
        final String value => num.tryParse(value),
        _ => null,
      };

  static int integer(
    Map<String, dynamic> json,
    List<String> keys, {
    int fallback = 0,
  }) => integerOrNull(json, keys) ?? fallback;

  static int? integerOrNull(Map<String, dynamic> json, List<String> keys) =>
      switch (_raw(json, keys)) {
        final int value => value,
        final num value => value.toInt(),
        final String value =>
          int.tryParse(value) ?? double.tryParse(value)?.toInt(),
        _ => null,
      };

  static double decimal(
    Map<String, dynamic> json,
    List<String> keys, {
    double fallback = 0,
  }) => decimalOrNull(json, keys) ?? fallback;

  static double? decimalOrNull(Map<String, dynamic> json, List<String> keys) =>
      switch (_raw(json, keys)) {
        final num value => value.toDouble(),
        final String value => double.tryParse(value),
        _ => null,
      };

  static bool boolean(
    Map<String, dynamic> json,
    List<String> keys, {
    bool fallback = false,
  }) => switch (_raw(json, keys)) {
    final bool value => value,
    final num value => value != 0,
    final String value => value.toLowerCase() == 'true' || value == '1',
    _ => fallback,
  };

  static DateTime? date(Map<String, dynamic> json, List<String> keys) {
    final value = _raw(json, keys);
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static Map<String, dynamic> object(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final value = _raw(json, keys);
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static Map<String, dynamic>? objectOrNull(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final value = _raw(json, keys);
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  /// A list of JSON objects, skipping anything that is not a map.
  static List<Map<String, dynamic>> objects(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final value = _raw(json, keys);
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  static List<String> strings(Map<String, dynamic> json, List<String> keys) {
    final value = _raw(json, keys);
    if (value is! List) return const <String>[];
    return value.map((item) => item.toString()).toList(growable: false);
  }

  /// A flat `{name: value}` map, used for variant options and similar shapes.
  static Map<String, String> stringMap(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    final value = _raw(json, keys);
    if (value is! Map) return const <String, String>{};
    return value.map(
      (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
    );
  }

  /// Maps a decoded list into domain objects.
  static List<T> mapList<T>(
    List<Map<String, dynamic>> items,
    T Function(Map<String, dynamic> json) mapper,
  ) => items.map(mapper).toList(growable: false);
}
