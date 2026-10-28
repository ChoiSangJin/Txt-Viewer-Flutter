import 'package:flutter/material.dart';

/// Keeps editing local until Apply/Done, so typing does not repeatedly reflow a book.
class NumericReadingSetting extends StatefulWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const NumericReadingSetting({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  @override
  State<NumericReadingSetting> createState() => _NumericReadingSettingState();
}

class _NumericReadingSettingState extends State<NumericReadingSetting> {
  late final controller = TextEditingController(text: format(widget.value));
  String? error;
  static String format(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  void didUpdateWidget(covariant NumericReadingSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      controller.text = format(widget.value);
      error = null;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void apply() {
    final parsed = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < widget.min ||
        parsed > widget.max) {
      setState(
        () => error =
            '${format(widget.min)}~${format(widget.max)} 사이의 숫자를 입력해 주세요.',
      );
      return;
    }
    final value = (parsed * 100).round() / 100;
    setState(() {
      error = null;
      controller.text = format(value);
    });
    widget.onChanged(value);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: '${format(widget.min)}~${format(widget.max)} · 입력 후 적용',
          errorText: error,
          errorMaxLines: 2,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: '${widget.label} 적용',
            onPressed: apply,
            icon: const Icon(Icons.check),
          ),
        ),
        onSubmitted: (_) => apply(),
        onChanged: (_) {
          if (error != null) setState(() => error = null);
        },
      ),
      Slider(
        label: format(widget.value),
        value: widget.value,
        min: widget.min,
        max: widget.max,
        onChanged: (value) => widget.onChanged((value * 100).round() / 100),
      ),
      const SizedBox(height: 8),
    ],
  );
}
