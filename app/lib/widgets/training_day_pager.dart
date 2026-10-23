import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One complete, full-width day per page. Height follows the current day's
/// content rather than clipping instructions at a fixed phone-sized height.
class TrainingDayPager extends StatefulWidget {
  const TrainingDayPager({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.selectedDate,
    required this.onDate,
    required this.builder,
  });
  final DateTime firstDate, lastDate, selectedDate;
  final ValueChanged<DateTime> onDate;
  final Widget Function(DateTime) builder;
  @override
  State<TrainingDayPager> createState() => _TrainingDayPagerState();
}

class _TrainingDayPagerState extends State<TrainingDayPager>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late PageController _controller;
  final Map<int, double> _heights = {};
  int _index(DateTime d) => DateTime.utc(d.year, d.month, d.day)
      .difference(
        DateTime.utc(
          widget.firstDate.year,
          widget.firstDate.month,
          widget.firstDate.day,
        ),
      )
      .inDays;
  DateTime _date(int i) => DateTime(
    widget.firstDate.year,
    widget.firstDate.month,
    widget.firstDate.day + i,
  );
  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _index(widget.selectedDate));
  }

  @override
  void didUpdateWidget(covariant TrainingDayPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstDate != widget.firstDate) {
      _controller.dispose();
      _controller = PageController(initialPage: _index(widget.selectedDate));
      _heights.clear();
    } else if (oldWidget.selectedDate != widget.selectedDate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _controller.hasClients &&
            _controller.page?.round() != _index(widget.selectedDate)) {
          _controller.jumpToPage(_index(widget.selectedDate));
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SizedBox(
      height: _heights[_index(widget.selectedDate)] ?? 600,
      child: PageView.builder(
        key: const ValueKey('training-day-pages'),
        controller: _controller,
        itemCount: _index(widget.lastDate) + 1,
        onPageChanged: (i) => widget.onDate(_date(i)),
        itemBuilder: (context, i) => OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: _MeasureSize(
            onChange: (size) {
              if (mounted && _heights[i] != size.height) {
                setState(() => _heights[i] = size.height);
              }
            },
            child: widget.builder(_date(i)),
          ),
        ),
      ),
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});
  final ValueChanged<Size> onChange;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureRender(onChange);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MeasureRender renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureRender extends RenderProxyBox {
  _MeasureRender(this.onChange);
  ValueChanged<Size> onChange;
  Size? _oldSize;
  @override
  void performLayout() {
    super.performLayout();
    if (size != _oldSize) {
      _oldSize = size;
      final measured = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange(measured));
    }
  }
}
