// Flutter's twin of mbui's hill-climb (src/bench, bench/README.md), itself
// a port of nanoui's hillclimb/ (github.com/justrach/nanoui, Rach Pradhan,
// MIT): the same five scenes, counts, sizes, styles and per-frame changes,
// written with ordinary Flutter widgets, and measured the same way: 30
// frames of warm-up, 300 measured, three runs per scene, the run with the
// lowest median frame kept.
//
// Every frame the scene's state changes (frame number, time += 1/120 s) and
// the scene is rebuilt from the top with setState, as mbui's view function
// runs every frame; Flutter then does what it does (diffs the widgets, lays
// out and repaints only what changed). Two extra scenes show the retained
// way a Flutter app would usually scroll: scroll_jump and list_jump build
// their rows once and only move the scroll position each frame.
//
// Per frame, timed on the UI thread with a Stopwatch (BenchBinding):
//   build   handleBeginFrame (the state change, setState) + BuildOwner.buildScope
//   layout  PipelineOwner.flushLayout
//   paint   flushCompositingBits + flushPaint (recording display lists)
//   frame   from handleBeginFrame to the end of drawFrame, which also
//           includes compositeFrame (building the layer tree and handing it
//           to the engine) and finalizeTree: mbui's "frame CPU"
// From the engine's FrameTiming: buildDuration (the UI thread's span, a
// cross-check of frame) and rasterDuration (the raster thread turning the
// layer tree into Metal commands with Impeller and submitting them: the
// counterpart of mbui's "encode CPU"). No GPU time: the engine keeps it to
// itself (Impeller's GPUTracer, in profile builds, stores Metal's
// timestamps as 32-bit floats, so on a machine up for days every frame
// reads 0 ms). Process CPU per frame is getrusage(RUSAGE_SELF) over the
// measured frames, all threads.
//
// Environment: BENCH_SCENES=text,list BENCH_FRAMES=300 BENCH_REPEAT=3
// BENCH_LABEL="…" BENCH_HISTORY=/abs/path/history.jsonl (appended to)
// BENCH_PACE=hot (frames back to back; default: at vsync); BENCH_HEAT=1
// (scripts/bench_flutter.sh kept another core busy: recorded only).

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const sceneNames = ['boxes', 'text', 'scroll', 'list', 'dashboard'];
const extraScenes = ['scroll_jump', 'list_jump'];
const warmup = 30;

// The scene's state, as in src/bench/scenes.mbt.
int frame = 0;
double time = 0;

final Stopwatch clock = Stopwatch()..start();
double nowMs() => clock.elapsedTicks * 1000.0 / clock.frequency;

void main() {
  final binding = BenchBinding();
  runApp(const BenchApp());
  binding.endOfFrame.then((_) => runAll(binding));
}

// ---------------------------------------------------------------- binding

/// The usual binding, with each frame's UI-thread phases timed, and frames
/// kept going when macOS hides or occludes the window.
class BenchBinding extends WidgetsFlutterBinding {
  /// Called at the very start of each frame, before the transient callbacks.
  void Function()? onFrameStart;

  /// Called at the end of drawFrame with build, layout, paint, composite and
  /// frame times in ms; while it is set, drawFrame is timed.
  void Function(double build, double layout, double paint, double composite, double frame)? onFrameEnd;

  double _t0 = 0;
  final lifecycle = <String>[];

  // The framework stops scheduling frames when the app is hidden (the
  // window occluded, the screen locked); the bench keeps drawing.
  @override
  bool get framesEnabled => true;

  /// Frames back to back, without vsync (BENCH_PACE=hot): each frame is
  /// run by the engine's warm-up frame path (begin and draw frame from
  /// timers, the scene rendered at once), as mbui's and nanoui's loops run
  /// theirs; the usual vsync requests are ignored meanwhile.
  bool hot = false;

  @override
  void scheduleFrame() {
    if (!hot) super.scheduleFrame();
  }

