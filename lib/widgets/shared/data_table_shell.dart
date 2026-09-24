import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/ui_scale.dart';

/// Dense bordered table shell: a shaded header row plus divider-separated
/// body rows.
///
/// Handles the bordered-container + header + zebra-divider rhythm that is
/// copy-pasted across trade, management and report tables. Column headers
/// use the standard monospace-ish HUD style; header row padding is
/// density-aware via [UiScale.spacing].
class DataTableShell extends StatelessWidget {
  const DataTableShell({
    super.key,
    required this.headers,
    required this.itemCount,
    required this.rowBuilder,
    this.flexes,
    this.headerAlignments,
    this.borderColor,
  });

  /// Column header labels.
  final List<String> headers;

  /// Per-column flex weights; defaults to equal widths.
  final List<int>? flexes;

  /// Per-column header text alignments.
  final List<TextAlign?>? headerAlignments;

  final int itemCount;

  /// Builds the body row for the given index.
  final Widget Function(BuildContext context, int index) rowBuilder;

  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final flexes = this.flexes ?? List<int>.filled(headers.length, 1);
    final aligns =
        headerAlignments ?? List<TextAlign?>.filled(headers.length, null);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: borderColor ?? cs.onSurface.withValues(alpha: 0.12),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: cs.onSurface.withValues(alpha: 0.04),
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: UiScale.spacing(8),
            ),
            child: Row(
              children: [
                for (var i = 0; i < headers.length; i++)
                  Expanded(
                    flex: flexes[i],
                    child: _colHeader(cs, headers[i], align: aligns[i]),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < itemCount; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: cs.onSurface.withValues(alpha: 0.08),
              ),
            rowBuilder(context, i),
          ],
        ],
      ),
    );
  }

  Widget _colHeader(ColorScheme cs, String text, {TextAlign? align}) {
    return Text(
      text,
      textAlign: align ?? TextAlign.left,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: cs.onSurface.withValues(alpha: 0.45),
      ),
    );
  }
}
