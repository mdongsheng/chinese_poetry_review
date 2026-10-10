#!/usr/bin/env python3
"""
把 chinese-poetry (https://github.com/chinese-poetry/chinese-poetry) 的 JSON 数据
整理成 App 内置的只读 SQLite 数据库 XiChuang/Resources/poetry.sqlite。

用法:
    pip3 install opencc pypinyin
    python3 scripts/build_database.py --source /path/to/chinese-poetry
    # 不传 --source 时会自动浅克隆到 .build/chinese-poetry

做了这些事:
  * 收录全部诗词类合集: 全唐诗(唐/宋)、宋词、花间集、南唐二主词、纳兰性德、元曲、
    诗经、楚辞、曹操诗集; 水墨唐诗/唐诗三百首/宋词三百首 只作为标签与解析合并进已有条目
  * 繁体统一转为简体 (OpenCC t2s)
  * 生成作者小传表
  * 分别为「词」和「律诗」生成每日推送顺序 daily_ci_rank / daily_shi_rank:
    名篇优先, 同一层级内用固定种子打乱。诗只推五律、七律, 见 is_lushi
"""
import argparse
import glob
import json
import os
import random
import re
import sqlite3
import subprocess
import sys

try:
    import opencc
    from pypinyin import Style, pinyin
except ImportError:
    sys.exit("缺少依赖: 请先运行 pip3 install opencc pypinyin")

T2S = opencc.OpenCC("t2s")
REPO_URL = "https://github.com/chinese-poetry/chinese-poetry.git"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "XiChuang", "Resources", "poetry.sqlite")

# 每日推送第二层级: 宋词名家
FAMOUS_CI_AUTHORS = [
    "苏轼", "辛弃疾", "李清照", "柳永", "晏殊", "晏几道", "欧阳修", "秦观", "周邦彦",
    "姜夔", "吴文英", "陆游", "岳飞", "贺铸", "张先", "范仲淹", "王安石", "黄庭坚",
    "张孝祥", "朱敦儒", "陈与义", "蒋捷", "张炎", "王沂孙", "周密", "刘克庄", "叶梦得",
    "史达祖", "刘过", "陈亮", "范成大", "杨万里", "朱淑真", "文天祥", "李之仪", "宋祁",
    "晁补之", "毛滂", "万俟咏", "曾觌", "康与之", "张元干", "李纲", "赵佶", "潘阆",
    "林逋", "王观", "舒亶", "谢逸", "陈克", "吕本中", "向子諲", "岳珂", "刘辰翁",
    "高观国", "卢祖皋", "严蕊", "聂胜琼", "魏夫人", "孙光宪",
]

# 诗的推送层级
FAMOUS_TANG_POETS = [
    "李白", "杜甫", "王维", "白居易", "李商隐", "杜牧", "孟浩然", "王昌龄", "刘禹锡", "柳宗元",
    "韩愈", "岑参", "高适", "王之涣", "贺知章", "李贺", "韦应物", "张九龄", "陈子昂", "骆宾王",
    "王勃", "杨炯", "卢照邻", "元稹", "张籍", "贾岛", "孟郊", "刘长卿", "钱起", "韦庄",
    "杜荀鹤", "罗隐", "皮日休", "陆龟蒙", "宋之问", "沈佺期", "崔颢", "常建", "祖咏", "王翰",
    "李益", "卢纶", "司空曙", "张继", "崔护", "金昌绪", "朱庆余", "许浑", "温庭筠", "薛涛",
    "鱼玄机", "张若虚", "王建", "李绅", "綦毋潜", "储光羲", "裴迪", "戴叔伦", "顾况", "皎然",
]
FAMOUS_SONG_POETS = [
    "苏轼", "陆游", "王安石", "黄庭坚", "杨万里", "范成大", "欧阳修", "梅尧臣", "苏舜钦",
    "陈与义", "陈师道", "林逋", "文天祥", "朱熹", "秦观", "曾巩", "苏辙", "晏殊", "叶绍翁",
    "翁卷", "赵师秀", "戴复古", "刘克庄", "姜夔", "王禹偁", "寇准", "邵雍", "程颢", "李清照",
    "岳飞", "范仲淹", "张耒", "晁补之", "汪藻", "曾几", "吕本中", "尤袤", "萧德藻",
]
LUSHI_MAX_VIOLATIONS = 3

PUNCT = "，。、；：？！,.;:?!"


def t(s):
    return T2S.convert(s) if s else s


def norm_title(s):
    return (s or "").replace("・", "·").replace("•", "·").strip()


def first_clause(lines):
    text = "".join(lines)
    m = re.split(r"[，。、；：？！,.;:?!\s]", text)
    for part in m:
        if part:
            return part
    return text[:8]


