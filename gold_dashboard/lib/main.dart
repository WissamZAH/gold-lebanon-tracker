// Lebanon Gold Tracker — Flutter Dashboard (Steps 4 + 5)
// =======================================================
// STEP 4: fetches gold_lebanon_data.json straight from the GitHub raw URL
//         (the repo IS the backend — no servers, no database).
// STEP 5: glassmorphism cards, animated trend arrow, historical price chart,
//         responsive desktop/mobile layout.
//
// Run with:  flutter run -d chrome

import 'dart:convert';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// STEP 4 — Data layer
// ---------------------------------------------------------------------------

const String kDataUrl =
    'https://raw.githubusercontent.com/WissamZAH/gold-lebanon-tracker/main/gold_lebanon_data.json';

class KaratPrice {
  final double usdPerGram;
  final int lbpPerGram;
  KaratPrice({required this.usdPerGram, required this.lbpPerGram});

  factory KaratPrice.fromJson(Map<String, dynamic> json) => KaratPrice(
        usdPerGram: (json['usd_per_gram'] as num).toDouble(),
        lbpPerGram: (json['lbp_per_gram'] as num).toInt(),
      );
}

class HistoryPoint {
  final DateTime date;
  final double spotUsdPerOunce;
  HistoryPoint({required this.date, required this.spotUsdPerOunce});

  factory HistoryPoint.fromJson(Map<String, dynamic> json) => HistoryPoint(
        date: DateTime.parse(json['date'] as String),
        spotUsdPerOunce: (json['spot_usd_per_ounce'] as num).toDouble(),
      );
}

class Prediction {
  final String signal; // UP / DOWN / NEUTRAL
  final double confidence;
  final String reason;
  Prediction({required this.signal, required this.confidence, required this.reason});

  factory Prediction.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return Prediction(signal: 'NEUTRAL', confidence: 0, reason: 'No prediction data.');
    }
    return Prediction(
      signal: (json['signal'] as String?) ?? 'NEUTRAL',
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      reason: (json['reason'] as String?) ?? '',
    );
  }
}

class GoldData {
  final DateTime lastUpdated;
  final double spotUsdPerOunce;
  final int usdToLbp;
  final Map<String, KaratPrice> prices;
  final List<HistoryPoint> history;
  final Prediction prediction;

  GoldData({
    required this.lastUpdated,
    required this.spotUsdPerOunce,
    required this.usdToLbp,
    required this.prices,
    required this.history,
    required this.prediction,
  });

  factory GoldData.fromJson(Map<String, dynamic> json) {
    final rawPrices = json['prices_per_gram'] as Map<String, dynamic>;
    return GoldData(
      lastUpdated: DateTime.parse(json['last_updated_utc'] as String),
      spotUsdPerOunce: (json['spot_usd_per_ounce'] as num).toDouble(),
      usdToLbp: (json['exchange_rate_usd_to_lbp'] as num).toInt(),
      prices: rawPrices.map((k, v) => MapEntry(k, KaratPrice.fromJson(v))),
      history: ((json['history'] as List?) ?? [])
          .map((e) => HistoryPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      prediction: Prediction.fromJson(json['prediction'] as Map<String, dynamic>?),
    );
  }
}

Future<GoldData> fetchGoldData() async {
  final response = await http.get(Uri.parse(kDataUrl));
  if (response.statusCode != 200) {
    throw Exception('Failed to load gold data (HTTP ${response.statusCode})');
  }
  return GoldData.fromJson(json.decode(response.body) as Map<String, dynamic>);
}

// ---------------------------------------------------------------------------
// STEP 5 — UI
// ---------------------------------------------------------------------------

void main() => runApp(const GoldTrackerApp());

const _gold = Color(0xFFFFD700);
const _goldDark = Color(0xFFB8860B);
const _bgTop = Color(0xFF0F0C29);
const _bgMid = Color(0xFF302B63);
const _bgBottom = Color(0xFF24243E);

class GoldTrackerApp extends StatelessWidget {
  const GoldTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lebanon Gold Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        colorScheme: ColorScheme.fromSeed(seedColor: _gold, brightness: Brightness.dark),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<GoldData> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchGoldData();
  }

