import 'package:flutter/material.dart';

const _personPalette = [
  Color(0xFF176B5B),
  Color(0xFF4F46A5),
  Color(0xFFC2415D),
  Color(0xFF146A8A),
  Color(0xFF8A4E9B),
  Color(0xFF966000),
];

Color personColor(String personId, List<String> peopleIds) {
  final index = peopleIds.indexOf(personId);
  if (index < 0) return _personPalette.first;
  return _personPalette[index % _personPalette.length];
}

Color personColorByIndex(int index) {
  if (index < 0) return _personPalette.first;
  return _personPalette[index % _personPalette.length];
}

List<Color> get personColors => List.unmodifiable(_personPalette);