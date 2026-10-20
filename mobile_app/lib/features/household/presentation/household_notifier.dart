import 'package:flutter/material.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';

class HouseholdNotifier extends ChangeNotifier {
  HouseholdNotifier({
    required HouseholdRepository householdRepository,
  }) : _householdRepository = householdRepository;

  final HouseholdRepository _householdRepository;

  List<HouseholdPerson> _people = [];
  List<HouseholdMember> _members = [];
  bool _isLoading = false;
  String? _error;

  // Filter state
  String _nameQuery = '';
  bool? _defaultFilter; // null = all, true = default only, false = others

  List<HouseholdPerson> get people => _people;
  List<HouseholdMember> get members => _members;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String get nameQuery => _nameQuery;
  bool? get defaultFilter => _defaultFilter;

  List<HouseholdPerson> get filteredPeople {
    var filtered = _people;
    if (_nameQuery.isNotEmpty) {
      final query = _nameQuery.trim().toLowerCase();
      filtered = filtered.where(
        (person) => person.displayName.toLowerCase().contains(query),
      ).toList();
    }
    if (_defaultFilter != null) {
      filtered = filtered.where(
        (person) => person.isDefault == _defaultFilter,
      ).toList();
    }
    return filtered;
  }

  bool get hasActiveFilters =>
      _nameQuery.isNotEmpty || _defaultFilter != null;

  Future<void> loadPeople() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _householdRepository.loadPeople();
      result.fold(
        (people) => _people = people,
        (failure) => _error = failure.message,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMembers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _householdRepository.loadMembers();
      result.fold(
        (members) => _members = members,
        (failure) => _error = failure.message,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createPerson(String displayName, {bool isDefault = false}) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _householdRepository.createPerson(displayName, isDefault: isDefault);
      return result.fold(
        (person) {
          _people.add(person);
          notifyListeners();
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updatePerson(String personId, String displayName, {bool? isDefault}) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _householdRepository.updatePerson(personId, displayName, isDefault: isDefault);
      return result.fold(
        (_) {
          final index = _people.indexWhere((p) => p.id == personId);
          if (index != -1) {
            _people[index] = HouseholdPerson(
              id: personId,
              displayName: displayName,
              isDefault: isDefault ?? _people[index].isDefault,
            );
            notifyListeners();
          }
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deletePerson(String personId) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _householdRepository.deletePerson(personId);
      return result.fold(
        (_) {
          _people.removeWhere((p) => p.id == personId);
          notifyListeners();
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> addMember(String userId) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _householdRepository.addMember(userId);
      return result.fold(
        (_) {
          loadMembers();
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

   Future<bool> joinByInviteCode(String inviteCode) async {
     _error = null;
     notifyListeners();

     try {
       final result = await _householdRepository.joinByInviteCode(inviteCode);
       return result.fold(
         (_) {
           loadPeople();
           loadMembers();
           return true;
         },
         (failure) {
           _error = failure.message;
           notifyListeners();
           return false;
         },
       );
     } catch (e) {
       _error = e.toString();
       notifyListeners();
       return false;
     }
   }

   void setNameQuery(String query) {
     _nameQuery = query;
     notifyListeners();
   }

   void setDefaultFilter(bool? isDefault) {
     _defaultFilter = isDefault;
     notifyListeners();
   }

   void clearAllFilters() {
     _nameQuery = '';
     _defaultFilter = null;
     notifyListeners();
   }

   /// Drops all user-owned state when the authenticated identity changes.
   void reset() {
     _people = [];
     _members = [];
     _isLoading = false;
     _error = null;
     _nameQuery = '';
     _defaultFilter = null;
     notifyListeners();
   }

   void clearError() {
     _error = null;
     notifyListeners();
   }
 }