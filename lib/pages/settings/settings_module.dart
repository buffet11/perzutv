import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:perzutv/pages/about/about_module.dart';
import 'package:perzutv/pages/logs/logs_page.dart';
import 'package:perzutv/pages/settings/danmaku/danmaku_module.dart';
import 'package:perzutv/pages/settings/decoder_settings.dart';
import 'package:perzutv/pages/settings/displaymode_settings.dart';
import 'package:perzutv/pages/settings/interface_settings.dart';
import 'package:perzutv/pages/settings/keyboard_settings.dart';
import 'package:perzutv/pages/settings/movie/movie_source_settings.dart';
import 'package:perzutv/pages/settings/movie/parse_source_settings.dart';
import 'package:perzutv/pages/settings/player_settings.dart';
import 'package:perzutv/pages/settings/proxy/proxy_module.dart';
import 'package:perzutv/pages/settings/renderer_settings.dart';
import 'package:perzutv/pages/settings/settings_page.dart';
import 'package:perzutv/pages/settings/storage_settings.dart';
import 'package:perzutv/pages/settings/super_resolution_settings.dart';
import 'package:perzutv/pages/settings/theme_settings_page.dart';
import 'package:perzutv/pages/settings/update_settings.dart';
import 'package:perzutv/pages/settings/watch_records_page.dart';
import 'package:perzutv/request/config/api_endpoints.dart';

final settingsModule = createModule(
  path: '/settings',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => SettingsPage(location: state.uri.path),
      children: (sub) {
        sub
          ..route('/', child: (context, state) => const SettingsIndexPage())
          ..route(
            '/update',
            child: (context, state) => const UpdateSettingsPage(),
          )
          ..route(
            '/movie-source',
            child: (context, state) => const MovieSourceSettingsPage(),
          )
          ..route(
            '/parse-source',
            child: (context, state) => const ParseSourceSettingsPage(),
          )
          ..route(
            '/storage',
            child: (context, state) => const StorageSettingsPage(),
          )
          ..route(
            '/records',
            child: (context, state) => const WatchRecordsPage(),
          )
          ..route('/storage/logs', child: (context, state) => const LogsPage())
          ..route('/theme',
              child: (context, state) => const ThemeSettingsPage())
          ..route(
            '/theme/display',
            child: (context, state) => const SetDisplayMode(),
          )
          ..route(
            '/keyboard',
            child: (context, state) => const KeyboardSettingsPage(),
          )
          ..route('/player',
              child: (context, state) => const PlayerSettingsPage())
          ..route(
            '/player/decoder',
            child: (context, state) => const DecoderSettings(),
          )
          ..route(
            '/player/renderer',
            child: (context, state) => const RendererSettings(),
          )
          ..route(
            '/interface',
            child: (context, state) => const InterfaceSettingsPage(),
          )
          ..module(proxyModule)
          ..route(
            '/player/super',
            child: (context, state) => const SuperResolutionSettings(),
          )
          ..module(aboutModule)
          ..module(danmakuModule);
      },
    );
    c
      // Root route: the license browser must cover the settings shell.
      ..route(
        '/about/license',
        child: (context, state) => const LicensePage(
          applicationName: 'Perzutv',
          applicationVersion: ApiEndpoints.version,
          applicationLegalese: 'Perzutv · GNU General Public License v3.0',
        ),
      );
  },
);
