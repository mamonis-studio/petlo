// ============================================================================
// petlo - NotificationBudgetAllocator Tests (build 73)
// ============================================================================
//
// Phase C の実測: ワクチンが 48/64 を占領し、schedule が押し出された。
// 3 系統の合計を見る場所が無かったことが原因。
//
// ここで固定するのは「最低保証枠 + 余りは時間軸で融通」の配分:
//   Tier 1  vaccination 16 / schedule 16 / prevention 12  (小計 44)
//   Tier 2  残り 20 + Tier 1 の余り を fireAt 昇順で先着
//   合計 64 を絶対に超えない
//
// ============================================================================

@Tags(<String>['needs_codegen'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:petlo/core/notifications/notification_budget_allocator.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 3, 12);

  /// [count] 件の候補を作る。fireAt は [dayOffset] 日後から 1 日ずつずらす。
  List<NotificationCandidate> make(
    NotificationSystem system,
    int count, {
    int dayOffset = 1,
    int idBase = 0,
  }) {
    return <NotificationCandidate>[
      for (int i = 0; i < count; i++)
        NotificationCandidate(
          system: system,
          id: idBase + i,
          fireAt: now.add(Duration(days: dayOffset + i)),
          rank: i,
          title: '${system.name} $i',
          body: '',
        ),
    ];
  }

  NotificationAllocation run(List<NotificationCandidate> candidates) {
    return NotificationBudgetAllocator.allocate(
      candidates: candidates,
      now: now,
    );
  }

  int countOf(NotificationAllocation a, NotificationSystem s) =>
      a.selected.where((NotificationCandidate c) => c.system == s).length;

  group('定数の整合', () {
    test('最低保証の合計 + 共有枠 = 64', () {
      expect(
        NotificationBudget.reservedTotal + NotificationBudget.shared,
        NotificationBudget.total,
      );
      expect(NotificationBudget.reservedTotal, 44);
      expect(NotificationBudget.shared, 20);
    });

    test('共有枠が負にならない', () {
      expect(NotificationBudget.shared, greaterThanOrEqualTo(0));
    });
  });

  group('★ワクチン50件 + schedule 3件 + 予防4コース', () {
    // ワクチン 50 件 = 100 slot (1 件 2 slot)
    // schedule 3 件 = 5 slot
    // 予防 4 コース = 20 候補
    late NotificationAllocation result;

    setUp(() {
      result = run(<NotificationCandidate>[
        ...make(NotificationSystem.vaccination, 100, idBase: 1000),
        ...make(NotificationSystem.schedule, 5, idBase: 2000),
        ...make(NotificationSystem.prevention, 20, idBase: 3000),
      ]);
    });

    test('合計が 64 を超えない', () {
      expect(result.selected, hasLength(NotificationBudget.total));
    });

    test('schedule が最低保証を下回らない', () {
      // 要求 5 < 保証 16 なので、5 件すべて通る
      expect(countOf(result, NotificationSystem.schedule), 5);
    });

    test('prevention が最低保証を下回らない', () {
      expect(
        countOf(result, NotificationSystem.prevention),
        greaterThanOrEqualTo(NotificationBudget.preventionReserve),
      );
    });

    test('ワクチンが他系統を押し潰さない', () {
      // Phase C では 48/64 (75%) を占領していた
      final int vac = countOf(result, NotificationSystem.vaccination);
      expect(vac, lessThan(48), reason: '実測時の占有量を下回ること');
      expect(vac, greaterThanOrEqualTo(NotificationBudget.vaccinationReserve),
          reason: '最低保証は確保される');
    });

    test('レポートが溢れた件数を系統別に持つ', () {
      expect(result.report.candidatesOf(NotificationSystem.vaccination), 100);
      expect(result.report.droppedOf(NotificationSystem.schedule), 0);
      expect(result.report.droppedOf(NotificationSystem.vaccination),
          greaterThan(0));
      expect(result.report.totalScheduled, NotificationBudget.total);
    });
  });

  group('★ワクチン3件しかない場合', () {
    test('余った 10 枠が他系統に流れる', () {
      // ワクチン 3 件 = 6 slot。保証 16 のうち 10 が余る。
      final NotificationAllocation r = run(<NotificationCandidate>[
        ...make(NotificationSystem.vaccination, 6, idBase: 1000),
        ...make(NotificationSystem.schedule, 40, idBase: 2000),
        ...make(NotificationSystem.prevention, 40, idBase: 3000),
      ]);

      expect(countOf(r, NotificationSystem.vaccination), 6);
      expect(r.selected, hasLength(NotificationBudget.total));

      // ワクチンが使わなかった 10 枠は schedule / prevention に回る。
      // 両者の合計は「自分の保証 + 共有枠 + ワクチンの余り」
      final int others = countOf(r, NotificationSystem.schedule) +
          countOf(r, NotificationSystem.prevention);
      expect(others, NotificationBudget.total - 6);
      expect(
        others,
        NotificationBudget.scheduleReserve +
            NotificationBudget.preventionReserve +
            NotificationBudget.shared +
            10,
        reason: 'ワクチンの余り 10 が合流している',
      );
    });

    test('他系統が無ければワクチンだけが積まれる', () {
      final NotificationAllocation r =
          run(make(NotificationSystem.vaccination, 6, idBase: 1000));
      expect(r.selected, hasLength(6));
      expect(r.report.totalDropped, 0);
    });
  });

  group('★全系統が最低保証未満', () {
    test('合計が 64 未満で全部積まれる', () {
      final NotificationAllocation r = run(<NotificationCandidate>[
        ...make(NotificationSystem.vaccination, 4, idBase: 1000),
        ...make(NotificationSystem.schedule, 3, idBase: 2000),
        ...make(NotificationSystem.prevention, 2, idBase: 3000),
      ]);
      expect(r.selected, hasLength(9));
      expect(r.selected.length, lessThan(NotificationBudget.total));
      expect(r.report.totalDropped, 0);
      for (final NotificationSystem s in NotificationSystem.values) {
        expect(r.report.droppedOf(s), 0);
      }
    });
  });

  group('★予防内部のラダーが保たれる', () {
    test('rank 先頭 4 件 (検査リマインド) が必ず残る', () {
      // 予防の planner は検査リマインドを rank 0-3 に置く。
      // どこで打ち切られても先頭が残ることを確認する。
      final List<NotificationCandidate> prevention = <NotificationCandidate>[
        // rank 0-3 = 検査リマインド。fireAt はあえて遠い未来にして、
        // fireAt 順なら落ちる位置に置く。
        for (int i = 0; i < 4; i++)
          NotificationCandidate(
            system: NotificationSystem.prevention,
            id: 3000 + i,
            fireAt: now.add(const Duration(days: 300)),
            rank: i,
            title: 'test reminder $i',
            body: '',
          ),
        // rank 4 以降 = dose。fireAt は近い。
        for (int i = 0; i < 40; i++)
          NotificationCandidate(
            system: NotificationSystem.prevention,
            id: 3100 + i,
            fireAt: now.add(Duration(days: 1 + i)),
            rank: 4 + i,
            title: 'dose $i',
            body: '',
          ),
      ];

      final NotificationAllocation r = run(<NotificationCandidate>[
        ...make(NotificationSystem.vaccination, 100, idBase: 1000),
        ...make(NotificationSystem.schedule, 100, idBase: 2000),
        ...prevention,
      ]);

      // 予防は最低保証を必ず確保する。Tier 2 で fireAt が近ければ
      // それ以上取ることもある (dose の予定日が直近に固まっている場合)。
      expect(
        countOf(r, NotificationSystem.prevention),
        greaterThanOrEqualTo(NotificationBudget.preventionReserve),
      );

      // 検査リマインドは fireAt が 300 日先で Tier 2 では絶対に勝てない。
      // それでも残るのは Tier 1 が rank 順だから。
      final List<NotificationCandidate> got = r.selected
          .where((NotificationCandidate c) =>
              c.system == NotificationSystem.prevention)
          .toList();
      for (int i = 0; i < 4; i++) {
        expect(got.any((NotificationCandidate c) => c.id == 3000 + i), isTrue,
            reason: '検査リマインド (rank $i) が予約枠から落ちてはいけない');
      }
    });

    test('Tier 1 は fireAt ではなく rank で選ぶ', () {
      // rank が優先されることを、fireAt を逆順にして確認する
      final List<NotificationCandidate> prevention = <NotificationCandidate>[
        for (int i = 0; i < 20; i++)
          NotificationCandidate(
            system: NotificationSystem.prevention,
            id: 3000 + i,
            fireAt: now.add(Duration(days: 100 - i)),
            rank: i,
            title: 'p$i',
            body: '',
          ),
      ];
      final NotificationAllocation r = run(<NotificationCandidate>[
        ...make(NotificationSystem.vaccination, 100, idBase: 1000),
        ...make(NotificationSystem.schedule, 100, idBase: 2000),
        ...prevention,
      ]);
      final List<int> ids = r.selected
          .where((NotificationCandidate c) =>
              c.system == NotificationSystem.prevention)
          .map((NotificationCandidate c) => c.id)
          .toList();
      expect(ids, <int>[for (int i = 0; i < 12; i++) 3000 + i]);
    });
  });

  group('既存ルール', () {
    test('過去日は積まない', () {
      final NotificationAllocation r =
          NotificationBudgetAllocator.allocate(
        candidates: <NotificationCandidate>[
          NotificationCandidate(
            system: NotificationSystem.vaccination,
            id: 1,
            fireAt: now.subtract(const Duration(days: 1)),
            rank: 0,
            title: 'past',
            body: '',
          ),
          NotificationCandidate(
            system: NotificationSystem.vaccination,
            id: 2,
            fireAt: now.add(const Duration(days: 1)),
            rank: 1,
            title: 'future',
            body: '',
          ),
        ],
        now: now,
      );
      expect(r.selected, hasLength(1));
      expect(r.selected.single.id, 2);
      // 過去日は「溢れた」ではなく候補にすら入らない
      expect(r.report.candidatesOf(NotificationSystem.vaccination), 1);
      expect(r.report.totalDropped, 0);
    });

    test('候補が空なら何も積まない', () {
      final NotificationAllocation r = run(<NotificationCandidate>[]);
      expect(r.selected, isEmpty);
      expect(r.report.totalScheduled, 0);
    });

    test('Tier 2 は系統をまたいで fireAt 昇順', () {
      // 保証枠を 0 にして Tier 2 のみで判定する
      final NotificationAllocation r =
          NotificationBudgetAllocator.allocate(
        candidates: <NotificationCandidate>[
          NotificationCandidate(
            system: NotificationSystem.vaccination,
            id: 1,
            fireAt: now.add(const Duration(days: 10)),
            rank: 0,
            title: 'late vaccination',
            body: '',
          ),
          NotificationCandidate(
            system: NotificationSystem.schedule,
            id: 2,
            fireAt: now.add(const Duration(days: 1)),
            rank: 0,
            title: 'soon schedule',
            body: '',
          ),
        ],
        now: now,
        total: 1,
        reserveOverride: <NotificationSystem, int>{
          NotificationSystem.vaccination: 0,
          NotificationSystem.schedule: 0,
          NotificationSystem.prevention: 0,
        },
      );
      expect(r.selected.single.id, 2, reason: '直近のものが勝つ');
    });
  });

  group('キルスイッチ (予防の枠を 0 にする)', () {
    test('予防の保証枠が他系統へ流れる', () {
      final NotificationAllocation r =
          NotificationBudgetAllocator.allocate(
        candidates: <NotificationCandidate>[
          ...make(NotificationSystem.vaccination, 100, idBase: 1000),
          ...make(NotificationSystem.schedule, 100, idBase: 2000),
        ],
        now: now,
        reserveOverride: <NotificationSystem, int>{
          NotificationSystem.vaccination:
              NotificationBudget.vaccinationReserve,
          NotificationSystem.schedule: NotificationBudget.scheduleReserve,
          NotificationSystem.prevention: 0,
        },
      );
      expect(r.selected, hasLength(NotificationBudget.total));
      expect(countOf(r, NotificationSystem.prevention), 0);
    });
  });

  group('レポート', () {
    test('JSON で往復できる (永続化して開発者設定で読む)', () {
      final NotificationAllocation r = run(<NotificationCandidate>[
        ...make(NotificationSystem.vaccination, 100, idBase: 1000),
        ...make(NotificationSystem.schedule, 5, idBase: 2000),
        ...make(NotificationSystem.prevention, 20, idBase: 3000),
      ]);
      final NotificationAllocationReport? back =
          NotificationAllocationReport.fromJson(r.report.toJson());
      expect(back, isNotNull);
      for (final NotificationSystem s in NotificationSystem.values) {
        expect(back!.scheduledOf(s), r.report.scheduledOf(s));
        expect(back.candidatesOf(s), r.report.candidatesOf(s));
      }
    });

    test('summary が系統別の内訳を含む', () {
      final NotificationAllocation r = run(<NotificationCandidate>[
        ...make(NotificationSystem.vaccination, 100, idBase: 1000),
      ]);
      expect(r.report.summary, contains('vaccination='));
      expect(r.report.summary, contains('total='));
      expect(r.report.summary, contains('dropped='));
    });
  });
}
