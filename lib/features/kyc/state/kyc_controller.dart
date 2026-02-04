import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';

@immutable
class KycLocalState {
  const KycLocalState({
    required this.status,
    required this.waitlistJoined,
    required this.myPublishCount,
  });

  final String status; // none|pending|approved|rejected
  final bool waitlistJoined;
  final int myPublishCount;

  KycLocalState copyWith({
    String? status,
    bool? waitlistJoined,
    int? myPublishCount,
  }) {
    return KycLocalState(
      status: status ?? this.status,
      waitlistJoined: waitlistJoined ?? this.waitlistJoined,
      myPublishCount: myPublishCount ?? this.myPublishCount,
    );
  }
}

class KycController extends Notifier<KycLocalState> {
  @override
  KycLocalState build() {
    final store = ref.read(localStoreProvider);
    return KycLocalState(
      status: store.getKycStatus(),
      waitlistJoined: store.getKycWaitlistJoined(),
      myPublishCount: store.getMyPublishCount(),
    );
  }

  Future<void> joinWaitlist() async {
    final store = ref.read(localStoreProvider);
    await store.setKycWaitlistJoined(true);
    state = state.copyWith(waitlistJoined: true);
  }

  Future<void> setStatus(String status) async {
    final store = ref.read(localStoreProvider);
    await store.setKycStatus(status);
    state = state.copyWith(status: status);
  }

  Future<void> incrementPublishCount() async {
    final store = ref.read(localStoreProvider);
    await store.incrementMyPublishCount();
    state = state.copyWith(myPublishCount: store.getMyPublishCount());
  }
}

final kycControllerProvider =
    NotifierProvider<KycController, KycLocalState>(() {
  return KycController();
});
