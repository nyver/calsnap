import 'dart:math' as math;
import 'dart:typed_data';

/// A grayscale picture: one luma byte per pixel, row by row.
class GrayImage {
  GrayImage(this.width, this.height, this.luma)
    : assert(luma.length == width * height);

  final int width;
  final int height;
  final Uint8List luma;

  int at(int x, int y) => luma[y * width + x];
}

/// Problems that make a portion estimate less reliable. All of them are
/// advice: the user can always analyze the photo anyway.
enum PhotoIssue { blurry, tooDark, tooBright, plateCutOff, steepAngle }

/// The plate as an ellipse in pixels of the analyzed picture.
class PlateFit {
  const PlateFit({
    required this.cx,
    required this.cy,
    required this.semiMajor,
    required this.semiMinor,
    required this.angle,
  });

  final double cx;
  final double cy;
  final double semiMajor;
  final double semiMinor;

  /// Direction of the major axis in radians.
  final double angle;

  /// Minor over major axis: 1 for a plate shot straight from above, about
  /// cos(tilt) when the camera is tilted.
  double get roundness => semiMinor / semiMajor;
}

/// What the local checks found out about a photo.
class PhotoQuality {
  const PhotoQuality({
    required this.sharpness,
    required this.meanLuma,
    required this.clippedFraction,
    required this.issues,
    this.plate,
  });

  /// Laplacian variance of the sharpest tiles; higher is sharper.
  final double sharpness;

  /// Mean brightness, 0 (black) to 255 (white).
  final double meanLuma;

  /// Share of pixels that are blown out to white.
  final double clippedFraction;

  /// The plate, when one was found with confidence.
  final PlateFit? plate;

  /// Sorted by importance; empty for a good photo.
  final List<PhotoIssue> issues;

  bool get isGood => issues.isEmpty;
}

/// Thresholds of the checks.
///
/// NOTE: these are heuristics tuned on synthetic pictures, not on a labeled
/// set of meal photos, so they are deliberately lenient: a warning should mean
/// something is really off. Each value lives here to be tuned in one place.
abstract final class PhotoThresholds {
  /// Picture size the checks run on; the long side is scaled to this.
  static const int analysisSidePx = 320;

  /// Sharpness (see [PhotoQuality.sharpness]) below this is "blurry".
  static const double minSharpness = 30;

  /// Mean brightness below this is "too dark".
  static const double minMeanLuma = 45;

  /// Mean brightness above this, or too many blown-out pixels, is "too bright".
  static const double maxMeanLuma = 225;
  static const double maxClippedFraction = 0.35;

  /// A plate rounder than this is close enough to the top view (cos of about
  /// 44 degrees).
  static const double minRoundness = 0.72;

  /// The plate counts as cut off when this share of its diameter (or more)
  /// lies outside the frame.
  static const double maxOutsideShare = 0.10;
}

/// Runs the local checks. Deterministic: the same picture gives the same
/// answer. [checkPlate] is off for side photos, which are tilted on purpose.
PhotoQuality assessPhoto(GrayImage image, {bool checkPlate = true}) {
  final sharpness = _sharpness(image);
  final (mean, clipped) = _brightness(image);
  final plate = checkPlate ? detectPlate(image) : null;

  final issues = <PhotoIssue>[
    if (sharpness < PhotoThresholds.minSharpness) PhotoIssue.blurry,
    if (mean < PhotoThresholds.minMeanLuma) PhotoIssue.tooDark,
    if (mean > PhotoThresholds.maxMeanLuma ||
        clipped > PhotoThresholds.maxClippedFraction)
      PhotoIssue.tooBright,
    if (plate != null &&
        _outsideShare(plate, image) > PhotoThresholds.maxOutsideShare)
      PhotoIssue.plateCutOff,
    if (plate != null && plate.roundness < PhotoThresholds.minRoundness)
      PhotoIssue.steepAngle,
  ];
  return PhotoQuality(
    sharpness: sharpness,
    meanLuma: mean,
    clippedFraction: clipped,
    plate: plate,
    issues: issues,
  );
}

