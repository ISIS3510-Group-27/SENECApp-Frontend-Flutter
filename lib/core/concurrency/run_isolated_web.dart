Future<R> runIsolated<A, R>(R Function(A input) work, A input) async =>
    work(input);
