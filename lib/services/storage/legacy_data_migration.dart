import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 应用改名（kazutv → perzutv）后的数据目录迁移。
///
/// 为什么需要它：Windows 上 `getApplicationSupportDirectory()` 的路径是
/// `%APPDATA%\<CompanyName>\<ProductName>`，而这两个值来自 **exe 的版本信息**
/// （见 `windows/runner/Runner.rc`）。所以一旦把 ProductName 从 `Kazutv`
/// 改成 `Perzutv`，应用就会去看一个全新的空目录 —— 用户的规则、设置、追番、
/// 影视观看历史看起来就"全没了"。
///
/// 这里在启动早期（Hive 初始化之前）做一次性搬迁：新目录为空、且旧目录存在时，
/// 把旧目录**复制**过来。用复制而不是移动，旧数据留作退路。
///
/// 只在 Windows 生效；其它平台的数据目录不由版本信息决定。
Future<void> migrateLegacyWindowsAppDataIfNeeded() async {
  if (!Platform.isWindows) return;
  try {
    final supportDir = await getApplicationSupportDirectory();
    final current = Directory(supportDir.path);

    // 已有数据（不是空目录）说明要么已迁移过、要么是新装用户，都不动。
    if (current.existsSync() && current.listSync().isNotEmpty) return;

    final roaming = Platform.environment['APPDATA'];
    if (roaming == null || roaming.trim().isEmpty) return;

    final legacy = Directory('$roaming\\com.buffet11\\Kazutv');
    if (!legacy.existsSync()) return;

    final copied = _copyDirectory(legacy, current);
    debugPrint(
      'AppData migration: copied $copied entries from ${legacy.path} to ${current.path}',
    );
  } catch (e) {
    // 迁移失败不能拦住启动：用户最多是回到"像新装一样"，仍能正常使用。
    debugPrint('AppData migration failed: $e');
  }
}

/// 递归复制目录内容，返回复制的文件数。
int _copyDirectory(Directory from, Directory to) {
  if (!to.existsSync()) to.createSync(recursive: true);
  var count = 0;
  for (final entity in from.listSync(recursive: false)) {
    // 取名字用 path 而不是 uri：Directory.uri 对目录会带尾斜杠，
    // pathSegments.last 会是空串 —— 那样整个子目录会被跳过（hive/ 就在子目录里）。
    final segments = entity.path.split(RegExp(r'[\\/]'));
    final name = segments.isEmpty ? '' : segments.last;
    if (name.isEmpty) continue;
    final target = '${to.path}${Platform.pathSeparator}$name';

    if (entity is Directory) {
      count += _copyDirectory(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
      count++;
    }
  }
  return count;
}