/// Variance of the Laplacian in an 8 x 8 grid; the 90th percentile of the
/// tiles. Judging the sharpest tiles rather than the whole picture keeps a
/// smooth soup or a white tablecloth from looking blurry: a sharp photo has at
/// least a few tiles with edges, a blurry one has none.
double _sharpness(GrayImage g) {
  const grid = 8;
  final w = g.width, h = g.height;
  if (w < grid * 3 || h < grid * 3) return double.infinity;
  final variances = <double>[];
  for (var ty = 0; ty < grid; ty++) {
    for (var tx = 0; tx < grid; tx++) {
      final x0 = math.max(1, tx * w ~/ grid);
      final x1 = math.min(w - 1, (tx + 1) * w ~/ grid);
      final y0 = math.max(1, ty * h ~/ grid);
      final y1 = math.min(h - 1, (ty + 1) * h ~/ grid);
      var sum = 0.0, sumSq = 0.0;
      var n = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final lap =
              4 * g.at(x, y) -
              g.at(x - 1, y) -
              g.at(x + 1, y) -
              g.at(x, y - 1) -
              g.at(x, y + 1);
          sum += lap;
          sumSq += lap * lap;
          n++;
        }
      }
      if (n == 0) continue;
      final mean = sum / n;
      variances.add(sumSq / n - mean * mean);
    }
  }
  if (variances.isEmpty) return double.infinity;
  variances.sort();
  return variances[((variances.length - 1) * 0.9).round()];
}

(double, double) _brightness(GrayImage g) {
  var sum = 0;
  var clipped = 0;
  for (final v in g.luma) {
    sum += v;
    if (v >= 250) clipped++;
  }
  final n = g.luma.length;
  return (sum / n, clipped / n);
}

/// Share of the plate diameter that lies outside the frame (0 when inside).
double _outsideShare(PlateFit p, GrayImage g) {
  final cos = math.cos(p.angle), sin = math.sin(p.angle);
  final a = p.semiMajor, b = p.semiMinor;
  final halfW = math.sqrt(a * a * cos * cos + b * b * sin * sin);
  final halfH = math.sqrt(a * a * sin * sin + b * b * cos * cos);
  final outside = [
    halfW - p.cx,
    p.cx + halfW - g.width,
    halfH - p.cy,
    p.cy + halfH - g.height,
  ].reduce(math.max);
  return math.max(0, outside) / (2 * a);
}

// ---------------------------------------------------------------------------
// Plate detection: an ellipse fitted to the picture's edges with RANSAC.
// ---------------------------------------------------------------------------

const int _detectSidePx = 160;
const int _ransacIterations = 260;
const int _maxComponents = 6;
const int _angleBins = 12;

/// Finds the most convincing ellipse of plate size, or null. Null is the
/// answer for anything doubtful (a square plate, a cluttered table, no plate):
/// the caller must not read it as "there is no plate".
PlateFit? detectPlate(GrayImage source) {
  final g = _downscale(source, _detectSidePx);
  final w = g.width, h = g.height;
  if (w < 40 || h < 40) return null;

  final edges = _edges(g);
  if (edges.length < 60) return null;
  final components = _components(edges, w, h)
    ..sort((a, b) => b.length.compareTo(a.length));
  final minComponent = math.max(30, (0.15 * math.min(w, h)).round());

  final random = math.Random(7);
  _Candidate? best;
  var tried = 0;
  for (final component in components) {
    if (component.length < minComponent || tried >= _maxComponents) break;
    tried++;
    for (var i = 0; i < _ransacIterations; i++) {
      final sample = [
        for (var k = 0; k < 5; k++)
          edges[component[random.nextInt(component.length)]],
      ];
      final model = _Ellipse.fromPoints(sample, w, h);
      if (model == null || !model.plausible) continue;
      final score = model.score(edges);
      if (score != null && (best == null || score.inliers > best.inliers)) {
        best = score;
      }
    }
  }
  if (best == null) return null;

  // Refine with all the points that agree with the winner.
  final refined = _Ellipse.fromPoints(best.support, w, h, leastSquares: true);
  final finalModel = refined != null && refined.plausible
      ? refined
      : best.model;
  final confirmed = finalModel.score(edges);
  if (confirmed == null) return null;

  final scale = source.width / w;
  return PlateFit(
    cx: finalModel.cx * scale,
    cy: finalModel.cy * scale,
    semiMajor: finalModel.a * scale,
    semiMinor: finalModel.b * scale,
    angle: finalModel.theta,
  );
}

class _Edge {
  const _Edge(this.x, this.y, this.nx, this.ny);

  final double x;
  final double y;

  /// Unit gradient direction (the edge normal).
  final double nx;
  final double ny;
}

