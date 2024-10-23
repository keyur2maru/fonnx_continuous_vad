class CircularBuffer<T> {
  final List<T?> _buffer;
  int _start = 0;
  int _length = 0;

  CircularBuffer(int capacity) : _buffer = List<T?>.filled(capacity, null);

  void add(T item) {
    if (_length < _buffer.length) {
      _buffer[(_start + _length) % _buffer.length] = item;
      _length++;
    } else {
      _buffer[_start] = item;
      _start = (_start + 1) % _buffer.length;
    }
  }

  void addAll(Iterable<T> items) {
    for (var item in items) {
      add(item);
    }
  }

  List<T> toList() {
    return [
      for (int i = 0; i < _length; i++)
        _buffer[(_start + i) % _buffer.length]!
    ];
  }

  void clear() {
    _start = 0;
    _length = 0;
  }

  int get length => _length;

  void removeFirst() {
    if (_length == 0) return;
    _start = (_start + 1) % _buffer.length;
    _length--;
  }
}
