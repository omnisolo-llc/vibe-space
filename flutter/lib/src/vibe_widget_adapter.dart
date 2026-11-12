import 'package:flutter/cupertino.dart';

/// Supported built-in Flutter widget toolkits for [VibeWidgetAdapter].
enum VibeWidgetKit { material, cupertino, custom }

typedef VibeNodeHeadingBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  Widget child,
  Color? toneColor,
);

typedef VibeNodeTextBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  Widget child,
  Color? toneColor,
);

typedef VibeNodeBadgeBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  Widget child,
  Color badgeColor,
);

typedef VibeNodeStatBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  Widget valueWidget,
  Widget labelWidget,
  Color? toneColor,
);

typedef VibeNodeBarBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  Widget labelWidget,
  Widget? captionWidget,
  double ratio,
  Color fillColor,
  Color? swatchColor,
);

typedef VibeNodeSparklineBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  List<double> points,
  Color strokeColor,
);

typedef VibeNodeButtonBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  String title,
  String command,
  Map<String, dynamic> args,
  VoidCallback onPressed,
  Color? toneColor,
);

typedef VibeNodeCardBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  Widget child,
);

typedef VibeNodeTableBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  List<Widget> headers,
  List<List<Widget>> rows,
);

typedef VibeNodeInputBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  String id,
  String label,
  bool secret,
  bool multiline,
  ValueChanged<String> onChanged,
);

typedef VibeNodeCheckboxBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  String id,
  String label,
  bool checked,
  ValueChanged<bool> onChanged,
);

typedef VibeNodeOptionGroupBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> node,
  String id,
  String? label,
  bool multiSelect,
  List<Map<String, dynamic>> options,
  Set<String> selectedIds,
  ValueChanged<String> onToggleOption,
);

typedef VibeSealedTextBuilder = Widget Function(
  BuildContext context,
  String resolvedValue,
  TextStyle? style,
);

/// Compatibility adapter allowing [VibeView] and [VibeCanvasView] to render
/// through Material, Cupertino, or custom host design-system widgets while
/// preserving VibeProtocol validation and sealed-handle isolation.
@immutable
class VibeWidgetAdapter {
  const VibeWidgetAdapter.material()
      : kit = VibeWidgetKit.material,
        fallbackKit = VibeWidgetKit.material,
        headingBuilder = null,
        textBuilder = null,
        badgeBuilder = null,
        statBuilder = null,
        barBuilder = null,
        sparklineBuilder = null,
        buttonBuilder = null,
        cardBuilder = null,
        tableBuilder = null,
        inputBuilder = null,
        checkboxBuilder = null,
        optionGroupBuilder = null,
        sealedTextBuilder = null;

  const VibeWidgetAdapter.cupertino()
      : kit = VibeWidgetKit.cupertino,
        fallbackKit = VibeWidgetKit.cupertino,
        headingBuilder = null,
        textBuilder = null,
        badgeBuilder = null,
        statBuilder = null,
        barBuilder = null,
        sparklineBuilder = null,
        buttonBuilder = null,
        cardBuilder = null,
        tableBuilder = null,
        inputBuilder = null,
        checkboxBuilder = null,
        optionGroupBuilder = null,
        sealedTextBuilder = null;

  const VibeWidgetAdapter.custom({
    this.fallbackKit = VibeWidgetKit.material,
    this.headingBuilder,
    this.textBuilder,
    this.badgeBuilder,
    this.statBuilder,
    this.barBuilder,
    this.sparklineBuilder,
    this.buttonBuilder,
    this.cardBuilder,
    this.tableBuilder,
    this.inputBuilder,
    this.checkboxBuilder,
    this.optionGroupBuilder,
    this.sealedTextBuilder,
  }) : kit = VibeWidgetKit.custom;

  final VibeWidgetKit kit;
  final VibeWidgetKit fallbackKit;
  final VibeNodeHeadingBuilder? headingBuilder;
  final VibeNodeTextBuilder? textBuilder;
  final VibeNodeBadgeBuilder? badgeBuilder;
  final VibeNodeStatBuilder? statBuilder;
  final VibeNodeBarBuilder? barBuilder;
  final VibeNodeSparklineBuilder? sparklineBuilder;
  final VibeNodeButtonBuilder? buttonBuilder;
  final VibeNodeCardBuilder? cardBuilder;
  final VibeNodeTableBuilder? tableBuilder;
  final VibeNodeInputBuilder? inputBuilder;
  final VibeNodeCheckboxBuilder? checkboxBuilder;
  final VibeNodeOptionGroupBuilder? optionGroupBuilder;
  final VibeSealedTextBuilder? sealedTextBuilder;

  /// Returns whether Cupertino primitives should be used when no custom builder
  /// overrides a node.
  bool get usesCupertino =>
      kit == VibeWidgetKit.cupertino ||
      (kit == VibeWidgetKit.custom && fallbackKit == VibeWidgetKit.cupertino);

  /// Built-in Cupertino card renderer used when [usesCupertino] is `true`.
  static Widget buildCupertinoCard(BuildContext context, Widget child) {
    final bg = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    );
    final border = CupertinoColors.separator.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.7),
      ),
      child: child,
    );
  }

  /// Built-in Cupertino button renderer used when [usesCupertino] is `true`.
  static Widget buildCupertinoButton({
    required BuildContext context,
    required String title,
    required VoidCallback onPressed,
    Color? toneColor,
    bool filled = false,
  }) {
    final child = Text(
      title,
      style: toneColor != null && !filled ? TextStyle(color: toneColor) : null,
    );
    if (filled) {
      return CupertinoButton.filled(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(36, 36),
        onPressed: onPressed,
        child: child,
      );
    }
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: const Size(34, 34),
      color: toneColor?.withValues(alpha: 0.14) ??
          CupertinoColors.tertiarySystemFill.resolveFrom(context),
      onPressed: onPressed,
      child: child,
    );
  }
}

/// Inherited scope providing a [VibeWidgetAdapter] to descendant [VibeView] and
/// [VibeCanvasView] widgets.
class VibeWidgetAdapterScope extends InheritedWidget {
  const VibeWidgetAdapterScope({
    super.key,
    required this.adapter,
    required super.child,
  });

  final VibeWidgetAdapter adapter;

  static VibeWidgetAdapter? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<VibeWidgetAdapterScope>()
        ?.adapter;
  }

  static VibeWidgetAdapter of(BuildContext context) {
    return maybeOf(context) ?? const VibeWidgetAdapter.material();
  }

  @override
  bool updateShouldNotify(VibeWidgetAdapterScope oldWidget) {
    return !identical(adapter, oldWidget.adapter) && adapter != oldWidget.adapter;
  }
}
