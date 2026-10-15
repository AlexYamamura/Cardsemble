import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatDate(DateTime date, {String pattern = 'yyyy-MM-dd'}) {
  return DateFormat(pattern).format(date);
}

String formatDateTime(DateTime date, {String pattern = 'yyyy-MM-dd HH:mm:ss'}) {
  return DateFormat(pattern).format(date);
}

String formatShortDate(DateTime date) {
  return DateFormat('MMM d, yyyy').format(date);
}

String formatMonthYear(DateTime date) {
  return DateFormat("MMM ''yy").format(date);
}

String formatDateRange(DateTimeRange range) {
  return '${formatShortDate(range.start)} – ${formatShortDate(range.end)}';
}

DateTime dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTimeRange monthRange(DateTime month) {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1, 0);
  final today = dateOnly(DateTime.now());
  final actualEnd = end.isAfter(today) ? today : end;
  return DateTimeRange(start: start, end: actualEnd);
}

List<DateTime> previousMonths(int count) {
  final today = dateOnly(DateTime.now());
  return List<DateTime>.generate(
    count,
    (index) => DateTime(today.year, today.month - index, 1),
    growable: false,
  );
}

DateTime? parseDate(String? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value.replaceFirst('Z', '+00:00'));
  } catch (_) {
    return null;
  }
}

int daysBetween(DateTime? a, DateTime? b) {
  if (a == null || b == null) return 999;
  final aDate = dateOnly(a);
  final bDate = dateOnly(b);
  return (aDate.difference(bDate).inDays).abs();
}

bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool isWithinRange(DateTime? date, DateTimeRange? range) {
  if (date == null || range == null) return false;
  final dateOnlyValue = dateOnly(date);
  return dateOnlyValue.compareTo(range.start) >= 0 && dateOnlyValue.compareTo(range.end) <= 0;
}