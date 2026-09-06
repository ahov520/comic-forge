// Node 冒烟：验证 ppcat JS 取图契约（getImgList + 全局 html + @Header 尾缀）。
// 用法：node engine/tool/js_contract_smoke.mjs [源名关键词] [章节页URL]
// 从 app/assets/store.json 取源的内容规则，抓真实章节页，按引擎同款
// 预处理（剥 $ 前缀/@Header 尾缀、补 getImgList(html) 调用、注入 env）执行。
import { readFileSync } from 'fs';

const needle = process.argv[2] ?? '腾讯';
const chapterUrl = process.argv[3] ?? 'https://m.ac.qq.com/chapter/index/id/505433/cid/1';

const store = JSON.parse(readFileSync(new URL('../../app/assets/store.json', import.meta.url), 'utf8'));
const src = store.sources.find((s) => (s.bookSourceName ?? '').includes(needle));
if (!src) {
  console.error('找不到源:', needle);
  process.exit(1);
}
let rule = src.ruleBookContent ?? '';
console.log('源:', src.bookSourceName, ' 规则长度:', rule.length);

// —— 引擎同款预处理 ——
rule = rule.trim();
if (rule.startsWith('@js:')) rule = rule.slice(4);
if (rule.startsWith('$') && !rule.startsWith('$.')) rule = rule.slice(1);
const hm = rule.match(/@Header:\s*(\{[\s\S]*\})\s*$/);
if (hm) rule = rule.slice(0, hm.index).trim();
if (/function\s+getImgList\s*\(/.test(rule) && !/getImgList\s*\([^)]*\)\s*;?\s*$/.test(rule)) {
  rule += '\ngetImgList(html);';
}

const ua = src.headers?.['User-Agent'] ?? 'Mozilla/5.0 (Linux; Android 13) Chrome/124 Mobile';
const res = await fetch(chapterUrl, { headers: { 'User-Agent': ua } });
const html = await res.text();
console.log('章节页:', chapterUrl, ' HTTP', res.status, ' ', html.length, '字节');

// —— 引擎同款 env 注入（含浏览器 shim：ppcat JS 假定 WebView 环境）——
const prelude = `var document = { getElementsByTagName: function () { return [{}]; }, createElement: function () { return {}; } };
var console = typeof console !== 'undefined' ? console : { info: function(){}, log: function(){}, error: function(){} };
var window = typeof window !== 'undefined' ? window : {};`;
const env = { html, result: html, baseUrl: chapterUrl, key: '', page: '' };
const setup = Object.entries(env)
  .map(([k, v]) => `var ${k} = ${JSON.stringify(v)};`)
  .join('\n');

try {
  // 间接 eval：全局作用域 + 宽松模式，贴近 flutter_js/QuickJS 行为
  const ev = eval;
  const out = ev(`${prelude}\n${setup}\n\n${rule}`);
  const list = typeof out === 'string' ? out.split(/[\n\r]+/).filter(Boolean) : out;
  if (Array.isArray(list) && list.length > 0) {
    console.log('✅ 取图', list.length, '张，样例:', list.slice(0, 2));
    process.exit(0);
  }
  console.error('❌ 返回为空:', String(out).slice(0, 200));
  process.exit(1);
} catch (e) {
  console.error('❌ JS 执行失败:', String(e.message).slice(0, 300));
  process.exit(1);
}