  /// Asks for the next frame: at the next vsync, or right away when hot.
  void nextFrame() {
    if (hot) {
      platformDispatcher.scheduleWarmUpFrame(
        beginFrame: () => handleBeginFrame(null),
        drawFrame: handleDrawFrame,
      );
    } else {
      scheduleFrame();
    }
  }

  @override
  void handleAppLifecycleStateChanged(AppLifecycleState state) {
    lifecycle.add(state.name);
    stdout.writeln('lifecycle: ${state.name}');
    super.handleAppLifecycleStateChanged(state);
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _t0 = nowMs();
    onFrameStart?.call();
    super.handleBeginFrame(rawTimeStamp);
  }

  // WidgetsBinding.drawFrame and RendererBinding.drawFrame, timed. (The
  // first frame, which the framework reports, goes through super.)
  @override
  void drawFrame() {
    final end = onFrameEnd;
    if (end == null) {
      super.drawFrame();
      return;
    }
    if (rootElement != null) {
      buildOwner!.buildScope(rootElement!);
    }
    final t2 = nowMs();
    rootPipelineOwner.flushLayout();
    final t3 = nowMs();
    rootPipelineOwner.flushCompositingBits();
    rootPipelineOwner.flushPaint();
    final t4 = nowMs();
    if (sendFramesToEngine) {
      for (final RenderView renderView in renderViews) {
        renderView.compositeFrame();
      }
      rootPipelineOwner.flushSemantics();
    }
    buildOwner!.finalizeTree();
    final t5 = nowMs();
    end(t2 - _t0, t3 - t2, t4 - t3, t5 - t4, t5 - _t0);
  }
}

// ----------------------------------------------------------------- scenes

const textColor = Color(0xFF1C1C1E);
const s11 = TextStyle(fontSize: 11);
const s12 = TextStyle(fontSize: 12);
const s13 = TextStyle(fontSize: 13);
const s28 = TextStyle(fontSize: 28, fontWeight: FontWeight.w700);

final hostKey = GlobalKey<SceneHostState>();

class BenchApp extends StatelessWidget {
  const BenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false, overscroll: false),
      home: ColoredBox(
        color: const Color(0xFFF2F2F7),
        child: DefaultTextStyle(
          // No family: the engine's default is the system font (SF), as
          // mbui and nanoui use.
          style: const TextStyle(fontSize: 13, color: textColor),
          child: SceneHost(key: hostKey),
        ),
      ),
    );
  }
}

class SceneHost extends StatefulWidget {
  const SceneHost({super.key});

  @override
  State<SceneHost> createState() => SceneHostState();
}

class SceneHostState extends State<SceneHost> {
  String scene = '';
  int run = 0;
  ScrollController controller = ScrollController();

  void show(String name) {
    setState(() {
      scene = name;
      run++;
      controller.dispose();
      controller = ScrollController();
    });
  }

  /// One frame's change: the state moved on, the scene rebuilt (and, for
  /// the lists, scrolled).
  void tick() {
    switch (scene) {
      case 'list':
        jump(frame * 3 % (100000 - 40) * 28.0);
        setState(() {});
      case 'list_jump':
        jump(frame * 3 % (100000 - 40) * 28.0);
      case 'scroll_jump':
        jump(scrollOffset());
      default:
        setState(() {});
    }
  }

  void jump(double to) {
    if (controller.hasClients) controller.jumpTo(to);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey(run),
      child: switch (scene) {
        'boxes' => boxes(),
        'text' => text(),
        'scroll' => scroll(),
        'scroll_jump' => scrollJump(controller),
        'list' || 'list_jump' => list(controller),
        'dashboard' => dashboard(),
        _ => const SizedBox.expand(),
      },
    );
  }
}

/// 600 rounded, shadowed boxes moving and changing color.
Widget boxes() {
  final t = time;
  return Padding(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        for (var r = 0; r < 20; r++)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              for (var col = 0; col < 30; col++) box((r * 30 + col).toDouble(), t),
            ],
          ),
      ],
    ),
  );
}

Widget box(double i, double t) {
  return Transform.translate(
    offset: Offset(0, 6 * math.sin(t * 3 + i * 0.1)),
    child: Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: hsl(fmod(t * 60 + i * 3, 360)),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
    ),
  );
}

