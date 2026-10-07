import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../models/admin_models.dart';

/// Interactive, time-series chart displaying live revenue & transaction analytics.
class AdminRevenueChartCard extends StatefulWidget {
  final List<RevenueChartPoint> points;
  final String activePeriod;
  final ValueChanged<String> onPeriodChanged;
  final bool isLoading;

  const AdminRevenueChartCard({
    super.key,
    required this.points,
    required this.activePeriod,
    required this.onPeriodChanged,
    this.isLoading = false,
  });

  @override
  State<AdminRevenueChartCard> createState() => _AdminRevenueChartCardState();
}

class _AdminRevenueChartCardState extends State<AdminRevenueChartCard> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final double maxRevenue = widget.points.fold(
      0.0,
      (max, p) => math.max(max, p.revenue),
    );
    final double maxRevDisplay = maxRevenue > 0 ? maxRevenue : 1000.0;

    final double totalRevenuePeriod = widget.points.fold(0.0, (sum, p) => sum + p.revenue);
    final int totalTransactionsPeriod = widget.points.fold(0, (sum, p) => sum + p.transactions);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Period Selectors
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Revenue & Sales Analytics',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total Revenue: ${CurrencyFormatter.format(totalRevenuePeriod)} • $totalTransactionsPeriod Transactions',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  _buildPeriodChip('today', 'Today'),
                  _buildPeriodChip('last_7_days', 'Last 7 Days'),
                  _buildPeriodChip('last_30_days', 'Last 30 Days'),
                  _buildPeriodChip('this_month', 'This Month'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Chart Canvas / Loading State
          if (widget.isLoading)
            const SizedBox(
              height: 220,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (widget.points.isEmpty)
            const SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'No sales transaction data available for selected period.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            SizedBox(
              height: 220,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return MouseRegion(
                    onHover: (event) {
                      final width = constraints.maxWidth;
                      final count = widget.points.length;
                      if (count == 0) return;
                      final step = width / count;
                      final idx = (event.localPosition.dx / step).floor().clamp(0, count - 1);
                      if (_hoveredIndex != idx) {
                        setState(() => _hoveredIndex = idx);
                      }
                    },
                    onExit: (_) {
                      setState(() => _hoveredIndex = null);
                    },
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _RevenueChartPainter(
                        points: widget.points,
                        maxRevenue: maxRevDisplay,
                        hoveredIndex: _hoveredIndex,
                      ),
                    ),
                  );
                },
              ),
            ),

          // Hovered Detail Banner
          if (_hoveredIndex != null && _hoveredIndex! < widget.points.length) ...[
            const SizedBox(height: 12),
            _buildHoverDetails(widget.points[_hoveredIndex!]),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String value, String label) {
    final isSelected = widget.activePeriod == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : const Color(0xFF1E293B),
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF003366),
      backgroundColor: const Color(0xFFF1F5F9),
      onSelected: (_) => widget.onPeriodChanged(value),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildHoverDetails(RevenueChartPoint point) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _formatDateLabel(point.timestamp, widget.activePeriod),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Row(
            children: [
              Text(
                'Revenue: ${CurrencyFormatter.format(point.revenue)}',
                style: const TextStyle(color: Colors.lightGreenAccent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 16),
              Text(
                'Transactions: ${point.transactions}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              if (point.refunds > 0) ...[
                const SizedBox(width: 16),
                Text(
                  'Refunds: -${CurrencyFormatter.format(point.refunds)}',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateLabel(DateTime dt, String period) {
    if (period == 'today') {
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:00 $amPm';
    }
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _RevenueChartPainter extends CustomPainter {
  final List<RevenueChartPoint> points;
  final double maxRevenue;
  final int? hoveredIndex;

  _RevenueChartPainter({
    required this.points,
    required this.maxRevenue,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final double topPadding = 20.0;
    final double bottomPadding = 30.0;
    final double leftPadding = 10.0;
    final double rightPadding = 10.0;

    final double chartHeight = size.height - topPadding - bottomPadding;
    final double chartWidth = size.width - leftPadding - rightPadding;

    // Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 3; i++) {
      final y = topPadding + (chartHeight / 3) * i;
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width - rightPadding, y), gridPaint);
    }

    final count = points.length;
    final stepX = count > 1 ? chartWidth / (count - 1) : chartWidth;

    final path = Path();
    final fillPath = Path();

    final List<Offset> pointsOffsets = [];

    for (int i = 0; i < count; i++) {
      final x = leftPadding + (count > 1 ? i * stepX : chartWidth / 2);
      final normalizedValue = (points[i].revenue / maxRevenue).clamp(0.0, 1.0);
      final y = topPadding + chartHeight * (1.0 - normalizedValue);

      final offset = Offset(x, y);
      pointsOffsets.add(offset);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, topPadding + chartHeight);
        fillPath.lineTo(x, y);
      } else {
        final prev = pointsOffsets[i - 1];
        final controlX1 = prev.dx + (x - prev.dx) / 2;
        final controlY1 = prev.dy;
        final controlX2 = prev.dx + (x - prev.dx) / 2;
        final controlY2 = y;

        path.cubicTo(controlX1, controlY1, controlX2, controlY2, x, y);
        fillPath.cubicTo(controlX1, controlY1, controlX2, controlY2, x, y);
      }
    }

    fillPath.lineTo(pointsOffsets.last.dx, topPadding + chartHeight);
    fillPath.close();

    // Draw gradient fill under curve
    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF003366).withValues(alpha: 0.25),
        const Color(0xFF003366).withValues(alpha: 0.0),
      ],
    );

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(Rect.fromLTWH(0, topPadding, size.width, chartHeight));
    canvas.drawPath(fillPath, fillPaint);

    // Draw main line path
    final linePaint = Paint()
      ..color = const Color(0xFF003366)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // Draw data points & hovered highlight
    for (int i = 0; i < count; i++) {
      final offset = pointsOffsets[i];
      final isHovered = hoveredIndex == i;

      if (isHovered) {
        // Draw vertical guide line
        final guidePaint = Paint()
          ..color = const Color(0xFF003366).withValues(alpha: 0.3)
          ..strokeWidth = 1.5;
        canvas.drawLine(Offset(offset.dx, topPadding), Offset(offset.dx, topPadding + chartHeight), guidePaint);

        // Draw hover circle highlight
        final outerCircle = Paint()..color = const Color(0xFF003366).withValues(alpha: 0.2);
        canvas.drawCircle(offset, 10.0, outerCircle);

        final innerCircle = Paint()..color = const Color(0xFF003366);
        canvas.drawCircle(offset, 5.0, innerCircle);

        final whiteDot = Paint()..color = Colors.white;
        canvas.drawCircle(offset, 2.5, whiteDot);
      } else {
        final pointPaint = Paint()..color = const Color(0xFF003366);
        canvas.drawCircle(offset, 3.5, pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.maxRevenue != maxRevenue ||
        oldDelegate.hoveredIndex != hoveredIndex;
  }
}
