import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';

class LIMEDropdown<T> extends StatefulWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Color? arrowColor;

  const LIMEDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.arrowColor,
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
                elevation: 12,
                shadowColor: Colors.black26,
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
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shrinkWrap: true,
                      itemCount: widget.items.length,
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        final selected = item.value == widget.value;
                        return ListTile(
                          dense: true,
                          title: item.child,
                          selected: selected,
                          selectedTileColor: HexColor("#0F4C7F").withValues(alpha: 0.05),
                          trailing: selected ? Icon(Icons.check, size: 18, color: HexColor("#0F4C7F")) : null,
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
    String displayValue = '';
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
        borderRadius: BorderRadius.circular(8),
        onTap: _toggle,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  displayValue,
                  style: TextStyle(
                    color: widget.value == null ? Colors.grey[600] : Colors.black,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down, color: widget.arrowColor ?? HexColor("#0F4C7F")),
            ],
          ),
        ),
      ),
    );
  }
}
