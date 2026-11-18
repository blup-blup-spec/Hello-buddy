import 'package:flutter/material.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';

/// Reusable brutalist pill button with press animation
class BuddyPillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color fill;
  final Color textColor;
  final double fontSize;
  final FontWeight fontWeight;
  final IconData? icon;
  final bool isGhost;
  final double height;

  const BuddyPillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.fill = BuddyColors.lime,
    this.textColor = BuddyColors.onLime,
    this.fontSize = 15,
    this.fontWeight = FontWeight.w800,
    this.icon,
    this.isGhost = false,
    this.height = 52,
  });

  @override
  State<BuddyPillButton> createState() => _BuddyPillButtonState();
}

class _BuddyPillButtonState extends State<BuddyPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: widget.height,
        transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
        decoration: widget.isGhost
            ? BuddyDecorations.ghostPill(fill: widget.fill)
            : BoxDecoration(
                color: widget.fill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: BuddyColors.pitch, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: BuddyColors.pitch,
                    offset: Offset(0, _pressed ? 1 : 4),
                    blurRadius: 0,
                  ),
                ],
              ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: widget.textColor, size: 20),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: BuddyTheme.displayFont(
                  fontSize: widget.fontSize,
                  fontWeight: widget.fontWeight,
                  color: widget.textColor,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brutalist card container
class BuddyCard extends StatelessWidget {
  final Widget child;
  final Color fill;
  final EdgeInsetsGeometry padding;
  final double radius;

  const BuddyCard({
    super.key,
    required this.child,
    this.fill = Colors.white,
    this.padding = const EdgeInsets.all(18),
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BuddyDecorations.card(fill: fill, radius: radius),
      padding: padding,
      child: child,
    );
  }
}

/// Input field with brutalist styling
class BuddyInputField extends StatelessWidget {
  final String hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextEditingController? controller;

  const BuddyInputField({
    super.key,
    required this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BuddyDecorations.inputField(),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: BuddyTheme.bodyFont(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: BuddyTheme.bodyFont(
            fontSize: 14,
            color: BuddyColors.smoke,
          ),
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon, color: BuddyColors.smoke, size: 20)
              : null,
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }
}

/// Segmented tab control (neo-graphic style)
class BuddySegmentedControl extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const BuddySegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (i) {
        final isActive = i == selectedIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              height: 42,
              margin: EdgeInsets.only(right: i < labels.length - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: isActive ? BuddyColors.lime : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: BuddyColors.pitch, width: 2),
                boxShadow: isActive
                    ? const [
                        BoxShadow(
                          color: BuddyColors.pitch,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                labels[i],
                style: BuddyTheme.bodyFont(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? BuddyColors.onLime : BuddyColors.smoke,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Chip button for quick actions
class BuddyChip extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  const BuddyChip({
    super.key,
    required this.label,
    this.onTap,
    this.isActive = false,
  });

  @override
  State<BuddyChip> createState() => _BuddyChipState();
}

class _BuddyChipState extends State<BuddyChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isActive ? BuddyColors.lime : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: BuddyColors.pitch, width: 2),
          boxShadow: [
            BoxShadow(
              color: BuddyColors.pitch,
              offset: Offset(0, _pressed ? 1 : 2),
            ),
          ],
        ),
        child: Text(
          widget.label,
          style: BuddyTheme.bodyFont(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: widget.isActive ? BuddyColors.onLime : BuddyColors.pitch,
          ),
        ),
      ),
    );
  }
}
