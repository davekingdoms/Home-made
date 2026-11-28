import 'package:homemade/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

/// The QR code of [data] on its white tile (`docs/spec/stile.md`, section
/// 8): modules [size] wide in all, dark on white in every theme, with
/// medium error correction and no image in the centre. The screen reader
/// reads it as one image called [semanticLabel].
class QrCodeBox extends StatefulWidget {
  const new({
    required this.data,
    required this.semanticLabel,
    this.size = defaultSize,
    super.key,
  });

  /// Width of the modules, without the margin of the tile.
  static const double defaultSize = 96;

  /// White margin around the modules, and radius of the tile.
  static const double margin = 8;
  static const double radius = 16;

  final String data;
  final String semanticLabel;
  final double size;

  @override
  State<QrCodeBox> createState() => _QrCodeBoxState();
}

class _QrCodeBoxState extends State<QrCodeBox> {
  /// The modules of the data, worked out once for each new data.
  late QrImage _image = _encode(widget.data);

  static QrImage _encode(String data) =>
      QrImage(QrCode(payload: QrPayload.fromString(data)));

  @override
  void didUpdateWidget(QrCodeBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _image = _encode(widget.data);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    image: true,
    label: widget.semanticLabel,
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: qrBackground,
        borderRadius: BorderRadius.circular(QrCodeBox.radius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(QrCodeBox.margin),
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _QrPainter(_image),
        ),
      ),
    ),
  );
}

/// Paints the dark modules of [image] as one path, without antialiasing:
/// no seams between modules side by side.
class _QrPainter extends CustomPainter {
  const new(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final module = size.shortestSide / count;
    final path = Path();
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (image.isDark(row, col)) {
          path.addRect(
            Rect.fromLTWH(col * module, row * module, module, module),
          );
        }
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = qrModule
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}
