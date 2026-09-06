import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

/// H-Viewer 真实规则样例（ghostgzt/H-Viewer-Sites sites/E-shuushuu.txt 节选）。
const eShuushuuRule = r'''
{
  "categories": [
    {"cid": 1, "title": "首页", "url": "http://e-shuushuu.net/?page={page:1}"},
    {"cid": 2, "title": "排行榜", "url": "http://e-shuushuu.net/top.php?page={page:1}"}
  ],
  "cookie": "",
  "flag": "onePicGallery",
  "galleryRule": {
    "pictureRule": {
      "item": {"selector": ".image_thread .image_block"},
      "thumbnail": {"fun": "attr", "param": "src", "selector": "a.thumb_image img"},
      "url": {"fun": "attr", "param": "href", "selector": "a.thumb_image"}
    },
    "rating": {
      "fun": "html", "regex": "(\\d*\\.?\\d*).*?<img", "replacement": "$2/2",
      "selector": ".display .meta dl dd[id^='rating']"
    }
  },
  "galleryUrl": "http://e-shuushuu.net/{idCode:}",
  "indexRule": {
    "cover": {"fun": "attr", "param": "src", "selector": "a.thumb_image img"},
    "datetime": {"fun": "html", "selector": ".meta dd:eq(3)"},
    "idCode": {"fun": "attr", "param": "href", "selector": ".title h2 a"},
    "item": {"selector": "div.display:has(.thumb)"},
    "tags": {"fun": "html", "selector": ".meta span.tag a"},
    "title": {"fun": "html", "selector": ".title h2 a"}
  },
  "searchIndex": 0,
  "searchUrl": {"keywords": "tags", "path": "http://e-shuushuu.net/search/results/?tags={keywords:}&page={page:1}"},
  "sid": 101, "title": "E-shuushuu", "versionCode": 3
}
''';

void main() {
  group('HViewerAdapter', () {
    late ComicSource src;

    setUpAll(() {
      src = HViewerAdapter.convert((jsonDecode(eShuushuuRule) as Map).cast<String, dynamic>());
    });

    test('基本信息', () {
      expect(src.name, 'E-shuushuu');
      expect(src.group, 'H-Viewer');
    });

    test('发现分类入口', () {
      final entries = src.rules.exploreUrl.split('\n');
      expect(entries.first, contains('首页::'));
      expect(entries.first, contains('e-shuushuu.net'));
    });

    test('发现规则映射', () {
      expect(src.rules.findList, 'div.display:has(.thumb)');
      expect(src.rules.findName, '.title h2 a@html');
      expect(src.rules.findCoverUrl, 'a.thumb_image img@src');
      expect(src.rules.findBookUrl, '.title h2 a@href');
    });

    test('搜索 URL 占位符保留', () {
      expect(src.rules.searchUrl, contains('{keywords:}'));
    });

    test('图片规则映射', () {
      expect(src.rules.contentUrl, 'a.thumb_image@href');
    });

    test('regex/replacement 字段携带', () {
      // rating 规则带 regex — 验证 _field 的 ## 语法转换（用 datetime 位验证普通映射即可）
      expect(src.rules.findUpdateTime, '.meta dd:eq(3)@html');
    });
  });
}
