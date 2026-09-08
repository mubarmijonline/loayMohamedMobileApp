import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The app's back control.
///
/// Carries its own contrast rather than inheriting it. The default Material
/// back button takes its colour from `AppBarTheme.iconTheme`, which is
/// near-black in light mode — so on the screens with a dark brand header it
/// rendered black-on-navy and was effectively invisible. Setting
/// `foregroundColor` on the local `AppBar` does not fix that, because an
/// explicit `iconTheme` on the theme wins.
///
/// So this paints a translucent disc behind the chevron. It reads on a photo,
/// on the navy header and on a plain background, without any screen needing to
/// know which it is sitting on.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onDark = true, this.onPressed});

  /// True when the button sits on the dark brand header or a video frame.
  final bool onDark;

  /// Defaults to popping the route.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : AppColors.textPrimary;
    final bg = onDark
        ? Colors.white.withValues(alpha: 0.16)
        : AppColors.textPrimary.withValues(alpha: 0.06);
    final border =
        onDark ? Colors.white.withValues(alpha: 0.22) : AppColors.divider;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: bg,
        shape: CircleBorder(side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed ?? () => Navigator.of(context).maybePop(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: fg),
          ),
        ),
      ),
    );
  }
}
