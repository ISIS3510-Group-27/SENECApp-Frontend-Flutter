import 'dart:isolate';

Future<R> runIsolated<A, R>(R Function(A input) work, A input) =>
    Isolate.run(() => work(input));
