sealed class Failure {
  const Failure();

  String get message => switch (this) {
    NetworkFailure(message: final m) => m,
    AuthFailure(message: final m) => m,
    ValidationFailure(message: final m) => m,
    DatabaseFailure(message: final m) => m,
    NotFoundFailure(message: final m) => m,
    PermissionFailure(message: final m) => m,
    ConfigurationFailure(message: final m) => m,
    UnknownFailure(message: final m) => m,
  };
}

class NetworkFailure extends Failure {
  const NetworkFailure(this.message, [this.code]);
  @override
  final String message;
  final String? code;
}

class AuthFailure extends Failure {
  const AuthFailure(this.message, [this.code]);
  @override
  final String message;
  final String? code;
}

class ValidationFailure extends Failure {
  const ValidationFailure(this.message, [this.code]);
  @override
  final String message;
  final String? code;
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(this.message, [this.code]);
  @override
  final String message;
  final String? code;
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(this.message, [this.code]);
  @override
  final String message;
  final String? code;
}

class PermissionFailure extends Failure {
  const PermissionFailure(this.message, [this.code]);
  @override
  final String message;
  final String? code;
}

class ConfigurationFailure extends Failure {
  const ConfigurationFailure(this.message, [this.code]);
  @override
  final String message;
  final String? code;
}

class UnknownFailure extends Failure {
  const UnknownFailure(this.message, [this.code]);
  @override
  final String message;
  final String? code;
}

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is FailureResult<T>;

  T get value => (this as Success<T>).value;
  Failure get failure => (this as FailureResult<T>).failure;

  R fold<R>(R Function(T) onSuccess, R Function(Failure) onFailure) {
    return switch (this) {
      Success<T>(value: final v) => onSuccess(v),
      FailureResult<T>(failure: final f) => onFailure(f),
    };
  }
}

class Success<T> extends Result<T> {
  const Success(this.value);
  @override
  final T value;
}

class FailureResult<T> extends Result<T> {
  const FailureResult(this.failure);
  @override
  final Failure failure;
}

extension ResultExtensions<T> on Result<T> {
  Result<R> map<R>(R Function(T) transform) {
    return fold(
      (value) => Success(transform(value)),
      (failure) => FailureResult(failure),
    );
  }

  Result<R> flatMap<R>(Result<R> Function(T) transform) {
    return fold(
      (value) => transform(value),
      (failure) => FailureResult(failure),
    );
  }
}

Result<T> success<T>(T value) => Success(value);
Result<T> failure<T>(Failure failure) => FailureResult(failure);