/// 300 labels whose numbers change every frame.
Widget text() {
  return Padding(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        for (var r = 0; r < 15; r++)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              for (var col = 0; col < 20; col++)
                SizedBox(width: 40, child: Text('${(frame * 7 + (r * 20 + col) * 13) % 10000}', style: s13)),
            ],
          ),
      ],
    ),
  );
}

Widget listRow(int i) {
  return SizedBox(
    height: 28,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        spacing: 8,
        children: [
          Text('Row $i — a line of a long list', style: s13),
          const Spacer(),
          Text('${i * 7 % 100}', style: s12),
        ],
      ),
    ),
  );
}

double scrollOffset() => fmod(time * 600, 28.0 * 1000 - 640);

/// A plain column of 1000 rows, clipped, moved every frame (rebuilt every
/// frame, as mbui's view declares it every frame).
Widget scroll() {
  return ClipRect(
    child: OverflowBox(
      alignment: Alignment.topLeft,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Transform.translate(
        offset: Offset(0, -scrollOffset()),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (var i = 0; i < 1000; i++) listRow(i)],
        ),
      ),
    ),
  );
}

/// The same column in a SingleChildScrollView, built once and scrolled by
/// jumpTo every frame: how a Flutter app would usually do it.
Widget scrollJump(ScrollController c) {
  return SingleChildScrollView(
    controller: c,
    physics: const NeverScrollableScrollPhysics(),
    child: Column(children: [for (var i = 0; i < 1000; i++) listRow(i)]),
  );
}

/// A virtual list of 100 000 rows, scrolled to another row each frame.
Widget list(ScrollController c) {
  return ListView.builder(
    controller: c,
    physics: const NeverScrollableScrollPhysics(),
    itemExtent: 28,
    itemCount: 100000,
    itemBuilder: (context, i) => listRow(i),
  );
}

/// 12 cards of text, a large number and a progress bar.
Widget dashboard() {
  final t = time;
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        for (var r = 0; r < 3; r++)
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [for (var col = 0; col < 4; col++) card(r * 4 + col, t)],
          ),
      ],
    ),
  );
}

Widget card(int i, double t) {
  final v = 0.5 + 0.5 * math.sin(t * 2 + i);
  return SizedBox(
    width: 200,
    child: Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Text('Metric $i', style: s13),
            Text('${(v * 1000).toInt()}', style: s28),
            LinearProgressIndicator(
              value: v,
              minHeight: 6,
              borderRadius: const BorderRadius.all(Radius.circular(3)),
              color: const Color(0xFF0A84FF),
              backgroundColor: const Color(0xFFE0E0E5),
            ),
            Text('updated ${frame % 60}s ago', style: s11),
          ],
        ),
      ),
    ),
  );
}

double fmod(double x, double m) => x - (x / m).floorToDouble() * m;

/// nanoui's hsl: saturation 0.7, lightness 0.55.
Color hsl(double h) {
  const s = 0.7, l = 0.55;
  double f(double n) {
    final k = fmod(n + h / 30, 12);
    final a = s * math.min(l, 1 - l);
    return l - a * math.max(-1, math.min(math.min(k - 3, 9 - k), 1));
  }

  return Color.from(alpha: 1, red: f(0), green: f(8), blue: f(4));
}

// ---------------------------------------------------------------- measure

final _libc = ffi.DynamicLibrary.process();
final _getrusage = _libc.lookupFunction<ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Int64>),
    int Function(int, ffi.Pointer<ffi.Int64>)>('getrusage');
final _malloc = _libc.lookupFunction<ffi.Pointer<ffi.Int64> Function(ffi.IntPtr),
    ffi.Pointer<ffi.Int64> Function(int)>('malloc');
final ffi.Pointer<ffi.Int64> _rusage = _malloc(256);

/// The process's user + system CPU time in ms (struct rusage on Darwin
/// arm64: two struct timeval {long tv_sec; int tv_usec;} of 16 bytes).
double cpuMs() {
  _getrusage(0, _rusage);
  final i32 = _rusage.cast<ffi.Int32>();
  return (_rusage[0] + _rusage[2]) * 1000.0 + (i32[2] + i32[6]) / 1000.0;
}