GrayImage _downscale(GrayImage g, int longSide) {
  final scale = math.max(g.width, g.height) / longSide;
  if (scale <= 1) return g;
  final w = (g.width / scale).floor(), h = (g.height / scale).floor();
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = (y * scale).floor();
    final y1 = math.max(y0 + 1, math.min(g.height, ((y + 1) * scale).floor()));
    for (var x = 0; x < w; x++) {
      final x0 = (x * scale).floor();
      final x1 = math.max(x0 + 1, math.min(g.width, ((x + 1) * scale).floor()));
      var sum = 0;
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          sum += g.luma[yy * g.width + xx];
        }
      }
      out[y * w + x] = sum ~/ ((y1 - y0) * (x1 - x0));
    }
  }
  return GrayImage(w, h, out);
}

/// Sobel edges: pixels whose gradient is among the strongest ~9%.
List<_Edge> _edges(GrayImage g) {
  final w = g.width, h = g.height;
  final gx = Float32List(w * h), gy = Float32List(w * h);
  final mag = Float32List(w * h);
  final all = <double>[];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      int p(int dx, int dy) => g.luma[(y + dy) * w + x + dx];
      final sx =
          (p(1, -1) + 2 * p(1, 0) + p(1, 1)) -
          (p(-1, -1) + 2 * p(-1, 0) + p(-1, 1));
      final sy =
          (p(-1, 1) + 2 * p(0, 1) + p(1, 1)) -
          (p(-1, -1) + 2 * p(0, -1) + p(1, -1));
      final i = y * w + x;
      gx[i] = sx.toDouble();
      gy[i] = sy.toDouble();
      mag[i] = math.sqrt((sx * sx + sy * sy).toDouble());
      all.add(mag[i]);
    }
  }
  if (all.isEmpty) return const [];
  all.sort();
  final threshold = math.max(60.0, all[(all.length * 0.91).floor()]);
  final edges = <_Edge>[];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (mag[i] < threshold) continue;
      edges.add(
        _Edge(x.toDouble(), y.toDouble(), gx[i] / mag[i], gy[i] / mag[i]),
      );
    }
  }
  return edges;
}

/// Groups edge pixels into 8-connected components (lists of edge indices).
List<List<int>> _components(List<_Edge> edges, int w, int h) {
  final at = List<int>.filled(w * h, -1);
  for (var i = 0; i < edges.length; i++) {
    at[edges[i].y.toInt() * w + edges[i].x.toInt()] = i;
  }
  final seen = List<bool>.filled(edges.length, false);
  final result = <List<int>>[];
  for (var start = 0; start < edges.length; start++) {
    if (seen[start]) continue;
    final component = <int>[];
    final stack = [start];
    seen[start] = true;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      component.add(i);
      final x = edges[i].x.toInt(), y = edges[i].y.toInt();
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final j = at[ny * w + nx];
          if (j >= 0 && !seen[j]) {
            seen[j] = true;
            stack.add(j);
          }
        }
      }
    }
    result.add(component);
  }
  return result;
}

class _Candidate {
  const _Candidate(this.model, this.inliers, this.support);

  final _Ellipse model;
  final int inliers;
  final List<_Edge> support;
}

/// An ellipse from the conic x'Mx + d'x = 1, in coordinates centered on the
/// picture and scaled by half its long side.
class _Ellipse {
  _Ellipse._(
    this.cx,
    this.cy,
    this.a,
    this.b,
    this.theta,
    this._m,
    this._k,
    this._w,
    this._h,
    this._scale,
  );

  final double cx, cy, a, b, theta;
  final List<double> _m; // [A, B/2, C]
  final double _k;
  final int _w, _h;
  final double _scale;

