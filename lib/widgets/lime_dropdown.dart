import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';

class LIMEDropdown<T> extends StatefulWidget {
  final String label;
  final String? hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Color? arrowColor;
  final bool enabled;
  final bool showLabel;
  final bool compact;

  const LIMEDropdown({
    super.key,
    required this.label,
    this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.arrowColor,
    this.enabled = true,
    this.showLabel = true,
    this.compact = false,
  });

  @override
  State<LIMEDropdown<T>> createState() => _LIMEDropdownState<T>();
}

class _LIMEDropdownState<T> extends State<LIMEDropdown<T>> {
  final LayerLink _link = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      _removeEntry();
      return;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final renderBox = _targetKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero);
    final size = renderBox?.size;
    if (offset == null || size == null) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final availableHeight = (screenHeight - (offset.dy + size.height) - 8).clamp(120.0, 320.0);

    _entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeEntry,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              offset: Offset(0, size.height + 4),
              child: Material(
                elevation: 8,
                shadowColor: Colors.black12,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: size.width,
                      maxWidth: size.width,
                      maxHeight: availableHeight,
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: widget.items.length,
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        final selected = item.value == widget.value;
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: DefaultTextStyle(
                            style: TextStyle(
                              fontSize: 14,
                              color: selected ? HexColor("#116754") : Colors.black87,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            ),
                            child: item.child,
                          ),
                          selected: selected,
                          selectedTileColor: HexColor("#116754").withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          trailing: selected ? Icon(Icons.check, size: 16, color: HexColor("#116754")) : null,
                          onTap: () {
                            widget.onChanged(item.value);
                            _removeEntry();
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    String displayValue = widget.hint ?? widget.label;
    try {
      if (widget.value != null) {
        final selectedItem = widget.items.firstWhere((i) => i.value == widget.value);
        if (selectedItem.child is Text) {
          displayValue = (selectedItem.child as Text).data ?? '';
        }
      }
    } catch (_) {}

    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        key: _targetKey,
        onTap: widget.enabled ? _toggle : null,
        borderRadius: BorderRadius.circular(widget.compact ? 12 : 8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16, 
            vertical: widget.compact ? 10 : 12
          ),
          decoration: BoxDecoration(
            color: widget.compact ? Colors.grey[50] : Colors.white,
            borderRadius: BorderRadius.circular(widget.compact ? 12 : 8),
            border: Border.all(
              color: widget.enabled ? Colors.grey[300]! : Colors.grey[100]!,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showLabel && !widget.compact) ...[
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      displayValue,
                      style: TextStyle(
                        color: widget.value == null ? (widget.compact ? Colors.grey[600] : Colors.grey[400]) : Colors.black87,
                        fontSize: widget.compact ? 14 : 15,
                        fontWeight: widget.value != null ? FontWeight.w500 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down, 
                size: widget.compact ? 20 : 24,
                color: widget.arrowColor ?? HexColor("#116754")
              ),
            ],
          ),
        ),
      ),
    );
  }
}
