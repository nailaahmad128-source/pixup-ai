import 'dart:io';
import 'package:flutter/material.dart';

/// A draggable divider that reveals the "before" image on one side
/// and the "after" (enhanced) image on the other.
class BeforeAfterSlider extends StatefulWidget {
  const BeforeAfterSlider({
    super.key,
    required this.beforeFile,
    required this.afterFile,
    this.borderRadius = 24,
  });

  final File beforeFile;
  final File afterFile;
  final double borderRadius;

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _position = 0.5; // 0.0 = fully "before", 1.0 = fully "after"

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _position =
                    (_position + details.delta.dx / width).clamp(0.0, 1.0);
              });
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // After image (fully visible underneath)
                Image.file(widget.afterFile, fit: BoxFit.cover),
                // Before image, clipped to the slider position
                ClipRect(
                  clipper: _SideClipper(_position),
                  child: Image.file(widget.beforeFile, fit: BoxFit.cover),
                ),
                // Labels
                Positioned(
                  top: 14,
                  left: 14,
                  child: const _Badge(label: 'BEFORE'),
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  child: const _Badge(label: 'AFTER'),
                ),
                // Divider handle
                Positioned(
                  left: (width * _position) - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white),
                ),
                Positioned(
                  left: (width * _position) - 20,
                  top: (constraints.maxHeight / 2) - 20,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.code,
                      size: 20,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SideClipper extends CustomClipper<Rect> {
  _SideClipper(this.position);
  final double position;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, size.width * position, size.height);
  }

  @override
  bool shouldReclip(covariant _SideClipper oldClipper) =>
      oldClipper.position != position;
}
