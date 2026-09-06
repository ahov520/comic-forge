/// 引擎产出/消费的内容模型。
library;

/// 搜索/发现结果条目或书籍详情。
class Book {
  Book({
    this.sourceId,
    this.name = '',
    this.author = '',
    this.kind = '',
    this.coverUrl = '',
    this.introduce = '',
    this.lastChapter = '',
    this.updateTime = '',
    this.bookUrl = '',
  });

  final String? sourceId;
  String name;
  String author;
  String kind;
  String coverUrl;
  String introduce;
  String lastChapter;
  String updateTime;
  String bookUrl;

  Map<String, dynamic> toJson() => {
        if (sourceId != null) 'sourceId': sourceId,
        'name': name,
        if (author.isNotEmpty) 'author': author,
        if (kind.isNotEmpty) 'kind': kind,
        if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
        if (introduce.isNotEmpty) 'introduce': introduce,
        if (lastChapter.isNotEmpty) 'lastChapter': lastChapter,
        if (updateTime.isNotEmpty) 'updateTime': updateTime,
        if (bookUrl.isNotEmpty) 'bookUrl': bookUrl,
      };

  static Book fromJson(Map<String, dynamic> j) => Book(
        sourceId: j['sourceId'] as String?,
        name: (j['name'] ?? '') as String,
        author: (j['author'] ?? '') as String,
        kind: (j['kind'] ?? '') as String,
        coverUrl: (j['coverUrl'] ?? '') as String,
        introduce: (j['introduce'] ?? '') as String,
        lastChapter: (j['lastChapter'] ?? '') as String,
        updateTime: (j['updateTime'] ?? '') as String,
        bookUrl: (j['bookUrl'] ?? '') as String,
      );
}

/// 章节。
class Chapter {
  Chapter({
    this.title = '',
    this.url = '',
    this.coverUrl = '',
    this.time = '',
    this.group = '',
  });

  String title;
  String url;
  String coverUrl;
  String time;
  String group;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (url.isNotEmpty) 'url': url,
        if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
        if (time.isNotEmpty) 'time': time,
        if (group.isNotEmpty) 'group': group,
      };
}

/// 一次搜索/发现的分页结果。
class Paged<T> {
  Paged(this.items, {this.nextPage});
  final List<T> items;

  /// 下一页 URL（源规则给出 UrlNext 时使用），null 表示无更多。
  final String? nextPage;
}