def tone(ch):
    """平 p / 仄 z, 按普通话声调近似"""
    t = pinyin(ch, style=Style.TONE3)[0][0]
    return "p" if t[-1] in "12" else "z" if t[-1] in "34" else None


def tone_violations(lines):
    v = 0
    for i, line in enumerate(lines):
        end = tone(line[-1])
        if i % 2 == 1 and end != "p":         # 偶句押平声韵
            v += 1
        if i in (2, 4, 6) and end != "z":     # 三五七句句末用仄
            v += 1
    for k in ([1] if len(lines[0]) == 5 else [1, 3]):   # 二字（七言兼四字）
        ts = [tone(line[k]) for line in lines]
        v += sum(ts[i] == ts[i + 1] for i in (0, 2, 4, 6))   # 联内相对
        v += sum(ts[i] != ts[i + 1] for i in (1, 3, 5))      # 联间相粘
    return v


def key_of(author, lines):
    """去重键: 作者 + 首句 (去标点)"""
    first = re.sub(r"[%s\s]" % re.escape(PUNCT), "", "".join(lines))[:12]
    return (author or "", first)


class Builder:
    def __init__(self, src):
        self.src = src
        self.poems = []
        self.index = {}
        self.authors = {}

    def p(self, *parts):
        return os.path.join(self.src, *parts)

    def load(self, *parts):
        with open(self.p(*parts), encoding="utf-8") as f:
            return json.load(f)

    def add(self, *, title, author, dynasty, collection, kind, lines,
            rhythmic=None, notes=None, prologue=None, tags=None, tier=None):
        lines = [t(l).strip() for l in lines if l and l.strip()]
        if not lines:
            return None
        author = t(author or "佚名").strip() or "佚名"
        rhythmic = norm_title(t(rhythmic)) if rhythmic else None
        title = norm_title(t(title))
        if kind == "ci":
            if not rhythmic:
                rhythmic = title.split("·")[0].split(" ")[0] if title else None
            # 词以「词牌·首句」作题, 与常见诗词 App 一致
            if not title or title == rhythmic or re.fullmatch(r".+\s+其[一二三四五六七八九十]+", title):
                title = f"{rhythmic}·{first_clause(lines)}" if rhythmic else first_clause(lines)
        if not title:
            title = first_clause(lines)
        k = key_of(author, lines)
        if k in self.index:
            existing = self.index[k]
            self.merge(existing, notes=notes, prologue=prologue, tags=tags, tier=tier)
            return existing
        poem = dict(
            title=title, author=author, dynasty=dynasty, collection=collection, kind=kind,
            rhythmic=rhythmic, content="\n".join(lines),
            notes="\n".join(t(n) for n in (notes or []) if n) or None,
            prologue=t(prologue) if prologue else None,
            tags=set(tags or []), tier=tier,
        )
        self.poems.append(poem)
        self.index[k] = poem
        return poem

    def merge(self, poem, *, notes=None, prologue=None, tags=None, tier=None):
        if notes and not poem["notes"]:
            poem["notes"] = "\n".join(t(n) for n in notes if n)
        if prologue and not poem["prologue"]:
            poem["prologue"] = t(prologue)
        if tags:
            poem["tags"].update(tags)
        if tier is not None and (poem["tier"] is None or tier < poem["tier"]):
            poem["tier"] = tier

    def add_author(self, name, dynasty, desc):
        if not name or not desc:
            return
        name, desc = t(name).strip(), t(desc).strip()
        key = (name, dynasty)
        if len(desc) > len(self.authors.get(key, "")):
            self.authors[key] = desc

    # ---------- 各合集 ----------
    def build(self):
        # 词: 名篇集子先加入, 以便去重时保留更好的元数据
        for item in self.load("宋词", "宋词三百首.json"):
            self.add(title=None, author=item["author"], dynasty="宋", collection="宋词",
                     kind="ci", rhythmic=item["rhythmic"], lines=item["paragraphs"],
                     tags=["宋词三百首"], tier=0)
        for item in self.load("五代诗词", "nantang", "poetrys.json"):
            self.add(title=item.get("title"), author=item["author"], dynasty="五代",
                     collection="南唐二主词", kind="ci", rhythmic=item.get("rhythmic"),
                     lines=item["paragraphs"], notes=item.get("notes"), tier=0)
        for a in self.load("五代诗词", "nantang", "authors.json"):
            self.add_author(a["name"], "五代", a.get("desc"))
        for item in self.load("纳兰性德", "纳兰性德诗集.json"):
            title = norm_title(item["title"])
            is_ci = "·" in title
            self.add(title=title, author=item["author"], dynasty="清", collection="纳兰词",
                     kind="ci" if is_ci else "shi",
                     rhythmic=title.split("·")[0] if is_ci else None,
                     lines=item["para"], tier=0 if is_ci else None)
        for f in sorted(glob.glob(self.p("五代诗词", "huajianji", "huajianji-[0-9x]*-juan.json"))):
            for item in json.load(open(f, encoding="utf-8")):
                self.add(title=item.get("title"), author=item["author"], dynasty="五代",
                         collection="花间集", kind="ci", rhythmic=item.get("rhythmic"),
                         lines=item["paragraphs"], notes=item.get("notes"), tier=1)
        famous = set(FAMOUS_CI_AUTHORS)
        for f in sorted(glob.glob(self.p("宋词", "ci.song.*.json"))):
            for item in json.load(open(f, encoding="utf-8")):
                author = t(item["author"])
                self.add(title=None, author=author, dynasty="宋", collection="宋词",
                         kind="ci", rhythmic=item["rhythmic"], lines=item["paragraphs"],
                         tier=1 if author in famous else 2)
        for a in self.load("宋词", "author.song.json"):
            self.add_author(a["name"], "宋", a.get("description"))

        # 诗
        for f in sorted(glob.glob(self.p("全唐诗", "poet.tang.*.json"))):
            for item in json.load(open(f, encoding="utf-8")):
                self.add(title=item.get("title"), author=item.get("author"), dynasty="唐",
                         collection="全唐诗", kind="shi", lines=item.get("paragraphs", []))
        for f in sorted(glob.glob(self.p("全唐诗", "poet.song.*.json"))):
            for item in json.load(open(f, encoding="utf-8")):
                self.add(title=item.get("title"), author=item.get("author"), dynasty="宋",
                         collection="宋诗", kind="shi", lines=item.get("paragraphs", []))
        for a in self.load("全唐诗", "authors.tang.json"):
            self.add_author(a["name"], "唐", a.get("desc"))
        for a in self.load("全唐诗", "authors.song.json"):
            self.add_author(a["name"], "宋", a.get("desc"))
        for item in self.load("全唐诗", "唐诗三百首.json"):
            tags = [x for x in item.get("tags", []) if x]
            self.add(title=item.get("title"), author=item.get("author"), dynasty="唐",
                     collection="全唐诗", kind="shi", lines=item["paragraphs"], tags=tags)
        for item in self.load("水墨唐诗", "shuimotangshi.json"):
            self.add(title=item.get("title"), author=item.get("author"), dynasty="唐",
                     collection="全唐诗", kind="shi", lines=item["paragraphs"],
                     prologue=item.get("prologue"), tags=["水墨唐诗"])
        for item in self.load("曹操诗集", "caocao.json"):
            self.add(title=item["title"], author="曹操", dynasty="汉", collection="曹操诗集",
                     kind="shi", lines=item["paragraphs"])
        for item in self.load("诗经", "shijing.json"):
            self.add(title=item["title"], author="佚名", dynasty="先秦", collection="诗经",
                     kind="shi", lines=item["content"],
                     tags=[x for x in (item.get("chapter"), item.get("section")) if x])
        for item in self.load("楚辞", "chuci.json"):
            self.add(title=item["title"], author=item.get("author"), dynasty="先秦",
                     collection="楚辞", kind="shi", lines=item["content"],
                     tags=[item["section"]] if item.get("section") else None)
        for item in self.load("元曲", "yuanqu.json"):
            self.add(title=item["title"], author=item.get("author"), dynasty="元",
                     collection="元曲", kind="qu", lines=item["paragraphs"])

    def daily_order(self):
        for p in self.poems:
            if p["kind"] == "shi":
                p["shi_tier"] = self.shi_tier(p)
        self.assign_rank("ci", "tier", "daily_ci_rank")
        self.assign_rank("shi", "shi_tier", "daily_shi_rank")

    @staticmethod
    def is_lushi(p):
        """五言 / 七言律诗。

        唐诗三百首带体裁标签的直接用标签; 其余要求八句、每句同为五字或七字,
        再用普通话声调粗查平仄 (偶句押平声、三五七句收仄、对与粘)。
        普通话没有入声, 真律诗也常有一两处对不上, 所以允许 LUSHI_MAX_VIOLATIONS 处出入。
        """
        tags = p["tags"]
        if tags & {"五言律诗", "七言律诗"}:
            return True
        if tags & {"五言古诗", "七言古诗", "乐府", "五言绝句", "七言绝句"}:
            return False
        text = re.sub(r"[\[\]【】□]", "", p["content"])
        lines = [c for c in re.split(r"[%s\s]" % re.escape(PUNCT), text) if c]
        if len(lines) != 8 or len({len(c) for c in lines}) != 1 or len(lines[0]) not in (5, 7):
            return False
        return tone_violations(lines) <= LUSHI_MAX_VIOLATIONS

    @classmethod
    def shi_tier(cls, p):
        """只有律诗进入每日推送"""
        if not cls.is_lushi(p):
            return None
        if "唐诗三百首" in p["tags"] or "水墨唐诗" in p["tags"]:
            return 0
        if p["dynasty"] == "唐" and p["author"] in FAMOUS_TANG_POETS:
            return 1
        if p["dynasty"] == "宋" and p["author"] in FAMOUS_SONG_POETS:
            return 2
        return 3

    def assign_rank(self, kind, tier_key, rank_key):
        rng = random.Random(20260101)
        tiers = {}
        for p in self.poems:
            if p["kind"] == kind and p.get(tier_key) is not None:
                tiers.setdefault(p[tier_key], []).append(p)
        rank = 0
        for tier in sorted(tiers):
            group = tiers[tier]
            rng.shuffle(group)
            for p in group:
                p[rank_key] = rank
                rank += 1

    def write(self, out):
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tmp = out + ".tmp"
        if os.path.exists(tmp):
            os.remove(tmp)
        db = sqlite3.connect(tmp)
        db.executescript("""
            PRAGMA page_size = 4096;
            CREATE TABLE poems (
                id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                author TEXT NOT NULL,
                dynasty TEXT NOT NULL,
                collection TEXT NOT NULL,
                kind TEXT NOT NULL,          -- ci 词 / shi 诗 / qu 曲
                rhythmic TEXT,               -- 词牌 / 曲牌
                content TEXT NOT NULL,       -- 以换行分隔的句子
                notes TEXT,                  -- 原数据自带的注释
                prologue TEXT,               -- 原数据自带的赏析
                tags TEXT,                   -- 以 | 分隔
                daily_ci_rank INTEGER,       -- 每日推送: 词的顺序
                daily_shi_rank INTEGER       -- 每日推送: 诗的顺序
            );
            CREATE TABLE authors (
                name TEXT NOT NULL,
                dynasty TEXT NOT NULL,
                description TEXT NOT NULL,
                PRIMARY KEY (name, dynasty)
            );
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        """)
        rows = []
        for i, p in enumerate(self.poems, start=1):
            rows.append((i, p["title"], p["author"], p["dynasty"], p["collection"], p["kind"],
                         p["rhythmic"], p["content"], p["notes"], p["prologue"],
                         "|".join(sorted(p["tags"])) or None, p.get("daily_ci_rank"), p.get("daily_shi_rank")))
        db.executemany("INSERT INTO poems VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
        db.executemany("INSERT INTO authors VALUES (?,?,?)",
                       [(n, d, desc) for (n, d), desc in self.authors.items()])
        db.executescript("""
            CREATE INDEX idx_poems_author ON poems(author);
            CREATE INDEX idx_poems_rhythmic ON poems(rhythmic) WHERE rhythmic IS NOT NULL;
            CREATE INDEX idx_poems_collection ON poems(collection);
            CREATE UNIQUE INDEX idx_poems_daily_ci ON poems(daily_ci_rank) WHERE daily_ci_rank IS NOT NULL;
            CREATE UNIQUE INDEX idx_poems_daily_shi ON poems(daily_shi_rank) WHERE daily_shi_rank IS NOT NULL;
        """)
        daily_ci = sum(1 for p in self.poems if p.get("daily_ci_rank") is not None)
        daily_shi = sum(1 for p in self.poems if p.get("daily_shi_rank") is not None)
        db.executemany("INSERT INTO meta VALUES (?,?)", [
            ("source", REPO_URL), ("poem_count", str(len(rows))),
            ("daily_ci_count", str(daily_ci)), ("daily_shi_count", str(daily_shi)),
        ])
        db.commit()
        db.execute("VACUUM")
        db.close()
        os.replace(tmp, out)
        return len(rows), daily_ci, daily_shi


def ensure_source(path):
    if path:
        return path
    path = os.path.join(ROOT, ".build", "chinese-poetry")
    if not os.path.isdir(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print(f"克隆 {REPO_URL} → {path}")
        subprocess.check_call(["git", "clone", "--depth", "1", REPO_URL, path])
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", help="chinese-poetry 仓库本地路径")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()
    b = Builder(ensure_source(args.source))
    b.build()
    b.daily_order()
    total, daily_ci, daily_shi = b.write(args.out)
    size = os.path.getsize(args.out) / 1024 / 1024
    print(f"完成: {total} 首作品, 每日推送 {daily_ci} 首词、{daily_shi} 首诗, "
          f"作者 {len(b.authors)} 位, {size:.1f} MB → {args.out}")


if __name__ == "__main__":
    main()
