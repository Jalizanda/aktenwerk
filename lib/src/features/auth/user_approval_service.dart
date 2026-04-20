import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/auth_service.dart';
import '../../data/sync/firebase_init.dart';

/// Globaler App-User (pro Firebase-Auth-UID ein Dokument in `/users`).
class AppUser {
  final String uid;
  final String? email;
  final String? displayName;
  final bool approved;
  final bool isSuperAdmin;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final String? approvedBy;

  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.approved = false,
    this.isSuperAdmin = false,
    this.createdAt,
    this.approvedAt,
    this.approvedBy,
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppUser(
      uid: d.id,
      email: m['email'] as String?,
      displayName: m['displayName'] as String?,
      approved: m['approved'] as bool? ?? false,
      isSuperAdmin: m['isSuperAdmin'] as bool? ?? false,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      approvedAt: (m['approvedAt'] as Timestamp?)?.toDate(),
      approvedBy: m['approvedBy'] as String?,
    );
  }
}

/// Stellt sicher, dass für jeden eingeloggten Firebase-User ein Dokument in
/// `/users/{uid}` existiert. Enthält das Approval-Flag und die Super-Admin-
/// Markierung. Beim allerersten Benutzer (noch kein anderer approveder
/// Super-Admin vorhanden) wird dieser automatisch Super-Admin und approved.
class UserApprovalService {
  UserApprovalService(this._auth);
  final AuthService _auth;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// Stream auf das User-Dokument des aktuellen Users (legt es initial an).
  Stream<AppUser?> watchCurrentUser() async* {
    final user = _auth.currentUser;
    if (user == null || !FirebaseBootstrap.isReady) {
      yield null;
      return;
    }
    // Sicherstellen, dass das Dokument existiert.
    await ensureUserDoc(user);
    yield* _userDoc(user.uid).snapshots().map((s) {
      if (!s.exists) return null;
      return AppUser.fromDoc(s);
    });
  }

  /// E-Mail-Adresse, die bei der Anlage automatisch Super-Admin wird.
  /// Server-seitig zusätzlich in den Firestore-Rules gegen
  /// `request.auth.token.email` verifiziert.
  static const superAdminEmail = 'alexander.hoepken@gmail.com';

  /// ID der öffentlichen Demo-Organisation. Wird einmal beim Bootstrap des
  /// Super-Admins angelegt und mit Demo-Daten befüllt. Jeder freigegebene
  /// User wird automatisch als Leser dieser Org eingetragen.
  static const demoOrgId = 'demo';
  static const demoOrgName = 'Demo — Bauelemente-Experte (Testdaten)';
  static const produktivOrgName = 'Bauelemente-Experte';

  /// Legt das User-Dokument an, falls es noch nicht existiert.
  /// Wenn die E-Mail des Users mit [superAdminEmail] übereinstimmt, wird er
  /// automatisch als approved + isSuperAdmin angelegt und die initialen
  /// Organisationen (Demo + Produktiv) werden sichergestellt.
  Future<void> ensureUserDoc(User user) async {
    final doc = await _userDoc(user.uid).get();
    final email = (user.email ?? '').toLowerCase().trim();
    final isBootstrap = email == superAdminEmail;

    if (doc.exists) {
      if (isBootstrap &&
          (doc.data()?['isSuperAdmin'] != true ||
              doc.data()?['approved'] != true)) {
        await _userDoc(user.uid).update({
          'approved': true,
          'isSuperAdmin': true,
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': 'bootstrap',
        });
      }
    } else {
      await _userDoc(user.uid).set({
        'email': user.email,
        'displayName': user.displayName,
        'approved': isBootstrap,
        'isSuperAdmin': isBootstrap,
        'createdAt': FieldValue.serverTimestamp(),
        if (isBootstrap) 'approvedAt': FieldValue.serverTimestamp(),
        if (isBootstrap) 'approvedBy': 'bootstrap',
      });
    }

    // Initiales Org-Setup: Demo + Produktiv-Mandant, nur für Super-Admin.
    if (isBootstrap) {
      await _ensureSuperAdminOrgs(user);
    } else if (doc.data()?['approved'] == true) {
      // Freigegebene, normale User: sicherstellen, dass sie Leser der Demo-Org sind.
      await _joinDemoOrg(user);
    }
  }

