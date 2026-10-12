import 'package:flutter_test/flutter_test.dart';
import 'package:perzutv/utils/version.dart';

void main() {
  group('needUpdate', () {
    // ── 原有语义：插件版本比较（必须是纯数字版本号）───────────────────────
    group('数字版本（规则插件场景，语义不可回退）', () {
      test('远端更高 → 需要更新', () {
        expect(needUpdate('1.4', '1.5'), isTrue);
      });

      test('远端更低 → 不需要', () {
        expect(needUpdate('1.5', '1.4'), isFalse);
      });

      test('完全相同 → 不需要', () {
        expect(needUpdate('1.4', '1.4'), isFalse);
      });

      test('段数不同：1.4 vs 1.4.1', () {
        expect(needUpdate('1.4', '1.4.1'), isTrue);
        expect(needUpdate('1.4.1', '1.4'), isFalse);
      });

      test('按数值比较而非字典序：1.9 vs 1.10', () {
        expect(needUpdate('1.9', '1.10'), isTrue);
      });
    });

    // ── 本次加固：GitHub tag 的 v 前缀 ────────────────────────────────────
    // 上游实现直接 int.parse，遇到 'v1.4' 会抛 FormatException。
    group('v 前缀（应用更新检查场景）', () {
      test('0.1.0 vs v0.1.0 → 不需要', () {
        expect(needUpdate('0.1.0', 'v0.1.0'), isFalse);
      });

      test('0.1.0 vs v0.2.0 → 需要', () {
        expect(needUpdate('0.1.0', 'v0.2.0'), isTrue);
      });

      test('大写 V 前缀同样识别', () {
        expect(needUpdate('0.1.0', 'V1.0.0'), isTrue);
      });

      test('两端都带前缀', () {
        expect(needUpdate('v0.1.0', 'v0.2.0'), isTrue);
      });
    });

    // ── 本次加固：构建元数据与预发布标记 ──────────────────────────────────
    group('构建元数据 / 预发布标记', () {
      test('0.1.0 vs 0.1.0+1 → 不需要', () {
        expect(needUpdate('0.1.0', '0.1.0+1'), isFalse);
      });

      test('0.1.0 vs 0.2.0-beta.1 → 需要', () {
        expect(needUpdate('0.1.0', '0.2.0-beta.1'), isTrue);
      });

      test('两端都带构建号', () {
        expect(needUpdate('0.1.0+1', 'v0.1.0+2'), isFalse);
      });
    });

    // ── 本次加固：畸形输入不再抛异常 ──────────────────────────────────────
    group('边界输入', () {
      test('空串当作 0', () {
        expect(needUpdate('', '1.0.0'), isTrue);
        expect(needUpdate('0.1.0', ''), isFalse);
      });

      test('非数字段当作 0，不抛异常', () {
        expect(needUpdate('abc', '1.0.0'), isTrue);
      });

      test('首尾空白被忽略', () {
        expect(needUpdate(' 0.1.0 ', ' v0.2.0 '), isTrue);
      });
    });

    // ── 这个用例是本次修复的动机，保留下来防回归 ──────────────────────────
    test('回归：0.1.0 与上游 Kazumi 2.3.7 相比会判定为需要更新', () {
      // 所以更新源必须指向本分支自己的 release，
      // 不能沿用 api.kazumi.fyi / Predidit/Kazumi 的源，
      // 否则会引导用户下载原版 Kazumi 覆盖本分支。
      expect(needUpdate('0.1.0', '2.3.7'), isTrue);
    });
  });
}
