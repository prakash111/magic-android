import 'package:flutter/material.dart';

class SocialProviderIcon extends StatelessWidget {
  final String provider;
  const SocialProviderIcon(this.provider, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: CustomPaint(
      painter: _ProviderPainter(
        provider,
        Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _ProviderPainter extends CustomPainter {
  final String provider;
  final Color foreground;
  const _ProviderPainter(this.provider, this.foreground);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    if (provider == 'google') {
      canvas.drawPath(
        Path()
          ..moveTo(23.001, 12.2332)
          ..cubicTo(23.001, 11.3699, 22.9296, 10.7399, 22.7748, 10.0865)
          ..lineTo(12.7153, 10.0865)
          ..lineTo(12.7153, 13.9832)
          ..lineTo(18.62, 13.9832)
          ..cubicTo(18.501, 14.9515, 17.8582, 16.4099, 16.4296, 17.3898)
          ..lineTo(16.4096, 17.5203)
          ..lineTo(19.5902, 19.935)
          ..lineTo(19.8106, 19.9565)
          ..cubicTo(21.8343, 18.1249, 23.001, 15.4298, 23.001, 12.2332)
          ..close(),
        Paint()..color = const Color(0xFF4285F4),
      );
      canvas.drawPath(
        Path()
          ..moveTo(12.714, 22.5)
          ..cubicTo(15.6068, 22.5, 18.0353, 21.5666, 19.8092, 19.9567)
          ..lineTo(16.4282, 17.3899)
          ..cubicTo(15.5235, 18.0083, 14.3092, 18.4399, 12.714, 18.4399)
          ..cubicTo(9.88069, 18.4399, 7.47596, 16.6083, 6.61874, 14.0766)
          ..lineTo(6.49309, 14.0871)
          ..lineTo(3.18583, 16.5954)
          ..lineTo(3.14258, 16.7132)
          ..cubicTo(4.90446, 20.1433, 8.5235, 22.5, 12.714, 22.5)
          ..close(),
        Paint()..color = const Color(0xFF34A853),
      );
      canvas.drawPath(
        Path()
          ..moveTo(6.62046, 14.0767)
          ..cubicTo(6.39428, 13.4234, 6.26337, 12.7233, 6.26337, 12)
          ..cubicTo(6.26337, 11.2767, 6.39428, 10.5767, 6.60856, 9.92337)
          ..lineTo(6.60257, 9.78423)
          ..lineTo(3.25386, 7.2356)
          ..lineTo(3.14429, 7.28667)
          ..cubicTo(2.41814, 8.71002, 2.00146, 10.3084, 2.00146, 12)
          ..cubicTo(2.00146, 13.6917, 2.41814, 15.29, 3.14429, 16.7133)
          ..lineTo(6.62046, 14.0767)
          ..close(),
        Paint()..color = const Color(0xFFFBBC05),
      );
      canvas.drawPath(
        Path()
          ..moveTo(12.7141, 5.55997)
          ..cubicTo(14.7259, 5.55997, 16.083, 6.41163, 16.8569, 7.12335)
          ..lineTo(19.8807, 4.23)
          ..cubicTo(18.0236, 2.53834, 15.6069, 1.5, 12.7141, 1.5)
          ..cubicTo(8.52353, 1.5, 4.90447, 3.85665, 3.14258, 7.28662)
          ..lineTo(6.60686, 9.92332)
          ..cubicTo(7.47598, 7.39166, 9.88073, 5.55997, 12.7141, 5.55997)
          ..close(),
        Paint()..color = const Color(0xFFEB4335),
      );
      return;
    }
    if (provider == 'github') {
      canvas.drawPath(
        Path()
          ..moveTo(12.0099, 0)
          ..cubicTo(5.36875, 0, 0, 5.40833, 0, 12.0992)
          ..cubicTo(0, 17.4475, 3.43994, 21.9748, 8.21205, 23.5771)
          ..cubicTo(8.80869, 23.6976, 9.02724, 23.3168, 9.02724, 22.9965)
          ..cubicTo(9.02724, 22.716, 9.00757, 21.7545, 9.00757, 20.7527)
          ..cubicTo(5.6667, 21.474, 4.97099, 19.3104, 4.97099, 19.3104)
          ..cubicTo(4.43409, 17.9082, 3.63858, 17.5478, 3.63858, 17.5478)
          ..cubicTo(2.54511, 16.8066, 3.71823, 16.8066, 3.71823, 16.8066)
          ..cubicTo(4.93117, 16.8868, 5.56763, 18.0486, 5.56763, 18.0486)
          ..cubicTo(6.64118, 19.8913, 8.37111, 19.3707, 9.06706, 19.0501)
          ..cubicTo(9.16638, 18.2688, 9.48473, 17.728, 9.82275, 17.4276)
          ..cubicTo(7.15817, 17.1471, 4.35469, 16.1055, 4.35469, 11.458)
          ..cubicTo(4.35469, 10.1359, 4.8316, 9.05428, 5.58729, 8.21304)
          ..cubicTo(5.46807, 7.91263, 5.0504, 6.67043, 5.70677, 5.00787)
          ..cubicTo(5.70677, 5.00787, 6.72083, 4.6873, 9.00732, 6.24981)
          ..cubicTo(9.98625, 5.98497, 10.9958, 5.85024, 12.0099, 5.84911)
          ..cubicTo(13.024, 5.84911, 14.0577, 5.98948, 15.0123, 6.24981)
          ..cubicTo(17.299, 4.6873, 18.3131, 5.00787, 18.3131, 5.00787)
          ..cubicTo(18.9695, 6.67043, 18.5515, 7.91263, 18.4323, 8.21304)
          ..cubicTo(19.2079, 9.05428, 19.6652, 10.1359, 19.6652, 11.458)
          ..cubicTo(19.6652, 16.1055, 16.8617, 17.1269, 14.1772, 17.4276)
          ..cubicTo(14.6148, 17.8081, 14.9924, 18.5292, 14.9924, 19.6711)
          ..cubicTo(14.9924, 21.2936, 14.9727, 22.5957, 14.9727, 22.9962)
          ..cubicTo(14.9727, 23.3168, 15.1915, 23.6976, 15.7879, 23.5774)
          ..cubicTo(20.56, 21.9745, 23.9999, 17.4475, 23.9999, 12.0992)
          ..cubicTo(24.0196, 5.40833, 18.6312, 0, 12.0099, 0)
          ..close(),
        Paint()..color = foreground,
      );
      return;
    }
    if (provider == 'facebook') {
      canvas.drawPath(
        Path()
          ..moveTo(24, 12)
          ..cubicTo(24, 5.3726, 18.6274, 2.65179e-05, 12, 2.65179e-05)
          ..cubicTo(5.37258, 2.65179e-05, 0, 5.3726, 0, 12)
          ..cubicTo(0, 17.9896, 4.38823, 22.954, 10.125, 23.8542)
          ..lineTo(10.125, 15.4688)
          ..lineTo(7.07813, 15.4688)
          ..lineTo(7.07813, 12)
          ..lineTo(10.125, 12.0)
          ..lineTo(10.125, 9.35628)
          ..cubicTo(10.125, 6.34878, 11.9165, 4.68753, 14.6576, 4.68753)
          ..cubicTo(15.9705, 4.68753, 17.3438, 4.9219, 17.3438, 4.9219)
          ..lineTo(17.3438, 7.87503)
          ..lineTo(15.8306, 7.87503)
          ..cubicTo(14.3399, 7.87503, 13.875, 8.80003, 13.875, 9.74902)
          ..lineTo(13.875, 12)
          ..lineTo(17.2031, 12.0)
          ..lineTo(16.6711, 15.4688)
          ..lineTo(13.875, 15.4688)
          ..lineTo(13.875, 23.8542)
          ..cubicTo(19.6118, 22.954, 24, 17.9896, 24, 12)
          ..close(),
        Paint()..color = const Color(0xFF1877F2),
      );
      canvas.drawPath(
        Path()
          ..moveTo(16.6711, 15.4687)
          ..lineTo(17.2031, 12)
          ..lineTo(13.875, 12.0)
          ..lineTo(13.875, 9.74899)
          ..cubicTo(13.875, 8.80001, 14.3399, 7.875, 15.8306, 7.875)
          ..lineTo(17.3438, 7.875)
          ..lineTo(17.3438, 4.92187)
          ..cubicTo(17.3438, 4.92187, 15.9705, 4.6875, 14.6576, 4.6875)
          ..cubicTo(11.9165, 4.6875, 10.125, 6.34875, 10.125, 9.35625)
          ..lineTo(10.125, 12)
          ..lineTo(7.07812, 12.0)
          ..lineTo(7.07812, 15.4687)
          ..lineTo(10.125, 15.4687)
          ..lineTo(10.125, 23.8542)
          ..cubicTo(10.7359, 23.9501, 11.3621, 24, 12, 24)
          ..cubicTo(12.6379, 24, 13.2641, 23.9501, 13.875, 23.8542)
          ..lineTo(13.875, 15.4687)
          ..lineTo(16.6711, 15.4687)
          ..close(),
        Paint()..color = Colors.white,
      );
      return;
    }
  }

  @override
  bool shouldRepaint(covariant _ProviderPainter oldDelegate) =>
      oldDelegate.provider != provider || oldDelegate.foreground != foreground;
}