double? median(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

double? p95(List<double> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  return s[s.length * 95 ~/ 100];
}

Future<Map<String, Object?>> runScene(
    BenchBinding binding, List<FrameTiming> timings, String name, int frames, bool hot) async {
  final host = hostKey.currentState!;
  host.show(name);
  frame = 0;
  time = 0;
  await binding.endOfFrame;
  await binding.endOfFrame;

  final frameMs = <double>[], build = <double>[], layout = <double>[], paint = <double>[], composite = <double>[];
  var i = 0;
  var cpu0 = 0.0, cpu1 = 0.0, wall0 = 0.0, wall1 = 0.0;
  int? fn0, fn1;
  final done = Completer<void>();
  binding.onFrameStart = () {
    if (i == warmup) {
      cpu0 = cpuMs();
      wall0 = nowMs();
    }
    frame = i;
    time = i / 120;
    host.tick();
  };
  binding.onFrameEnd = (b, l, p, c, f) {
    if (i >= warmup) {
      frameMs.add(f);
      build.add(b);
      layout.add(l);
      paint.add(p);
      composite.add(c);
      final n = binding.platformDispatcher.frameData.frameNumber;
      fn0 ??= n;
      fn1 = n;
    }
    i++;
    if (i < warmup + frames) {
      binding.nextFrame();
    } else {
      cpu1 = cpuMs();
      wall1 = nowMs();
      binding.onFrameStart = null;
      binding.onFrameEnd = null;
      binding.hot = false;
      done.complete();
    }
  };
  final timingsBefore = timings.length;
  binding.hot = hot;
  binding.nextFrame();
  await done.future.timeout(const Duration(seconds: 60), onTimeout: () {
    stdout.writeln('$name: frames stopped after $i (no vsync?)');
    exit(2);
  });
  // FrameTimings arrive in batches (every second in release builds, every
  // 100 ms in profile ones); no frame is drawn meanwhile.
  await Future<void>.delayed(const Duration(milliseconds: 1300));
  var ft = timings.skip(timingsBefore).where((t) => fn0 != null && t.frameNumber >= fn0! && t.frameNumber <= fn1!).toList();
  final matched = ft.length;
  if (matched < frames ~/ 2) {
    // Frame numbers not reported: the last frames' timings are the measured ones.
    final all = timings.skip(timingsBefore).toList();
    ft = all.sublist(math.max(0, all.length - frames));
  }
  final view = binding.platformDispatcher.views.first;
  double ms(Duration d) => d.inMicroseconds / 1000.0;
  // Back to back, the engine rasterizes only the frames its pipeline has
  // room for (a few): no raster times, and the process CPU leaves out most
  // of the raster thread's work.
  final rastered = ft.length >= frames ~/ 2;
  final cpu = (cpu1 - cpu0) / frames;
  return {
    'fw': 'flutter',
    'scene': name,
    'frames': frames,
    'frame_ms': median(frameMs),
    'frame_p95': p95(frameMs),
    'encode_ms': rastered ? median([for (final t in ft) ms(t.rasterDuration)]) : null,
    'gpu_ms': null,
    'cpu_ms': rastered ? cpu : null,
    if (!rastered) 'cpu_ui_ms': cpu,
    'ops': null,
    'build_ms': median(build),
    'layout_ms': median(layout),
    'paint_ms': median(paint),
    'composite_ms': median(composite),
    'ui_ms': rastered ? median([for (final t in ft) ms(t.buildDuration)]) : null,
    'ui_p95': rastered ? p95([for (final t in ft) ms(t.buildDuration)]) : null,
    'raster_p95': rastered ? p95([for (final t in ft) ms(t.rasterDuration)]) : null,
    'timings': ft.length,
    'timings_matched': matched,
    'fps': frames / ((wall1 - wall0) / 1000),
    'dpr': view.devicePixelRatio,
    'mode': kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug'),
    'pace': hot ? 'hot' : 'vsync',
    'heat': Platform.environment['BENCH_HEAT'] == '1',
    'mem_mb': ProcessInfo.currentRss / 1048576.0,
  };
}

String f3(Object? v) => v is num ? v.toStringAsFixed(3) : '—';

Future<void> runAll(BenchBinding binding) async {
  final env = Platform.environment;
  int envInt(String k, int d) => int.tryParse(env[k] ?? '') ?? d;
  final frames = envInt('BENCH_FRAMES', 300);
  final repeat = envInt('BENCH_REPEAT', 3);
  final label = env['BENCH_LABEL'] ?? '';
  final history = env['BENCH_HISTORY'] ?? '';
  final wanted = (env['BENCH_SCENES'] ?? '').isEmpty
      ? sceneNames
      : env['BENCH_SCENES']!.split(',').where((s) {
          final ok = sceneNames.contains(s) || extraScenes.contains(s);
          if (!ok) stdout.writeln('unknown scene: $s');
          return ok;
        }).toList();
  final timings = <FrameTiming>[];
  binding.addTimingsCallback(timings.addAll);
  final view = binding.platformDispatcher.views.first;
  final mode = kProfileMode ? 'profile' : 'release';
  final hot = env['BENCH_PACE'] == 'hot';
  stdout.writeln('\nflutter hill-climb · $frames frames after $warmup of warm-up · '
      '${view.physicalSize.width ~/ view.devicePixelRatio}×${view.physicalSize.height ~/ view.devicePixelRatio} '
      'at ${view.devicePixelRatio}x · $mode · window, ${hot ? 'frames back to back (no vsync)' : 'vsync-driven'}'
      '${env['BENCH_HEAT'] == '1' ? ', another core kept busy' : ''}\n');
  final results = <Map<String, Object?>>[];
  for (final name in wanted) {
    Map<String, Object?>? best;
    for (var rep = 0; rep < repeat; rep++) {
      final r = await runScene(binding, timings, name, frames, hot);
      stdout.writeln('flutter · $name · run ${rep + 1}/$repeat: frame ${f3(r['frame_ms'])} ms, '
          'raster ${f3(r['encode_ms'])} ms, process ${f3(r['cpu_ms'] ?? r['cpu_ui_ms'])} ms, '
          '${(r['fps'] as double).toStringAsFixed(1)} fps, '
          'timings ${r['timings']} (${r['timings_matched']} by number)');
      if (best == null || (r['frame_ms'] as double) < (best['frame_ms'] as double)) best = r;
    }
    results.add(best!);
  }
  stdout.writeln('');
  stdout.writeln('${'scene'.padRight(12)} ${'metric'.padRight(22)} ${'flutter'.padLeft(9)}');
  const rows = [
    ('frame CPU (median)', 'frame_ms'),
    ('frame CPU (p95)', 'frame_p95'),
    ('  build', 'build_ms'),
    ('  layout', 'layout_ms'),
    ('  paint', 'paint_ms'),
    ('  composite', 'composite_ms'),
    ('UI thread (engine)', 'ui_ms'),
    ('raster (encode)', 'encode_ms'),
    ('raster p95', 'raster_p95'),
    ('process CPU / frame', 'cpu_ms'),
    ('  (without raster)', 'cpu_ui_ms'),
    ('fps (vsync)', 'fps'),
    ('memory (RSS, MB)', 'mem_mb'),
  ];
  for (final r in results) {
    for (var k = 0; k < rows.length; k++) {
      stdout.writeln('${(k == 0 ? r['scene'] as String : '').padRight(12)} ${rows[k].$1.padRight(22)} '
          '${f3(r[rows[k].$2]).padLeft(9)}');
    }
    stdout.writeln('');
  }
  stdout.writeln('times in ms; lifecycle states seen: ${binding.lifecycle.join(', ')}');
  final line = jsonEncode({
    'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'label': label,
    'results': results,
  });
  if (history.isNotEmpty) {
    File(history).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } else {
    stdout.writeln(line);
  }
  await stdout.flush();
  exit(0);
}
