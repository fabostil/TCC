import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 96});

  final double height;

  static const String assetPath = 'assets/branding/voice_first_app.png';
  static const String iconAssetPath = 'assets/branding/touchless_icon.png';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Touchless',
      image: true,
      child: Image.asset(
        assetPath,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
