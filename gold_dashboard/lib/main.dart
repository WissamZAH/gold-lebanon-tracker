// Lebanon Gold Tracker — Flutter Dashboard (Steps 4 + 5 + 6)
// ============================================================
// STEP 4: fetches gold_lebanon_data.json straight from the GitHub raw URL.
// STEP 5: glassmorphism cards, trend arrow, history chart, responsive layout.
// STEP 6: professional animated experience —
//   • Living "gold dust" background: particles RISE when the signal is UP,
//     SINK when DOWN, drift sideways when NEUTRAL, and move faster the
//     higher the confidence. They scatter away from your cursor.
//   • Breathing gradient + orbiting glow orbs tinted by the signal.
//   • Shimmering title, pulsing LIVE badge, count-up prices,
//     hover-lift cards, staggered entrance, auto-refresh every 5 minutes.
//
// Run with:  flutter run -d chrome

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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

  /// % change between the last two daily closes (e.g. -0.84).
  double? get dayChangePercent {
    if (history.length < 2) return null;
    final prev = history[history.length - 2].spotUsdPerOunce;
    final last = history.last.spotUsdPerOunce;
    return (last - prev) / prev * 100;
  }

  double get high30 => history
      .skip(math.max(0, history.length - 30))
      .map((h) => h.spotUsdPerOunce)
      .reduce(math.max);

  double get low30 => history
      .skip(math.max(0, history.length - 30))
      .map((h) => h.spotUsdPerOunce)
      .reduce(math.min);
}

Future<GoldData> fetchGoldData() async {
  final response = await http.get(Uri.parse(kDataUrl));
  if (response.statusCode != 200) {
    throw Exception('Failed to load gold data (HTTP ${response.statusCode})');
  }
  return GoldData.fromJson(json.decode(response.body) as Map<String, dynamic>);
}

// ---------------------------------------------------------------------------
// Theme constants
// ---------------------------------------------------------------------------

void main() => runApp(const GoldTrackerApp());

const _gold = Color(0xFFFFD700);
const _goldSoft = Color(0xFFE8C766);
const _goldDark = Color(0xFFB8860B);
const _up = Color(0xFF4ADE80);
const _down = Color(0xFFF87171);
const _neutral = Color(0xFFFBBF24);

Color signalColor(String signal) => switch (signal) {
      'UP' => _up,
      'DOWN' => _down,
      _ => _neutral,
    };

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

// ---------------------------------------------------------------------------
// STEP 6 — Living gold-dust background
// ---------------------------------------------------------------------------

class Particle {
  final double x0, y0;     // start position (0..1)
  final double size;       // px radius
  final double speed;      // relative speed
  final double phase;      // random phase for wobble/twinkle
  final double baseOpacity;

  Particle(math.Random r)
      : x0 = r.nextDouble(),
        y0 = r.nextDouble(),
        size = 0.8 + r.nextDouble() * 2.6,
        speed = 0.35 + r.nextDouble() * 0.65,
        phase = r.nextDouble(),
        baseOpacity = 0.25 + r.nextDouble() * 0.55;
}

class GoldDustPainter extends CustomPainter {
  final Animation<double> animation; // 0..1 looping over 60 s
  final ValueNotifier<Offset?> cursor;
  final List<Particle> particles;
  final String signal;
  final double confidence;

  GoldDustPainter({
    required this.animation,
    required this.cursor,
    required this.particles,
    required this.signal,
    required this.confidence,
  }) : super(repaint: Listenable.merge([animation, cursor]));

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final w = size.width, h = size.height;
    final accent = signalColor(signal);

