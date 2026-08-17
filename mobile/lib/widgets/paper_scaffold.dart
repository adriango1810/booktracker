import 'package:flutter/material.dart';
import '../theme/biblioteka_theme.dart';

/// Warm paper background matching Biblioteka's body gradient.
class PaperScaffold extends StatelessWidget {
  const PaperScaffold({
    super.key,
    this.appBar,
    required this.body,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BkColors.cream, BkColors.creamWarm],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -90,
            left: -70,
            child: _Wash(color: Color(0x2E6B8F76), size: 280),
          ),
          const Positioned(
            bottom: -80,
            right: -50,
            child: _Wash(color: Color(0x29A88762), size: 260),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: appBar,
            body: body,
          ),
        ],
      ),
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: BkColors.leafBorder),
    );
    return Material(
      color: BkColors.card,
      elevation: 0,
      shadowColor: const Color(0x142A2E28),
      shape: shape,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _Wash extends StatelessWidget {
  const _Wash({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}
