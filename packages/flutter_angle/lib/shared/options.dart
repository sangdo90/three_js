class AngleOptions{
  AngleOptions({
    required this.width,
    required this.height,
    required this.dpr,
    this.alpha = false,
    this.antialias = false,
    this.useDebugContext = false
  });

  num width;
  num height;
  double dpr;
  bool antialias;
  bool alpha;
  bool useDebugContext;
}