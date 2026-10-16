import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show debugDumpRenderTree;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/features/household/presentation/household_notifier.dart';
import 'package:cardsemble/features/household/presentation/people_screen.dart';
import 'package:cardsemble/features/household/domain/household_repository.dart';
import 'package:cardsemble/features/household/domain/entities/household.dart';
import 'package:cardsemble/core/core.dart';

class FakeHouseholdRepository implements HouseholdRepository {
  @override
  Future<Result<List<HouseholdPerson>>> loadPeople() async {
    return Success([]);
  }

  @override
  Future<Result<List<HouseholdMember>>> loadMembers() async {
    return Success([]);
  }

  @override
  Future<Result<HouseholdPerson>> createPerson(
      String displayName, {bool isDefault = false}) async {
    return Success(HouseholdPerson(
      id: '1',
      displayName: displayName,
      isDefault: isDefault,
    ));
  }

  @override
  Future<Result<void>> addMember(String userId) async {
    return const Success(null);
  }

  @override
  Future<Result<JoinHouseholdResult>> joinByInviteCode(String inviteCode) async {
    return Success(JoinHouseholdResult(householdId: 'test', member: null));
  }

  @override
  Future<Result<void>> updatePerson(
      String personId, String displayName, {bool? isDefault}) async {
    return const Success(null);
  }

  @override
  Future<Result<void>> deletePerson(String personId) async {
    return const Success(null);
  }
}

void main() {
  late FakeHouseholdRepository repository;
  late HouseholdNotifier notifier;

  setUp(() {
    repository = FakeHouseholdRepository();
    notifier = HouseholdNotifier(householdRepository: repository);
  });

  testWidgets('renders add household member and add manually buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<HouseholdNotifier>.value(
        value: notifier,
        child: const MaterialApp(
          home: PeopleScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Debug: dump the render tree
    debugPrint('Render tree:');
    debugDumpRenderTree();

    // Verify the buttons are present in the footer
    expect(find.text('Add household member'), findsOneWidget);
    expect(find.text('Add manually'), findsOneWidget);

    // Verify the buttons are of the correct type
    expect(find.byType(FilledButton).first, findsOneWidget); // Add household member
    expect(find.byType(OutlinedButton).first, findsOneWidget); // Add manually

    // Tap the add household member button and verify it calls _scanQrCode
    // We can't directly test the modal, but we can verify that the notifier's
    // addMember or joinByInviteCode is called? Actually, _scanQrCode calls those.
    // For simplicity, we'll just tap and ensure no exception.
    await tester.tap(find.text('Add household member').first);
    await tester.pumpAndSettle();

    // Tap the add manually button and verify it shows the dialog
    await tester.tap(find.text('Add manually').first);
    await tester.pumpAndSettle();

    // Verify the dialog appears
    expect(find.text('Add Person'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}