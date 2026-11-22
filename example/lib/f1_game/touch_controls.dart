import 'package:flutter/material.dart';

/// Pressed state of the on-screen controls, read by the car every frame.
class DriveInput {
  bool left = false;
  bool right = false;
  bool gas = false;
  bool brake = false;

  void reset() => left = right = gas = brake = false;
}

/// Steering buttons on the left, brake and accelerator pedals on the right.
///
/// Every control uses its own pointer [Listener], so steering and pedals can
/// be held at the same time with multi-touch.
class TouchControls extends StatelessWidget {
  const TouchControls({super.key, required this.input});

  final DriveInput input;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HoldButton(
                  width: 84,
                  height: 84,
                  color: const Color(0xFF5B6B8C),
                  onChanged: (v) => input.left = v,
                  child: const Icon(Icons.chevron_left_rounded, size: 56),
                ),
                const SizedBox(width: 14),
                _HoldButton(
                  width: 84,
                  height: 84,
                  color: const Color(0xFF5B6B8C),
                  onChanged: (v) => input.right = v,
                  child: const Icon(Icons.chevron_right_rounded, size: 56),
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _HoldButton(
                  width: 72,
                  height: 96,
                  color: const Color(0xFFC8372D),
                  onChanged: (v) => input.brake = v,
                  child: const _PedalLabel(Icons.stop_rounded, 'BRAKE'),
                ),
                const SizedBox(width: 14),
                _HoldButton(
                  width: 84,
                  height: 132,
                  color: const Color(0xFF2E9B57),
                  onChanged: (v) => input.gas = v,
                  child:
                      const _PedalLabel(Icons.keyboard_arrow_up_rounded, 'GAS'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PedalLabel extends StatelessWidget {
  const _PedalLabel(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 40),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.width,
    required this.height,
    required this.color,
    required this.onChanged,
    required this.child,
  });

  final double width;
  final double height;
  final Color color;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  final Set<int> _pointers = {};

  bool get _pressed => _pointers.isNotEmpty;

  void _down(PointerEvent e) {
    _pointers.add(e.pointer);
    widget.onChanged(true);
    setState(() {});
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) widget.onChanged(false);
    setState(() {});
  }

  @override
  void dispose() {
    if (_pressed) widget.onChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1,
        duration: const Duration(milliseconds: 60),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _pressed ? 0.95 : 0.55),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: _pressed ? 0.9 : 0.4),
              width: 2,
            ),
          ),
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white),
              child: Center(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