    // --- 1. Breathing base gradient ---------------------------------------
    final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final top = Color.lerp(const Color(0xFF0B0920), const Color(0xFF120E2E), breathe)!;
    final mid = Color.lerp(const Color(0xFF231C4F), const Color(0xFF2B2363), breathe)!;
    final bottom = Color.lerp(const Color(0xFF1A1733), const Color(0xFF211C3F), breathe)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, mid, bottom],
        ).createShader(Offset.zero & size),
    );

    // --- 2. Orbiting glow orbs (one tinted by the signal) ------------------
    final orbColors = [_goldDark, accent, const Color(0xFF5B4FCF)];
    final orbAlpha = [0.20, 0.14, 0.16];
    for (var i = 0; i < 3; i++) {
      final angle = 2 * math.pi * (t * (i + 1) * 0.5 + i / 3);
      final center = Offset(
        w * 0.5 + w * 0.38 * math.cos(angle),
        h * 0.5 + h * 0.32 * math.sin(angle * 0.85),
      );
      final radius = math.min(w, h) * (0.30 + 0.06 * math.sin(angle * 2));
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [orbColors[i].withOpacity(orbAlpha[i]), Colors.transparent],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // --- 3. Gold dust particles --------------------------------------------
    // Direction follows the trend signal; speed scales with confidence.
    final dir = switch (signal) { 'UP' => -1.0, 'DOWN' => 1.0, _ => 0.0 };
    final speedScale = 1.0 + confidence * 1.5;
    final c = cursor.value;
    final dot = Paint();

    for (final p in particles) {
      final travel = t * p.speed * speedScale * 4; // screen traversals / cycle
      double xN, yN;
      if (dir == 0) {
        // NEUTRAL: slow sideways drift with a gentle float
        xN = _wrap(p.x0 + travel * 0.25);
        yN = _wrap(p.y0 + 0.03 * math.sin(2 * math.pi * (t * 2 + p.phase)));
      } else {
        yN = _wrap(p.y0 + dir * travel * 0.25);
        xN = _wrap(p.x0 + 0.035 * math.sin(2 * math.pi * (t * 3 + p.phase)));
      }

      var px = xN * w;
      var py = yN * h;

      // Cursor interaction: dust is blown away from the pointer.
      if (c != null) {
        final dx = px - c.dx, dy = py - c.dy;
        final dist = math.sqrt(dx * dx + dy * dy);
        const radius = 130.0;
        if (dist > 0.1 && dist < radius) {
          final force = (radius - dist) / radius;
          px += dx / dist * force * 46;
          py += dy / dist * force * 46;
        }
      }

      // Twinkle
      final tw = 0.65 + 0.35 * math.sin(2 * math.pi * (t * 6 + p.phase));
      dot.color = _goldSoft.withOpacity((p.baseOpacity * tw).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(px, py), p.size, dot);

      // Soft halo on the larger flecks
      if (p.size > 2.6) {
        dot.color = _gold.withOpacity(0.10 * tw);
        canvas.drawCircle(Offset(px, py), p.size * 3, dot);
        dot.maskFilter = null;
      }
    }

    // --- 4. Vignette so content stays readable -----------------------------
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: 1.2,
          colors: [Colors.transparent, Colors.black.withOpacity(0.35)],
        ).createShader(Offset.zero & size),
    );
  }

  double _wrap(double v) => ((v % 1) + 1) % 1;

  @override
  bool shouldRepaint(GoldDustPainter old) =>
      old.signal != signal || old.confidence != confidence;
}

class AnimatedGoldBackground extends StatefulWidget {
  final String signal;
  final double confidence;
  final Widget child;
  const AnimatedGoldBackground({
    super.key,
    required this.signal,
    required this.confidence,
    required this.child,
  });

  @override
  State<AnimatedGoldBackground> createState() => _AnimatedGoldBackgroundState();
}

class _AnimatedGoldBackgroundState extends State<AnimatedGoldBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  final ValueNotifier<Offset?> _cursor = ValueNotifier(null);
  final List<Particle> _particles =
      List.generate(85, (i) => Particle(math.Random(i * 7919)));

  @override
  void dispose() {
    _controller.dispose();
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      opaque: false,
      onHover: (e) => _cursor.value = e.localPosition,
      onExit: (_) => _cursor.value = null,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                painter: GoldDustPainter(
                  animation: _controller,
                  cursor: _cursor,
                  particles: _particles,
                  signal: widget.signal,
                  confidence: widget.confidence,
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable animated building blocks
// ---------------------------------------------------------------------------

/// Frosted-glass container that lifts and glows on hover.
class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color glow;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.glow = _gold,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -6 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: widget.glow.withOpacity(_hover ? 0.22 : 0.0),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.white.withOpacity(_hover ? 0.11 : 0.07),
                border: Border.all(
                  color: _hover
                      ? widget.glow.withOpacity(0.45)
                      : Colors.white.withOpacity(0.14),
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fade + slide entrance with a per-section delay (staggered reveal).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, 0.08), end: Offset.zero)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
}

