# 每日一词

一个 iOS 诗词应用：每天在固定时间推送一首词或律诗（默认诗词交替），附带译文、注释、赏析与创作背景。界面参考「西窗烛」的风格：宣纸底色、墨色文字、朱砂印章、楷体，可切换竖排。

诗词数据来自 [chinese-poetry](https://github.com/chinese-poetry/chinese-poetry)，收录其中全部诗词类合集，共 **342,482** 首：

| 合集 | 数量 | 说明 |
| --- | ---: | --- |
| 宋词 | 21,052 | 全宋词，含「宋词三百首」标签 |
| 花间集 / 南唐二主词 | 497 / 45 | 自带注释 |
| 纳兰词 | 256 | 纳兰性德 |
| 全唐诗 | 56,165 | 含「唐诗三百首」标签，水墨唐诗题解已合并 |
| 宋诗 | 253,167 | |
| 元曲 | 10,904 | |
| 诗经 / 楚辞 / 曹操诗集 | 305 / 65 / 26 | |

繁体统一转为简体，同一作品在不同合集中重复出现时合并为一条。

## 功能

- **每日推送**：在设置里选推送时间（默认 8:00）和推送内容：诗词交替（默认，一天词、一天律诗）、只推词、只推律诗。用本机定时通知实现，不需要服务器，离线也会准时到达。通知里有作品的前几句、一句话导读，以及一张诗词卡片图片；长按可以「阅读解析」或「收藏」。
- **推送顺序**：名篇排在前面。
  - 词共 21,823 首：宋词三百首、南唐二主词、纳兰词最先，然后是花间集和宋词名家，最后是其余的全宋词。
  - 律诗共 88,522 首，只收五律、七律，不含古体、绝句、诗经、楚辞：唐诗三百首里的律诗最先，然后是唐代名家、宋代名家，最后是其余作品。律诗由脚本自动识别：八句、每句同为五字或七字，再按普通话声调粗查平仄。普通话没有入声，所以会有少量误判。
- **解析**：调用 Claude API 生成导读、白话译文、字词注释、赏析、创作背景和词牌介绍，保存在本机，同一首只生成一次。App 会在后台提前生成接下来三天的解析，所以通知里能带上导读。花间集、南唐二主词的原注和水墨唐诗的题解直接显示，不需要 API Key。
- **阅读**：可横排或竖排（从右往左、去掉标点），能调字号，支持深色模式。
- **发现**：按题目、作者、名句搜索；按合集、词牌、词人浏览；随机一首。
- **收藏与分享**：可以收藏作品，也可以把作品分享成诗词卡片图片。

## 构建

需要 macOS、Xcode 15 或更高版本、Python 3，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
./scripts/bootstrap.sh        # 生成诗词库、下载字体、生成 Xcode 工程
open XiChuang.xcodeproj
```

`bootstrap.sh` 做三件事：

1. 运行 `scripts/build_database.py`。它浅克隆 chinese-poetry 仓库，用 OpenCC 转成简体，用 pypinyin 识别律诗，生成约 107 MB 的 `XiChuang/Resources/poetry.sqlite`。这个文件超过 GitHub 单文件 100 MB 的上限，所以不提交到仓库。如果本地已有数据仓库，可以用 `./scripts/bootstrap.sh --source /path/to/chinese-poetry`。
2. 下载[霞鹜文楷](https://github.com/lxgw/LxgwWenKai)（SIL OFL 1.1）到 `XiChuang/Resources/Fonts/`。下载失败时会自动改用系统宋体。
3. 运行 `xcodegen generate` 生成工程。

在 Xcode 的 Signing & Capabilities 里选好你的 Team，就能装到真机上。第一次打开 App 时允许通知。

### 解析用的 API Key

在 App 的「设置 → 解析（Claude）」里填写 [Anthropic API Key](https://console.anthropic.com/)。Key 保存在 iOS 钥匙串中，只用来直接请求 `api.anthropic.com`。

- 默认模型是 Claude Opus 5.5，也可以改用 Sonnet 5.5 或 Haiku 5.5（最省钱）。
- 请求使用结构化输出（JSON Schema），解析内容直接按字段显示。
- 用 Opus 或 Sonnet 时，请求开启了服务端 `fallbacks: "default"`：遇到安全分类器误拒，服务端会自动换用推荐的模型重试。

## 目录结构

```
scripts/
  build_database.py      chinese-poetry JSON → SQLite（简体化、去重、作者小传、推送顺序）
  bootstrap.sh           一键准备
project.yml              XcodeGen 工程定义
XiChuang/
  App/                   入口、通知点击路由
  Models/                Poem、Analysis
  Services/
    PoetryDatabase       只读 SQLite 查询
    DailyPoemProvider    日期 → 今日一词
    AnalysisService      Claude 解析 + 本地缓存
    NotificationManager  排未来 30 天的本地通知（附卡片图）
    BackgroundTasks      推送前在后台预生成解析
    FavoritesStore / KeychainHelper / AppSettings
  Views/                 今日、详情、竖排、发现、收藏、设置、分享卡片、主题
```

## 说明

- iOS 最多同时保留 64 条待发送的本地通知。App 每次打开，以及后台任务运行时，都会重新排好未来 30 天，所以 30 天内不打开 App 也照常推送。
- 每日序列从你第一次打开 App 那天算起；「今日」页可以左右滑动，翻看最近 30 天的推送。
- 诗词数据遵循 chinese-poetry 的 MIT 协议。AI 生成的解析仅供参考。
