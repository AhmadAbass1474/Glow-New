import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Closes only the sheet that owns [context], after this tap has finished.
void popTopSheet(BuildContext context) {
  final route = ModalRoute.of(context);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted || route?.isCurrent == false) return;
    Navigator.of(context).pop();
  });
}

/// Scrolls [child] and lets a tap on the leftover empty space close this sheet.
class SheetScroll extends StatelessWidget {
  const SheetScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: child),
        SliverFillRemaining(
          hasScrollBody: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => popTopSheet(context),
          ),
        ),
      ],
    );
  }
}

/// One sheet route. A tap on the dim area, or a downward drag, closes only
/// this sheet on the next frame so the gesture cannot close the sheet under it.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required double heightFactor,
  required Widget Function(BuildContext sheetContext) builder,
  bool avoidKeyboard = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final inset = avoidKeyboard ? media.viewInsets.bottom : 0.0;
      final height = math.max(160.0, media.size.height * heightFactor - inset);
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: _SheetFrame(
          height: height,
          onPop: () {
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
          child: builder(sheetContext),
        ),
      );
    },
  );
}

class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppColors.border_radius);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: AppColors.inputBorder),
      ),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: radius,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.close, size: 18, color: AppColors.secondary),
        ),
      ),
    );
  }
}

class _SheetFrame extends StatefulWidget {
  const _SheetFrame({
    required this.height,
    required this.onPop,
    required this.child,
  });

  final double height;
  final VoidCallback onPop;
  final Widget child;

  @override
  State<_SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<_SheetFrame> {
  var _popped = false;
  var _drag = 0.0;

  void _pop() {
    if (_popped) return;
    _popped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pop,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: widget.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (details) {
              if (_popped) return;
              final next = _drag + details.delta.dy;
              if (next < 0) return;
              setState(() => _drag = next);
            },
            onVerticalDragEnd: (details) {
              if (_popped) return;
              final velocity = details.primaryVelocity ?? 0;
              if (_drag > 72 || velocity > 700) {
                _pop();
                return;
              }
              setState(() => _drag = 0);
            },
            onVerticalDragCancel: () {
              if (_drag == 0) return;
              setState(() => _drag = 0);
            },
            child: Transform.translate(
              offset: Offset(0, _drag),
              child: Material(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppColors.border_radius),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(child: widget.child),
                    ),
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      child: SheetCloseButton(onPressed: _pop),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
