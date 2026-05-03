import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'firebase_init.dart';

/// Rolle eines Members innerhalb einer Organisation.
enum OrgRole { owner, admin, member, readonly }

extension OrgRoleX on OrgRole {
  String get dbValue => name;
  String get label => switch (this) {
        OrgRole.owner => 'Inhaber',
        OrgRole.admin => 'Administrator',
        OrgRole.member => 'Mitarbeiter',
        OrgRole.readonly => 'Lesezugriff',
      };
  bool get canManageMembers =>
      this == OrgRole.owner || this == OrgRole.admin;
  bool get canWrite =>
      this == OrgRole.owner ||
      this == OrgRole.admin ||
      this == OrgRole.member;

  static OrgRole fromDb(String? s) =>
      OrgRole.values.firstWhere((r) => r.name == s,
          orElse: () => OrgRole.member);
}

/// Zusammenfassung einer Organisation (Stammdaten + Rolle des Users).
class OrgSummary {
  final String id;
  final String name;
  final String? beschreibung;
  final OrgRole role;
  final DateTime? createdAt;
  final bool approved;
  const OrgSummary({
    required this.id,
    required this.name,
    this.beschreibung,
    required this.role,
    this.createdAt,
    this.approved = false,
  });
}

/// Einladungs-Eintrag.
class OrgInvite {
  final String code;
  final String orgId;
  final String orgName;
  final String invitedByUid;
  final OrgRole role;
  final DateTime expiresAt;
  const OrgInvite({
    required this.code,
    required this.orgId,
    required this.orgName,
    required this.invitedByUid,
    required this.role,
    required this.expiresAt,
  });
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class OrgService {
  OrgService(this._auth);
  final AuthService _auth;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  bool get enabled => FirebaseBootstrap.isReady;
  String? get _uid => _auth.currentUser?.uid;

  // --------------------- Current Org (lokal) ---------------------

  static const _prefKey = 'current_org_id';

  Future<String?> getCurrentOrgId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  Future<void> setCurrentOrgId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, id);
    }
  }

  // --------------------- Memberships ---------------------

  /// Beobachtet alle Orgs, in denen der aktuelle User Mitglied ist.
  Stream<List<OrgSummary>> watchMyOrgs() {
    final uid = _uid;
    if (!enabled || uid == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(uid)
        .collection('memberships')
        .snapshots()
        .asyncMap((snap) async {
      final out = <OrgSummary>[];
      for (final doc in snap.docs) {
        final orgId = doc.id;
        final role = OrgRoleX.fromDb(doc.data()['role']?.toString());
        final orgDoc = await _db.collection('organizations').doc(orgId).get();
        if (!orgDoc.exists) continue;
        final o = orgDoc.data() ?? {};
        out.add(OrgSummary(
          id: orgId,
          name: o['name']?.toString() ?? 'Organisation',
          beschreibung: o['beschreibung']?.toString(),
          role: role,
          createdAt: (o['createdAt'] as Timestamp?)?.toDate(),
          approved: o['approved'] as bool? ?? false,
        ));
      }
      out.sort((a, b) => a.name.compareTo(b.name));
      return out;
    });
  }

  // --------------------- Org anlegen / löschen ---------------------

  /// Legt eine neue Organisation an und macht den aktuellen User zum Owner.
  ///
  /// Wichtig: Die drei Writes laufen **sequenziell**, nicht als Batch.
  /// Grund: Firestore-Security-Rules werten jede Operation eines Batches
  /// gegen den Zustand *vor* dem Batch aus. Die Regel für `members/{uid}`
  /// prüft aber per `get(organizations/{orgId})`, dass der aktuelle User
  /// der Owner ist – die Org muss dafür bereits existieren.
  Future<String> createOrg({
    required String name,
    String? beschreibung,
  }) async {
    final uid = _uid;
    if (!enabled || uid == null) {
      throw StateError('Nicht angemeldet.');
    }
    final ref = _db.collection('organizations').doc();

    // 14-Tage-Test ab Anlage; Super-Admin schaltet anschließend frei.
    final now = DateTime.now();
    final trialEnde = now.add(const Duration(days: 14));

    // 1) Org-Dokument (approved: false — wartet auf Super-Admin)
    await ref.set({
      'name': name,
      'beschreibung': beschreibung,
      'ownerUid': uid,
      'approved': false,
      'subscriptionStatus': 'trial',
      'trialStartedAt': Timestamp.fromDate(now),
      'trialEndsAt': Timestamp.fromDate(trialEnde),
      'pricePerUserCents': 790,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // 2) Owner-Mitgliedschaft (Rule liest jetzt die existierende Org).
    await ref.collection('members').doc(uid).set({
      'role': OrgRole.owner.dbValue,
      'email': _auth.currentUser?.email,
      'displayName': _auth.currentUser?.displayName,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    // 3) Reverse-Lookup (Self-Write).
    await _db
        .collection('users')
        .doc(uid)
        .collection('memberships')
        .doc(ref.id)
        .set({
      'role': OrgRole.owner.dbValue,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await setCurrentOrgId(ref.id);
    return ref.id;
  }

  // --------------------- Mitglieder-Verwaltung ---------------------

  Stream<List<OrgMember>> watchMembers(String orgId) {
    if (!enabled) return const Stream.empty();
    return _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              return OrgMember(
                uid: d.id,
                email: data['email']?.toString(),
                displayName: data['displayName']?.toString(),
                role: OrgRoleX.fromDb(data['role']?.toString()),
                joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
                erlaubteModule: data['erlaubteModule']?.toString(),
                bearbeitbareModule: data['bearbeitbareModule']?.toString(),
                isDummy: data['isDummy'] == true,
              );
            }).toList());
  }

  /// Setzt die Modul-Berechtigungen eines Mitglieds.
  Future<void> setMemberPermissions(
    String orgId,
    String uid, {
    required String erlaubteModule,
    required String bearbeitbareModule,
  }) async {
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(uid)
        .update({
      'erlaubteModule': erlaubteModule,
      'bearbeitbareModule': bearbeitbareModule,
    });
  }

  /// Legt einen Dummy-/Test-Benutzer im Mandanten an (kein Firebase-Auth-Konto).
  /// Dummy-User-IDs beginnen mit `dummy_`.
  Future<void> createDummyMember(
    String orgId, {
    required String displayName,
    required String email,
    required OrgRole role,
  }) async {
    final uid = 'dummy_${DateTime.now().millisecondsSinceEpoch}';
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(uid)
        .set({
      'email': email,
      'displayName': displayName,
      'role': role.dbValue,
      'joinedAt': FieldValue.serverTimestamp(),
      'isDummy': true,
    });
  }

  Future<void> setMemberRole(
      String orgId, String uid, OrgRole role) async {
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(uid)
        .update({'role': role.dbValue});
    await _db
        .collection('users')
        .doc(uid)
        .collection('memberships')
        .doc(orgId)
        .update({'role': role.dbValue});
  }

  Future<void> removeMember(String orgId, String uid) async {
    final batch = _db.batch();
    batch.delete(_db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(uid));
    batch.delete(_db
        .collection('users')
        .doc(uid)
        .collection('memberships')
        .doc(orgId));
    await batch.commit();
  }

  // --------------------- Einladungen ---------------------

  /// Erzeugt einen Einladungs-Code (8 Zeichen), gültig 14 Tage.
  Future<String> createInvite(String orgId,
      {OrgRole role = OrgRole.member}) async {
    final uid = _uid;
    if (!enabled || uid == null) throw StateError('Nicht angemeldet.');
    final code = _generateCode();
    final orgSnap = await _db.collection('organizations').doc(orgId).get();
    final orgName = orgSnap.data()?['name']?.toString() ?? 'Organisation';
    await _db.collection('invites').doc(code).set({
      'orgId': orgId,
      'orgName': orgName,
      'invitedByUid': uid,
      'role': role.dbValue,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 14))),
    });
    return code;
  }

  Future<OrgInvite?> lookupInvite(String code) async {
    final doc = await _db.collection('invites').doc(code.toUpperCase()).get();
    if (!doc.exists) return null;
    final d = doc.data()!;
    final exp = (d['expiresAt'] as Timestamp?)?.toDate() ??
        DateTime.now().subtract(const Duration(days: 1));
    return OrgInvite(
      code: code.toUpperCase(),
      orgId: d['orgId']?.toString() ?? '',
      orgName: d['orgName']?.toString() ?? '',
      invitedByUid: d['invitedByUid']?.toString() ?? '',
      role: OrgRoleX.fromDb(d['role']?.toString()),
      expiresAt: exp,
    );
  }

  Future<void> redeemInvite(String code) async {
    final uid = _uid;
    if (!enabled || uid == null) throw StateError('Nicht angemeldet.');
    final normalized = code.trim().toUpperCase();
    final invite = await lookupInvite(normalized);
    if (invite == null) throw StateError('Einladungs-Code unbekannt.');
    if (invite.isExpired) {
      throw StateError('Einladung ist abgelaufen.');
    }
    // Sequenziell statt Batch, damit die Rules den Invite-Code jeweils gegen
    // den aktuellen State prüfen können.
    await _db
        .collection('organizations')
        .doc(invite.orgId)
        .collection('members')
        .doc(uid)
        .set({
      'role': invite.role.dbValue,
      'email': _auth.currentUser?.email,
      'displayName': _auth.currentUser?.displayName,
      'joinedAt': FieldValue.serverTimestamp(),
      'invitedByUid': invite.invitedByUid,
      // Wird von den Security-Rules geprüft: Nur mit gültigem Invite-Code
      // darf ein User sich selbst in eine fremde Org eintragen.
      'inviteCode': normalized,
    });
    await _db
        .collection('users')
        .doc(uid)
        .collection('memberships')
        .doc(invite.orgId)
        .set({
      'role': invite.role.dbValue,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    // Einladung „verbrauchen" (einmalig nutzbar).
    await _db.collection('invites').doc(normalized).delete();
    await setCurrentOrgId(invite.orgId);
  }

  String _generateCode() {
    final chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // ohne 0/O/1/I
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = now ^ (now << 13) ^ (now >> 7);
    var seed = rand.abs();
    final buf = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buf.writeCharCode(chars.codeUnitAt(seed % chars.length));
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    }
    return buf.toString();
  }
}

class OrgMember {
  final String uid;
  final String? email;
  final String? displayName;
  final OrgRole role;
  final DateTime? joinedAt;
  /// Komma-getrennte Liste erlaubter Modul-Keys; `null` = alle.
  final String? erlaubteModule;
  /// Komma-getrennte Liste bearbeitbarer Modul-Keys; `null` = alle.
  final String? bearbeitbareModule;
  final bool isDummy;
  const OrgMember({
    required this.uid,
    this.email,
    this.displayName,
    required this.role,
    this.joinedAt,
    this.erlaubteModule,
    this.bearbeitbareModule,
    this.isDummy = false,
  });
}

final orgServiceProvider = Provider<OrgService>((ref) {
  return OrgService(ref.watch(authServiceProvider));
});

/// Alle Orgs, in denen der aktuelle User Mitglied ist.
final myOrgsProvider = StreamProvider<List<OrgSummary>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(orgServiceProvider).watchMyOrgs();
});

/// Aktive Organisation. Wird persistent in SharedPreferences gehalten.
class CurrentOrgNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    ref.watch(authStateProvider);
    return ref.read(orgServiceProvider).getCurrentOrgId();
  }

  Future<void> set(String? id) async {
    state = AsyncData(id);
    await ref.read(orgServiceProvider).setCurrentOrgId(id);
  }
}

final currentOrgIdProvider =
    AsyncNotifierProvider<CurrentOrgNotifier, String?>(
        CurrentOrgNotifier.new);
