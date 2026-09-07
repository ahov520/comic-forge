import 'package:flutter/material.dart';

import 'package:engine/engine.dart';

import '../services/source_service.dart';
import '../state/app_state.dart';
import '../state/source_form.dart';

/// 源编辑器：新建/编辑源规则 + 规则试跑（搜索 → 目录 → 图片 三级钻取）。
class SourceEditorScreen extends StatefulWidget {
  const SourceEditorScreen({super.key, required this.state, this.source});

  final AppState state;
  final ComicSource? source; // null = 新建

  @override
  State<SourceEditorScreen> createState() => _SourceEditorScreenState();
}

class _SourceEditorScreenState extends State<SourceEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _group;
  late final TextEditingController _headers;
  late final TextEditingController _searchUrl;
  late final TextEditingController _searchList;
  late final TextEditingController _searchName;
  late final TextEditingController _searchAuthor;
  late final TextEditingController _searchCover;
  late final TextEditingController _searchBookUrl;
  late final TextEditingController _findUrl;
  late final TextEditingController _chapterList;
  late final TextEditingController _chapterName;
  late final TextEditingController _chapterUrl;
  late final TextEditingController _contentUrl;
  late final TextEditingController _contentUrlNext;

  final _keyword = TextEditingController();

  // 试跑状态（三级钻取）
  bool _trialSearching = false;
  String? _trialError;
  List<Book> _trialResults = const [];
  Book? _trialBook;
  bool _trialDetailLoading = false;
  List<Chapter> _trialChapters = const [];
  bool _trialImagesLoading = false;
  List<String> _trialImages = const [];

  bool get _isEditing => widget.source != null;

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    _name = TextEditingController(text: s?.name ?? '');
    _url = TextEditingController(text: s?.url ?? '');
    _group = TextEditingController(text: s?.group ?? '');
    _headers = TextEditingController(
        text: s?.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n') ?? '');
    _searchUrl = TextEditingController(text: s?.rules.searchUrl ?? '');
    _searchList = TextEditingController(text: s?.rules.searchList ?? '');
    _searchName = TextEditingController(text: s?.rules.searchName ?? '');
    _searchAuthor = TextEditingController(text: s?.rules.searchAuthor ?? '');
    _searchCover = TextEditingController(text: s?.rules.searchCoverUrl ?? '');
    _searchBookUrl = TextEditingController(text: s?.rules.searchBookUrl ?? '');
    _findUrl = TextEditingController(
        text: s == null
            ? ''
            : s.rules.findUrl.isNotEmpty
                ? s.rules.findUrl
                : s.rules.exploreUrl);
    _chapterList = TextEditingController(text: s?.rules.chapterList ?? '');
    _chapterName = TextEditingController(text: s?.rules.chapterName ?? '');
    _chapterUrl = TextEditingController(text: s?.rules.chapterUrl ?? '');
    _contentUrl = TextEditingController(text: s?.rules.contentUrl ?? '');
    _contentUrlNext = TextEditingController(text: s?.rules.contentUrlNext ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _name, _url, _group, _headers, _searchUrl, _searchList, _searchName,
      _searchAuthor, _searchCover, _searchBookUrl, _findUrl, _chapterList,
      _chapterName, _chapterUrl, _contentUrl, _contentUrlNext, _keyword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  SourceBuildResult _build() => SourceForm.build(
        existing: widget.source,
        name: _name.text,
        url: _url.text,
        group: _group.text,
        headers: _headers.text,
        searchUrl: _searchUrl.text,
        searchList: _searchList.text,
        searchName: _searchName.text,
        searchAuthor: _searchAuthor.text,
        searchCoverUrl: _searchCover.text,
        searchBookUrl: _searchBookUrl.text,
        findUrl: _findUrl.text,
        chapterList: _chapterList.text,
        chapterName: _chapterName.text,
        chapterUrl: _chapterUrl.text,
        contentUrl: _contentUrl.text,
        contentUrlNext: _contentUrlNext.text,
      );

  Future<void> _save() async {
    final r = _build();
    if (r is SourceBuildError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.message)));
      return;
    }
    final s = (r as SourceBuilt).source;
    await widget.state.addSourceManual(s);
    if (mounted) Navigator.of(context).pop(s);
  }

  ComicSource? _trialSource() {
    final r = _build();
    if (r is SourceBuildError) {
      setState(() => _trialError = '表单未通过校验：${r.message}');
      return null;
    }
    return (r as SourceBuilt).source;
  }

  Future<void> _trialSearch() async {
    final src = _trialSource();
    if (src == null || _keyword.text.trim().isEmpty) return;
    setState(() {
      _trialSearching = true;
      _trialError = null;
      _trialResults = const [];
      _trialBook = null;
      _trialChapters = const [];
      _trialImages = const [];
    });
    try {
      final page = await SourceService.instance.runtimeFor(src).search(_keyword.text.trim());
      setState(() => _trialResults = page.items.take(20).toList());
    } catch (e) {
      setState(() => _trialError = '搜索失败：$e');
    } finally {
      if (mounted) setState(() => _trialSearching = false);
    }
  }

  Future<void> _trialDetail(Book b) async {
    final src = _trialSource();
    if (src == null) return;
    setState(() {
      _trialBook = b;
      _trialDetailLoading = true;
      _trialError = null;
      _trialChapters = const [];
      _trialImages = const [];
    });
    try {
      final (_, chapters) =
          await SourceService.instance.runtimeFor(src).detail(b.bookUrl);
      setState(() => _trialChapters = chapters.take(30).toList());
    } catch (e) {
      setState(() => _trialError = '目录失败：$e');
    } finally {
      if (mounted) setState(() => _trialDetailLoading = false);
    }
  }

  Future<void> _loadTrialImages(Chapter c) async {
    final src = _trialSource();
    if (src == null) return;
    setState(() {
      _trialImagesLoading = true;
      _trialError = null;
      _trialImages = const [];
    });
    try {
      final urls = await SourceService.instance.runtimeFor(src).images(c.url);
      setState(() => _trialImages = urls);
    } catch (e) {
      setState(() => _trialError = '取图失败：$e');
    } finally {
      if (mounted) setState(() => _trialImagesLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑源' : '新建源'),
        actions: [
          IconButton(tooltip: '保存', icon: const Icon(Icons.check),
              onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _section(context, '基本信息', [
            _field(_name, '名称 *'),
            _field(_url, '源地址 *（http/https 公网）'),
            _field(_group, '分组'),
            _field(_headers, '请求头（每行 Key: Value）', maxLines: 3),
          ]),
          _section(context, '搜索规则', [
            _field(_searchUrl, '搜索 URL（searchKey/searchPage 占位，支持 @Post 语法）'),
            _field(_searchList, '列表选择器'),
            _field(_searchName, '名称选择器'),
            _field(_searchAuthor, '作者选择器'),
            _field(_searchCover, '封面选择器'),
            _field(_searchBookUrl, '书本链接选择器'),
          ]),
          _section(context, '发现与详情', [
            _field(_findUrl, '发现入口（名称::url，每行一条）', maxLines: 3),
            _field(_chapterList, '章节列表选择器'),
            _field(_chapterName, '章节名选择器'),
            _field(_chapterUrl, '章节链接选择器'),
          ]),
          _section(context, '阅读（取图）', [
            _field(_contentUrl, '取图规则（选择器或 \$js）', maxLines: 2),
            _field(_contentUrlNext, '图片翻页（contentUrlNext）'),
          ]),
          const SizedBox(height: 8),
          _trialCard(scheme),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          initiallyExpanded: title == '基本信息',
          title: Text(title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
          children: children,
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  /// 试跑卡片：关键词 → 搜索结果 → 章节目录 → 图片预览。
  Widget _trialCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.play_circle_outline, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text('规则试跑',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyword,
                    decoration: const InputDecoration(
                      hintText: '试跑关键词',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _trialSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _trialSearching ? null : _trialSearch,
                  child: _trialSearching
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('搜索'),
                ),
              ],
            ),
            if (_trialError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_trialError!,
                    style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
            if (_trialResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('搜索结果（${_trialResults.length}，点一条试目录）',
                  style: const TextStyle(fontSize: 12)),
              ..._trialResults.map((b) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.menu_book_outlined, size: 18),
                    title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _trialDetail(b),
                  )),
            ],
            if (_trialDetailLoading) const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            if (_trialChapters.isNotEmpty) ...[
              const Divider(),
              Text('目录「${_trialBook?.name}」（${_trialChapters.length}，点一话试图片）',
                  style: const TextStyle(fontSize: 12)),
              ..._trialChapters.take(10).map((c) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.image_outlined, size: 18),
                    title: Text(c.title.isEmpty ? '(未命名章节)' : c.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _loadTrialImages(c),
                  )),
            ],
            if (_trialImagesLoading) const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            if (_trialImages.isNotEmpty) ...[
              const Divider(),
              Text('取图成功：${_trialImages.length} 张',
                  style: TextStyle(
                      fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SizedBox(
                height: 120,
                child: Image.network(
                  _trialImages.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Text('首图预览加载失败（URL 见下）',
                      style: TextStyle(fontSize: 11, color: scheme.outline)),
                ),
              ),
              const SizedBox(height: 4),
              Text(_trialImages.take(3).join('\n'),
                  style: TextStyle(fontSize: 10, color: scheme.outline)),
            ],
          ],
        ),
      ),
    );
  }
}
