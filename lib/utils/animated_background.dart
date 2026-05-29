import 'package:flutter/material.dart';

class AnimatedGradientBackground extends StatefulWidget {
  final Widget child;

  const AnimatedGradientBackground({Key? key, required this.child}) : super(key: key);

  @override
  State<AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _color1;
  late Animation<Color?> _color2;
  late Animation<Color?> _color3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    )..repeat(reverse: true);

    _color1 = ColorTween(
      begin: const Color(0xFFF0F4F8), // Very light blue/grey
      end: const Color(0xFFFFFFFF),   // White
    ).animate(_controller);

    _color2 = ColorTween(
      begin: const Color(0xFFFFFFFF), // White
      end: const Color(0xFFE8F0FE),   // Subtle iOS light blue
    ).animate(_controller);

    _color3 = ColorTween(
      begin: const Color(0xFFF7F9FC), // Cool white
      end: const Color(0xFFF0F4F8),   // Very light blue/grey
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, cachedChild) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _color1.value ?? Colors.white,
                _color2.value ?? Colors.white,
                _color3.value ?? Colors.white,
              ],
            ),
          ),
          child: cachedChild,
        );
      },
    );
  }
}