/// Animated count-up number.
class CountUpText extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;
  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// Gold sheen that sweeps across its child periodically.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final slide = _c.value * 3 - 1; // sweeps then pauses
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [_goldDark, _gold, Colors.white, _gold, _goldDark],
            stops: [
              (slide - 0.4).clamp(0.0, 1.0),
              (slide - 0.2).clamp(0.0, 1.0),
              slide.clamp(0.0, 1.0),
              (slide + 0.2).clamp(0.0, 1.0),
              (slide + 0.4).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard page (holds data, auto-refreshes)
// ---------------------------------------------------------------------------

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  GoldData? _data;
  String? _error;
  bool _loading = true;
  Timer? _autoRefresh;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-refresh the data every 5 minutes — the dashboard stays live.
    _autoRefresh = Timer.periodic(const Duration(minutes: 5), (_) => _load(silent: true));
    // Re-render "updated X ago" every 30 seconds.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await fetchGoldData();
      if (mounted) setState(() { _data = data; _error = null; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final signal = _data?.prediction.signal ?? 'NEUTRAL';
    final confidence = _data?.prediction.confidence ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0920),
      body: AnimatedGoldBackground(
        signal: signal,
        confidence: confidence,
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _gold))
              : _error != null
                  ? _ErrorView(error: _error!, onRetry: _load)
                  : _Dashboard(data: _data!, onRefresh: _load),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final GoldData data;
  final Future<void> Function({bool silent}) onRefresh;
  const _Dashboard({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 800;
      return RefreshIndicator(
        color: _gold,
        onRefresh: () => onRefresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: isWide ? 48 : 16, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FadeSlideIn(child: _Header(data: data, onRefresh: () => onRefresh())),
                  const SizedBox(height: 20),
                  FadeSlideIn(delayMs: 120, child: _StatsStrip(data: data, isWide: isWide)),
                  const SizedBox(height: 20),
                  FadeSlideIn(delayMs: 240, child: _SignalCard(prediction: data.prediction)),
                  const SizedBox(height: 20),
                  FadeSlideIn(delayMs: 360, child: _KaratGrid(data: data, isWide: isWide)),
                  const SizedBox(height: 20),
                  FadeSlideIn(delayMs: 480, child: _ChartCard(history: data.history)),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delayMs: 600,
                    child: Center(
                      child: Text(
                        'Trend signal is a statistical indicator, not financial advice.\n'
                        'Rate: 1 USD = ${NumberFormat('#,###').format(data.usdToLbp)} LBP',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Header with shimmer title + LIVE badge
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final GoldData data;
  final VoidCallback onRefresh;
  const _Header({required this.data, required this.onRefresh});

  String _ago() {
    final d = DateTime.now().toUtc().difference(data.lastUpdated.toUtc());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Shimmer(
          child: Icon(Icons.workspace_premium, size: 44, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Shimmer(
                child: Text('Lebanon Gold Tracker',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(height: 2),
              Text('Updated ${_ago()}',
                  style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
            ],
          ),
        ),
        const _LiveBadge(),
        const SizedBox(width: 10),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, color: _gold),
          tooltip: 'Refresh now',
        ),
      ],
    );
  }
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: _up.withOpacity(0.10),
        border: Border.all(color: _up.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _up,
                boxShadow: [BoxShadow(color: _up.withOpacity(0.8), blurRadius: 6)],
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text('LIVE',
              style: TextStyle(
                  color: _up, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats strip: spot, 24h change, 30-day high/low
// ---------------------------------------------------------------------------

class _StatsStrip extends StatelessWidget {
  final GoldData data;
  final bool isWide;
  const _StatsStrip({required this.data, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final change = data.dayChangePercent;
    final changeColor = change == null
        ? Colors.white
        : change >= 0
            ? _up
            : _down;

    final items = <Widget>[
      _Stat(
        label: 'Spot price',
        child: CountUpText(
          value: data.spotUsdPerOunce,
          format: (v) => '\$${NumberFormat('#,##0.00').format(v)}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _gold),
        ),
        sub: 'USD / troy oz',
      ),
      _Stat(
        label: 'Daily change',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (change != null)
              Icon(change >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: changeColor, size: 28),
            Text(
              change == null ? '—' : '${change.abs().toStringAsFixed(2)}%',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: changeColor),
            ),
          ],
        ),
        sub: 'vs previous close',
      ),
      _Stat(
        label: '30-day high',
        child: CountUpText(
          value: data.high30,
          format: (v) => '\$${NumberFormat('#,##0').format(v)}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        sub: 'USD / oz',
      ),
      _Stat(
        label: '30-day low',
        child: CountUpText(
          value: data.low30,
          format: (v) => '\$${NumberFormat('#,##0').format(v)}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        sub: 'USD / oz',
      ),
    ];

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: isWide
          ? Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Container(
                        width: 1, height: 44, color: Colors.white.withOpacity(0.10),
                        margin: const EdgeInsets.symmetric(horizontal: 20)),
                  Expanded(child: items[i]),
                ]
              ],
            )
          : Wrap(
              runSpacing: 16,
              children: [
                for (final item in items)
                  SizedBox(width: 160, child: item),
              ],
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final Widget child;
  final String sub;
  const _Stat({required this.label, required this.child, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Signal card with pulsing icon
// ---------------------------------------------------------------------------

class _SignalCard extends StatefulWidget {
  final Prediction prediction;
  const _SignalCard({required this.prediction});

  @override
  State<_SignalCard> createState() => _SignalCardState();
}

class _SignalCardState extends State<_SignalCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prediction;
    final color = signalColor(p.signal);
    final (icon, label) = switch (p.signal) {
      'UP' => (Icons.trending_up, 'Trending Up'),
      'DOWN' => (Icons.trending_down, 'Trending Down'),
      _ => (Icons.trending_flat, 'Neutral'),
    };

    return GlassCard(
      glow: color,
      child: Row(
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.06).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.14),
                border: Border.all(color: color.withOpacity(0.55)),
                boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 24)],
              ),
              child: Icon(icon, color: color, size: 38),
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MARKET TREND SIGNAL',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(p.reason,
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: p.confidence.clamp(0, 1)),
                          duration: const Duration(milliseconds: 1500),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 8,
                            backgroundColor: Colors.white.withOpacity(0.10),
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${(p.confidence * 100).round()}% confidence',
                        style:
                            TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
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

// ---------------------------------------------------------------------------
// Karat price cards with count-up numbers
// ---------------------------------------------------------------------------

class _KaratGrid extends StatelessWidget {
  final GoldData data;
  final bool isWide;
  const _KaratGrid({required this.data, required this.isWide});

  static const _meta = {
    '24k': ('24K', 'Pure gold — ingots & coins'),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    color: _gold.withOpacity(0.14),
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
          CountUpText(
            value: price.usdPerGram,
            format: (v) => '\$${v.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
          ),
          Text('per gram',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
          const SizedBox(height: 10),
          CountUpText(
            value: price.lbpPerGram.toDouble(),
            format: (v) => '${NumberFormat('#,###').format(v)} LBP/g',
            style: const TextStyle(color: _gold, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History chart
// ---------------------------------------------------------------------------

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
    final minY = history.map((h) => h.spotUsdPerOunce).reduce(math.min);
    final maxY = history.map((h) => h.spotUsdPerOunce).reduce(math.max);
    final pad = (maxY - minY) * 0.1 + 1;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: _gold, size: 20),
              const SizedBox(width: 8),
              Text('Spot price — last ${history.length} days (USD/oz)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 280,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (context, reveal, _) => LineChart(
                LineChartData(
                  minY: minY - pad,
                  maxY: maxY + pad,
                  clipData: const FlClipData.all(),
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
                      // Reveal the line left-to-right on load
                      spots: spots.sublist(
                          0, math.max(2, (spots.length * reveal).round())),
                      isCurved: true,
                      curveSmoothness: 0.15,
                      barWidth: 2.5,
                      gradient: const LinearGradient(colors: [_goldDark, _gold]),
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [_gold.withOpacity(0.22), _gold.withOpacity(0.0)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String error;
  final Future<void> Function({bool silent}) onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: _down, size: 48),
              const SizedBox(height: 12),
              const Text('Could not load gold data',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => onRetry(),
                style: FilledButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: Colors.black),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