  Future<void> _ensureSuperAdminOrgs(User user) async {
    final uid = user.uid;

    // Demo-Mandant (feste ID)
    final demoRef = _db.collection('organizations').doc(demoOrgId);
    final demoSnap = await demoRef.get();
    if (!demoSnap.exists) {
      await demoRef.set({
        'name': demoOrgName,
        'beschreibung':
            'Öffentlicher Demo-Mandant mit Beispieldaten zum Ausprobieren. '
            'Alle registrierten Nutzer haben Lesezugriff.',
        'ownerUid': uid,
        'approved': true,
        'isDemo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': uid,
      });
      await demoRef.collection('members').doc(uid).set({
        'role': 'owner',
        'email': user.email,
        'displayName': user.displayName,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      await _db
          .collection('users')
          .doc(uid)
          .collection('memberships')
          .doc(demoOrgId)
          .set({
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }

    // Produktiv-Mandant „Bauelemente-Experte"
    final beQuery = await _db
        .collection('organizations')
        .where('ownerUid', isEqualTo: uid)
        .where('name', isEqualTo: produktivOrgName)
        .limit(1)
        .get();
    if (beQuery.docs.isEmpty) {
      final beRef = _db.collection('organizations').doc();
      await beRef.set({
        'name': produktivOrgName,
        'beschreibung': 'Produktiver Mandant.',
        'ownerUid': uid,
        'approved': true,
        'isDemo': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': uid,
      });
      await beRef.collection('members').doc(uid).set({
        'role': 'owner',
        'email': user.email,
        'displayName': user.displayName,
        'joinedAt': FieldValue.serverTimestamp(),
      });
      await _db
          .collection('users')
          .doc(uid)
          .collection('memberships')
          .doc(beRef.id)
          .set({
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Ergänzt einen freigegebenen User als `readonly`-Mitglied der Demo-Org.
  Future<void> _joinDemoOrg(User user) async {
    final demoRef = _db.collection('organizations').doc(demoOrgId);
    final demoSnap = await demoRef.get();
    if (!demoSnap.exists) return;
    final uid = user.uid;
    final memberRef = demoRef.collection('members').doc(uid);
    if ((await memberRef.get()).exists) return;
    await memberRef.set({
      'role': 'readonly',
      'email': user.email,
      'displayName': user.displayName,
      'joinedAt': FieldValue.serverTimestamp(),
      'autoJoined': true,
    });
    await _db
        .collection('users')
        .doc(uid)
        .collection('memberships')
        .doc(demoOrgId)
        .set({
      'role': 'readonly',
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AppUser>> watchAllUsers() {
    return _db
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(AppUser.fromDoc).toList());
  }

  Stream<List<AppUser>> watchPendingUsers() {
    return _db
        .collection('users')
        .where('approved', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.map(AppUser.fromDoc).toList());
  }

  Future<void> approve(String uid) async {
    final me = _auth.currentUser?.uid;
    await _userDoc(uid).update({
      'approved': true,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': me,
    });
    // Automatisch zur Demo-Org als `readonly` hinzufügen.
    try {
      final userSnap = await _userDoc(uid).get();
      final demoRef = _db.collection('organizations').doc(demoOrgId);
      if ((await demoRef.get()).exists) {
        final memRef = demoRef.collection('members').doc(uid);
        if (!(await memRef.get()).exists) {
          await memRef.set({
            'role': 'readonly',
            'email': userSnap.data()?['email'],
            'displayName': userSnap.data()?['displayName'],
            'joinedAt': FieldValue.serverTimestamp(),
            'autoJoined': true,
          });
          await _db
              .collection('users')
              .doc(uid)
              .collection('memberships')
              .doc(demoOrgId)
              .set({
            'role': 'readonly',
            'joinedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (_) {
      // Fehler beim Demo-Join sind nicht kritisch – User ist trotzdem approved.
    }
  }

  Future<void> revokeApproval(String uid) async {
    await _userDoc(uid).update({'approved': false});
  }

  Future<void> setSuperAdmin(String uid, bool value) async {
    await _userDoc(uid).update({'isSuperAdmin': value});
  }
}

final userApprovalServiceProvider = Provider<UserApprovalService>((ref) {
  return UserApprovalService(ref.watch(authServiceProvider));
});

/// Das User-Dokument für den aktuell eingeloggten User (oder null, wenn
/// niemand eingeloggt ist). Wird beim Login automatisch angelegt.
final currentUserDocProvider = StreamProvider<AppUser?>((ref) {
  ref.watch(authStateProvider); // bei Login/Logout neu anstoßen
  return ref.watch(userApprovalServiceProvider).watchCurrentUser();
});

final pendingUsersProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(userApprovalServiceProvider).watchPendingUsers();
});

final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(userApprovalServiceProvider).watchAllUsers();
});
