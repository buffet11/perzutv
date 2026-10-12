import 'package:flutter_modular/flutter_modular.dart';
import 'package:perzutv/core_module.dart';
import 'package:perzutv/pages/index_module.dart';

final appModule = createModule(
  register: (c) {
    c
      ..module(coreModule)
      ..module(indexModule);
  },
);
