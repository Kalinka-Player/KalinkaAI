import 'dart:math';

import '../enums.dart';
import '../models.dart';

/// Rearranges the digit keys of [layout], leaving everything else in place.
///
/// Only keys whose text is a single digit `0` to `9` take part. Action keys,
/// the decimal point, and any other character stay exactly where they are, so
/// backspace does not wander and the grid keeps its shape.
///
/// The digits are collected in reading order, permuted, and written back into
/// the same slots. That means the set of digits on screen is always the full
/// original set: shuffling can never drop or duplicate one.
///
/// [random] is injected so the behaviour is testable; production callers let it
/// default.
KeyboardLayout shuffleDigitKeys(KeyboardLayout layout, {Random? random}) {
  final rng = random ?? Random();

  // Where the digits live, in reading order.
  final slots = <(int, int)>[];
  final digits = <VirtualKey>[];
  for (var r = 0; r < layout.length; r++) {
    for (var c = 0; c < layout[r].length; c++) {
      if (_isDigitKey(layout[r][c])) {
        slots.add((r, c));
        digits.add(layout[r][c]);
      }
    }
  }
  // Nothing to do, and with one digit every permutation is the same.
  if (digits.length < 2) return layout;

  // Fisher-Yates over a copy, so the caller's layout is never mutated.
  final shuffled = List<VirtualKey>.of(digits);
  for (var i = shuffled.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }

  final out = <KeyRow>[for (final row in layout) List<VirtualKey>.of(row)];
  for (var i = 0; i < slots.length; i++) {
    final (r, c) = slots[i];
    out[r][c] = shuffled[i];
  }
  return out;
}

/// Whether [key] is a single digit character key, and so eligible to move.
bool _isDigitKey(VirtualKey key) {
  if (key.keyType != KeyType.character) return false;
  final text = key.text;
  if (text == null || text.length != 1) return false;
  final code = text.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}
