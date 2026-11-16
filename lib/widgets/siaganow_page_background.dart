import 'dart:math';

import 'package:flutter/material.dart';

/// Shared visual tokens for information surfaces; controls remain solid.
abstract final class SiagaNowSurfaceTokens {
  static const info = Color(0xBFFFFFFF); // 75% opaque
  static const mintInfo = Color(0xBFEAF9EF); // 75% opaque
  static const warning = Color(0xCCFFF0F0); // 80% opaque for semantic contrast
  static const error = Color(0xCCFFEEEE);
  static const notice = Color(0xCCFFF3D7);
  static const simulationNotice = Color(0xCCFFF2D5);
  static const border = Color(0x66FFFFFF);
  static const cardRadius = 12.0;
  static const panelRadius = 12.0;
  static const dialogRadius = 16.0;
}

class SiagaNowHeaderBackground extends StatelessWidget {
  const SiagaNowHeaderBackground({
    super.key,
    this.overlayOpacity = .5,
    this.waveAlignment = Alignment.topCenter,
  });

  final double overlayOpacity;
  final Alignment waveAlignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      return Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF79B99E), Color(0xFFCDEBDD)],
              ),
            ),
          ),
          Positioned.fill(
            key: const ValueKey('siaganow.header.wave'),
            child: Image.asset(
              'assets/images/header_waves.png',
              width: width,
              fit: BoxFit.fitWidth,
              alignment: waveAlignment,
            ),
          ),
          Positioned.fill(
            key: const ValueKey('siaganow.header.green-overlay'),
            child: IgnorePointer(
              child: Opacity(
                opacity: overlayOpacity.clamp(.4, .6),
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF16845F),
                    BlendMode.srcATop,
                  ),
                  child: Image.asset(
                    'assets/images/header_waves.png',
                    width: width,
                    fit: BoxFit.fitWidth,
                    alignment: waveAlignment,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class SiagaNowPageBackground extends StatelessWidget {
  const SiagaNowPageBackground({
    super.key,
    required this.child,
    this.showTop = false,
    this.showLandscape = true,
    this.landscapeHeight,
  });

  final Widget child;
  final bool showTop;
  final bool showLandscape;
  final double? landscapeHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final footerHeight = min(
        landscapeHeight ?? 330.0,
        constraints.maxHeight * .44,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFFD3F1E0)),
          if (showTop)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 180,
              child: SiagaNowHeaderBackground(),
            ),
          if (showLandscape)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: footerHeight,
              child: Image.asset(
                'assets/images/landscape_background.png',
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
          if (showLandscape)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: footerHeight,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB3D3F1E0), Color(0x22D3F1E0)],
                    stops: [0, .58],
                  ),
                ),
              ),
            ),
          Positioned(
            top: showTop ? 180 : 0,
            left: 0,
            right: 0,
            bottom: 0,
            child: const SiagaNowColorOverlay(),
          ),
          child,
        ],
      );
    },
  );
}

class SiagaNowColorOverlay extends StatelessWidget {
  const SiagaNowColorOverlay({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Opacity(
      opacity: .30,
      child: Image.asset(
        'assets/images/global_color_overlay.png',
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    ),
  );
}
