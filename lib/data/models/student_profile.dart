import 'package:flutter/material.dart';

/// The signed-in student.
@immutable
class StudentProfile {
  const StudentProfile({
    required this.name,
    required this.email,
    required this.program,
    required this.interests,
    required this.yearsActive,
  });

  final String name;
  final String email;

  /// Degree and semester, e.g. `Ingenieria de Sistemas - 6to semestre`.
  final String program;

  final List<String> interests;
  final int yearsActive;

  /// Initials for the avatar tile, e.g. `SA`.
  String get initials => name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}