  static _Ellipse? fromPoints(
    List<_Edge> points,
    int w,
    int h, {
    bool leastSquares = false,
  }) {
    if (points.length < 5) return null;
    final scale = math.max(w, h) / 2;
    final rows = [
      for (final p in points)
        () {
          final x = (p.x - w / 2) / scale, y = (p.y - h / 2) / scale;
          return [x * x, x * y, y * y, x, y];
        }(),
    ];
    final solution = leastSquares ? _solveNormal(rows) : _solve(rows);
    if (solution == null) return null;
    final [ca, cb, cc, cd, ce] = solution;

    final det = ca * cc - cb * cb / 4;
    if (ca <= 0 || det <= 1e-9) return null; // not an ellipse
    // Center: c = -1/2 M^-1 d with M = [[a, b/2], [b/2, c]].
    final centerX = -0.5 * (cc * cd - (cb / 2) * ce) / det;
    final centerY = -0.5 * (-(cb / 2) * cd + ca * ce) / det;
    // The form at the center: (p - c)'M(p - c) = k, with k = 1 - d.c / 2.
    final k = 1 - 0.5 * (cd * centerX + ce * centerY);
    if (!k.isFinite || k <= 1e-9) return null;

    final mean = (ca + cc) / 2;
    final diff = math.sqrt(
      ((ca - cc) / 2) * ((ca - cc) / 2) + (cb / 2) * (cb / 2),
    );
    final lMin = mean - diff, lMax = mean + diff;
    if (lMin <= 1e-9) return null;
    final semiMajor = math.sqrt(k / lMin), semiMinor = math.sqrt(k / lMax);
    final theta = diff < 1e-12 ? 0.0 : math.atan2(lMin - ca, cb / 2);
    return _Ellipse._(
      centerX * scale + w / 2,
      centerY * scale + h / 2,
      semiMajor * scale,
      semiMinor * scale,
      theta,
      [ca, cb / 2, cc],
      k,
      w,
      h,
      scale,
    );
  }

  /// A plate: centered in the frame, of a size that fits a meal photo, and
  /// not a needle.
  bool get plausible {
    final maxDim = math.max(_w, _h).toDouble();
    return cx > 0.2 * _w &&
        cx < 0.8 * _w &&
        cy > 0.2 * _h &&
        cy < 0.8 * _h &&
        a >= 0.18 * maxDim &&
        a <= 0.75 * maxDim &&
        b / a >= 0.3;
  }

  /// Counts the edges that lie on the ellipse and face along its normal, and
  /// requires them to cover most of the outline. Null when not convincing.
  _Candidate? score(List<_Edge> edges) {
    final support = <_Edge>[];
    final bins = List<bool>.filled(_angleBins, false);
    final cos = math.cos(theta), sin = math.sin(theta);
    for (final e in edges) {
      final px = (e.x - cx) / _scale, py = (e.y - cy) / _scale;
      final qx = _m[0] * px + _m[1] * py;
      final qy = _m[1] * px + _m[2] * py;
      final radius = math.sqrt((px * qx + py * qy) / _k);
      if ((radius - 1).abs() > 0.07) continue;
      final norm = math.sqrt(qx * qx + qy * qy);
      if (norm < 1e-9) continue;
      // The edge must run along the outline: its normal is the ellipse's.
      if (((qx * e.nx + qy * e.ny) / norm).abs() < 0.75) continue;
      support.add(e);
      final u = ((e.x - cx) * cos + (e.y - cy) * sin) / a;
      final v = (-(e.x - cx) * sin + (e.y - cy) * cos) / b;
      final bin = ((math.atan2(v, u) + math.pi) / (2 * math.pi) * _angleBins)
          .floor()
          .clamp(0, _angleBins - 1);
      bins[bin] = true;
    }
    final perimeter =
        math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b)));
    final covered = bins.where((hit) => hit).length;
    if (support.length < 0.35 * perimeter || covered < 7) return null;
    return _Candidate(this, support.length, support);
  }
}

/// Solves the 5 x 5 system rows * x = 1 for the conic coefficients.
List<double>? _solve(List<List<double>> rows) {
  final a = [
    for (final r in rows.take(5)) [...r, 1.0],
  ];
  return _gauss(a);
}

/// Least squares over any number of rows (normal equations).
List<double>? _solveNormal(List<List<double>> rows) {
  final a = List.generate(5, (_) => List<double>.filled(6, 0));
  for (final r in rows) {
    for (var i = 0; i < 5; i++) {
      for (var j = 0; j < 5; j++) {
        a[i][j] += r[i] * r[j];
      }
      a[i][5] += r[i];
    }
  }
  return _gauss(a);
}

List<double>? _gauss(List<List<double>> a) {
  const n = 5;
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    if (a[pivot][col].abs() < 1e-12) return null;
    final swap = a[col];
    a[col] = a[pivot];
    a[pivot] = swap;
    for (var r = col + 1; r < n; r++) {
      final f = a[r][col] / a[col][col];
      for (var c = col; c <= n; c++) {
        a[r][c] -= f * a[col][c];
      }
    }
  }
  final x = List<double>.filled(n, 0);
  for (var r = n - 1; r >= 0; r--) {
    var sum = a[r][n];
    for (var c = r + 1; c < n; c++) {
      sum -= a[r][c] * x[c];
    }
    x[r] = sum / a[r][r];
    if (!x[r].isFinite) return null;
  }
  return x;
}
