/// Outcome of a Plaid Link session.
enum PlaidLinkStatus { success, exited, failed }

/// Result of a Plaid Link session.
///
/// [status] describes whether the user linked an account, exited the flow, or
/// whether the session could not be started/completed.
class PlaidLinkResult {
  const PlaidLinkResult({
    required this.status,
    this.publicToken,
    this.institutionId,
    this.institutionName,
    this.message,
  });

  const PlaidLinkResult.success({
    required String publicToken,
    String? institutionId,
    String? institutionName,
  }) : this(
         status: PlaidLinkStatus.success,
         publicToken: publicToken,
         institutionId: institutionId,
         institutionName: institutionName,
       );

  const PlaidLinkResult.exited({String? message, String? institutionName})
    : this(
        status: PlaidLinkStatus.exited,
        message: message,
        institutionName: institutionName,
      );

  const PlaidLinkResult.failed(String message)
    : this(status: PlaidLinkStatus.failed, message: message);

  final PlaidLinkStatus status;
  final String? publicToken;
  final String? institutionId;
  final String? institutionName;
  final String? message;

  bool get isSuccess => status == PlaidLinkStatus.success;
}

/// Boundary for opening the native Plaid Link flow.
abstract class PlaidLinkLauncher {
  Future<PlaidLinkResult> launch({required String linkToken});
}