  void _refresh() => setState(() => _future = fetchGoldData());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bgTop, _bgMid, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<GoldData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _gold));
              }
              if (snapshot.hasError) {
                return _ErrorView(error: '${snapshot.error}', onRetry: _refresh);
              }
              return _Dashboard(data: snapshot.data!, onRefresh: _refresh);
            },
          ),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final GoldData data;
  final VoidCallback onRefresh;
  const _Dashboard({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 800;
      return RefreshIndicator(
        color: _gold,
        onRefresh: () async => onRefresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: isWide ? 48 : 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(data: data, onRefresh: onRefresh),
                const SizedBox(height: 24),
                _SignalCard(prediction: data.prediction),
                const SizedBox(height: 24),
                _KaratGrid(data: data, isWide: isWide),
                const SizedBox(height: 24),
                _ChartCard(history: data.history),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Trend signal is a statistical indicator, not financial advice.\n'
                    'Rate: 1 USD = ${NumberFormat('#,###').format(data.usdToLbp)} LBP',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  final GoldData data;
  final VoidCallback onRefresh;
  const _Header({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final updated = DateFormat('d MMM y, HH:mm').format(data.lastUpdated.toLocal());
    return Row(
      children: [
        ShaderMask(
          shaderCallback: (rect) =>
              const LinearGradient(colors: [_gold, _goldDark]).createShader(rect),
          child: const Icon(Icons.monetization_on, size: 44, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Lebanon Gold Tracker',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text(
                'Spot \$${NumberFormat('#,##0.00').format(data.spotUsdPerOunce)} /oz · updated $updated',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, color: _gold),
          tooltip: 'Refresh',
        ),
      ],
    );
  }
}

/// Frosted-glass container used by every card (the glassmorphism look).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.white.withOpacity(0.08),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  final Prediction prediction;
  const _SignalCard({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (prediction.signal) {
      'UP' => (Colors.greenAccent, Icons.trending_up, 'Trending Up'),
      'DOWN' => (Colors.redAccent, Icons.trending_down, 'Trending Down'),
      _ => (Colors.amberAccent, Icons.trending_flat, 'Neutral'),
    };

    return GlassCard(
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutBack,
            builder: (context, value, child) =>
                Transform.scale(scale: value, child: child),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Icon(icon, color: color, size: 36),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Market Trend Signal',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(prediction.reason,
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: prediction.confidence.clamp(0, 1),
                          minHeight: 8,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${(prediction.confidence * 100).round()}% confidence',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KaratGrid extends StatelessWidget {
  final GoldData data;
  final bool isWide;
  const _KaratGrid({required this.data, required this.isWide});

  static const _meta = {
    '24k': ('24K', 'Pure Gold — ounces & bars'),
    '21k': ('21K', 'Lebanese jewellery standard'),
    '18k': ('18K', 'Fine jewellery'),
  };

  @override
  Widget build(BuildContext context) {
    final cards = _meta.entries.where((e) => data.prices.containsKey(e.key)).map((e) {
      final price = data.prices[e.key]!;
      return _KaratCard(
        karat: e.value.$1,
        subtitle: e.value.$2,
        price: price,
        highlight: e.key == '21k',
      );
    }).toList();

    if (isWide) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: cards[i]),
          ]
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          cards[i],
        ]
      ],
    );
  }
}

class _KaratCard extends StatelessWidget {
  final String karat;
  final String subtitle;
  final KaratPrice price;
  final bool highlight;
  const _KaratCard({
    required this.karat,
    required this.subtitle,
    required this.price,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final lbp = NumberFormat('#,###').format(price.lbpPerGram);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(karat,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold, color: _gold)),
              const Spacer(),
              if (highlight)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _gold.withOpacity(0.15),
                    border: Border.all(color: _gold.withOpacity(0.4)),
                  ),
                  child: const Text('Most traded',
                      style: TextStyle(color: _gold, fontSize: 11)),
                ),
            ],
          ),
          Text(subtitle,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          const SizedBox(height: 16),
          Text('\$${price.usdPerGram.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          Text('per gram',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          const SizedBox(height: 10),
          Text('$lbp LBP/g',
              style: const TextStyle(
                  color: _gold, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final List<HistoryPoint> history;
  const _ChartCard({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return const GlassCard(
        child: SizedBox(
          height: 120,
          child: Center(child: Text('Not enough history for a chart yet.')),
        ),
      );
    }

    final spots = [
      for (var i = 0; i < history.length; i++)
        FlSpot(i.toDouble(), history[i].spotUsdPerOunce)
    ];
    final minY = history.map((h) => h.spotUsdPerOunce).reduce((a, b) => a < b ? a : b);
    final maxY = history.map((h) => h.spotUsdPerOunce).reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.1 + 1;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spot price — last ${history.length} days (USD/oz)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          SizedBox(
            height: 260,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: Colors.white.withOpacity(0.06), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (value, meta) => Text(
                        NumberFormat('#,###').format(value),
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4), fontSize: 11),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (history.length / 5).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= history.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            DateFormat('d MMM').format(history[i].date),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.4), fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) => touched.map((t) {
                      final h = history[t.x.toInt()];
                      return LineTooltipItem(
                        '${DateFormat('d MMM y').format(h.date)}\n'
                        '\$${NumberFormat('#,##0.00').format(h.spotUsdPerOunce)}/oz',
                        const TextStyle(color: _gold, fontWeight: FontWeight.w600),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.15,
                    barWidth: 2.5,
                    color: _gold,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_gold.withOpacity(0.25), _gold.withOpacity(0.0)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text('Could not load gold data',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
