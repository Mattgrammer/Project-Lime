import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'guide_pointer.dart';

class TimeRangeSelector extends StatefulWidget {
  final String label;
  final String initialValue;
  final ValueChanged<String> onTimeChanged;
  final Key? containerKey;

  const TimeRangeSelector({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onTimeChanged,
    this.containerKey,
  });

  @override
  State<TimeRangeSelector> createState() => _TimeRangeSelectorState();
}

class _TimeRangeSelectorState extends State<TimeRangeSelector> {
  late String _currentTime;

  @override
  void initState() {
    super.initState();
    _currentTime = widget.initialValue;
  }

  Future<void> _selectTimeRange() async {
    GuidePointer.toggle(false);
    
    final TimeOfDay? startTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'SELECT START TIME',
    );

    if (startTime == null) {
      GuidePointer.toggle(true);
      return;
    }

    if (!mounted) return;

    final TimeOfDay? endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: startTime.hour + 1, minute: startTime.minute),
      helpText: 'SELECT END TIME',
    );

    if (endTime == null) {
      GuidePointer.toggle(true);
      return;
    }
    
    GuidePointer.toggle(true);
    
    if (!mounted) return;

    final String formattedRange = '${startTime.format(context)} - ${endTime.format(context)}';
    setState(() {
      _currentTime = formattedRange;
    });
    widget.onTimeChanged(formattedRange);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: widget.containerKey,
      onTap: _selectTimeRange,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: Icon(Icons.access_time, color: HexColor("#116754")),
        ),
        child: Text(
          _currentTime.isEmpty ? 'Select Time Range' : _currentTime,
          style: TextStyle(
            color: _currentTime.isEmpty ? Colors.grey[600] : Colors.black,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
