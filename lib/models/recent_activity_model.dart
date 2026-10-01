import 'package:flutter/material.dart';

/// Model representing a real activity log entry for the cashier dashboard.
class RecentActivityModel {
  final String id;
  final String title;
  final String details;
  final DateTime timestamp;
  final IconData icon;
  final Color iconColor;
  final String type; // 'sale', 'held_sale', 'shift'

  const RecentActivityModel({
    required this.id,
    required this.title,
    required this.details,
    required this.timestamp,
    required this.icon,
    required this.iconColor,
    required this.type,
  });
}
