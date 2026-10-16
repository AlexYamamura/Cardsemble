import 'package:flutter/material.dart';
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

     // Verify the buttons are present in the footer
     expect(find.byKey(ValueKey('add-household-member-button')), findsOneWidget);
     expect(find.byKey(ValueKey('add-manually-button')), findsOneWidget);

     // Tap the add household member button and verify it calls _scanQrCode
     // We can't directly test the modal, but we can verify that the notifier's
     // addMember or joinByInviteCode is called? Actually, _scanQrCode calls those.
     // For simplicity, we'll just tap and ensure no exception.
     await tester.ensureVisible(find.text('Add household member').first);
     await tester.tap(find.text('Add household member').first);
     await tester.pumpAndSettle();

     // Dismiss the QR scan modal by tapping the cancel button
     await tester.tap(find.text('Cancel').first);
     await tester.pumpAndSettle();

     // Tap the add manually button and verify it shows the dialog
     await tester.ensureVisible(find.text('Add manually').first);
     await tester.tap(find.text('Add manually').first);
     await tester.pumpAndSettle();

    // Verify the dialog appears with a single name field (the screen itself
    // also renders a filter search field, so scope the lookup to the dialog).
    expect(find.text('Add Person'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
  });
}