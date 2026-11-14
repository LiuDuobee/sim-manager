import 'package:flutter_test/flutter_test.dart';
import 'package:sim_manager/main.dart';

void main() {
  test('SIM 卡状态在续费日前七天内为即将续费', () {
    final now = DateTime.now();
    final card = SimCard(
      id: '1',
      nickname: '测试卡',
      operatorName: '测试运营商',
      type: SimType.physical,
      planName: '月套餐',
      monthlyFee: 10,
      renewalCycle: '月',
      nextRenewalDate: now.add(const Duration(days: 3)),
      expiryDate: now.add(const Duration(days: 30)),
    );
    expect(card.status, SimStatus.renewing);
  });
}
