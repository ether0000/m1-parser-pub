# M1 Parser - 證照題庫特訓與記憶提煉系統

這是一款專門為**網管與醫管證照考試**量身打造的 Flutter 行動端 App。結合了 **Firebase Services** 與 **Spaced Repetition（間隔重複）記憶演算法**，旨在幫助考生克服忘卻曲線，實行高效率、無負擔的碎型複習。

---

## 🚀 核心特色

1. **碎型複習卡（隨機抽測）**：每次打開 App，看板會從「常錯題庫」中隨機抽取一題盲測，利用零碎時間進行高頻刺激。
2. **今日待複習排程**：基於間隔重複演算法，系統自動將錯題加入今日排程，並隨掌握度拉長下次複習間隔。
3. **每日委託任務與積分**：設計「每日完成 20 題」與「消除 5 道錯題」目標，搭配 Streak（連續登入）激勵機制。
4. **重點筆記與精熟標記**：作答完畢後可對錯題編寫電子書筆記，並可將題目標記為「精熟（Mastered）」以將其從測驗池中過濾。
5. **雲端與離線持久化優先**：Firestore 開啟離線快取（Offline Cache），弱網或斷網時依然能流暢作答，連網後自動同步至雲端。

---

## 🛠️ 技術棧說明

- **Flutter SDK**: 支援 Cross-platform 開發（已於 Android / iOS / Web 進行驗證）。
- **狀態管理**:
  - **全域數據流**：採用原生 `ChangeNotifier` + `ChangeNotifierProvider` (`AppProvider`, `QuizProvider`) 託管 Firestore 串流與測驗作答狀態。
  - **局部 UI 狀態**：採用原生 **`StatefulWidget`** 搭配 `setState()` 來維護搜尋輸入、卡片摺疊與日期選擇器，避免狀態工具過度設計。
- **Firebase 生態系**:
  - **Firebase Auth**：支援臨時/匿名登入，保障用戶個人數據的隱私與雲端同步。
  - **Cloud Firestore**：作為核心的 NoSQL 題庫與個人進度存儲，啟用 Offline Persistence（離線持久化）。
- **本地緩存**: 採用 `SharedPreferences` 進行快取優先加載（Cache-First），大幅縮短冷啟動時間。

---

## 🏗️ 專案狀態優化與安全設計

本專案經過深度重構，遵循生產級別的 Flutter 開發規範：

1. **防重複 `setState()` 渲染限制**
   - 在 `dashboard_tab.dart` 與 `settings_tab.dart` 中優化了考試日期加載邏輯。當 Firestore 返回的最新日期與當前緩存一致時，**拒絕觸發** `setState()`，降低 Widget 重建（Rebuild）開銷。
   - 善用 `didChangeDependencies()` 進行 build 之前的狀態預更新，避免在 build 階段或 postFrameCallback 內多次觸發 `setState()`。
2. **嚴格的生命週期管理與資源回收**
   - 所有的 `TextEditingController` 與 `TabController` 均在專屬的 `dispose()` 中銷毀。
   - 將 Dialog 彈出框（如 `_EditQuestionDialog`）與 BottomSheet（如 `_QuestionDetailSheet`）抽離為獨立的 `StatefulWidget`，藉由其 State 生命週期確保動態生成的 Controllers 能在彈窗關閉時 100% 被垃圾回收，徹底根除 Memory Leak。
3. **非同步守護 (Mounted Guard)**
   - 所有在 `await` 異步操作後調用 `setState()` 或 `Navigator.pop()` 的邏輯，均預先通過 `if (!mounted) return;` 檢查，確保在頁面被提前銷毀時不會引發崩潰。
4. **Firestore 批次寫入效能優化 (`WriteBatch`)**
   - 改進了錯題筆記編輯的即時寫入問題：考後總結頁面在編輯筆記時，僅更新記憶體欄位，直到用戶點擊「完成並返回看板」時，才進行一次性的 `WriteBatch` 寫入。
   - 針對大量題庫初始化，實作「450筆滑動窗口機制」，安全繞過 Firestore 單次 Batch 500 個操作的硬性限制。

---

## 📁 資料夾結構設計

```text
lib/
├── firebase_options.dart      # FlutterFire 自動生成的跨平台 Firebase 組態
├── main.dart                  # 應用程式入口，初始化 Firebase 與全域 Provider
├── models/
│   ├── exam_question.dart     # 題目資料模型（含年分、選項、答題次數、精熟狀態）
│   ├── question_category.dart # 題目分類模型（支援延伸考科分類）
│   ├── quiz_session.dart      # 單次測驗歷程紀錄
│   └── user_stats.dart        # 使用者個人數據（Streak、積分、每日進度）
├── providers/
│   ├── app_provider.dart      # 全域數據同步管理中心（監聽 Firestore Stream 廣播）
│   └── quiz_provider.dart     # 單次測驗進度、計分與原子存檔邏輯
├── screens/
│   ├── main_layout.dart       # 底部導覽列主框架（StatefulWidget 局部切換）
│   ├── quiz_screen.dart       # 測驗練習進行畫面（StatelessWidget + Consumer）
│   ├── review_screen.dart     # 考後檢討與筆記提煉（批次 Commit 機制）
│   ├── manage_questions_screen.dart # 後台題庫管理與增刪查改頁面
│   └── tabs/
│       ├── dashboard_tab.dart # 學習看板、每日委託與隨機抽測
│       ├── practice_tab.dart  # 測驗範圍配置與特訓起點
│       ├── notes_tab.dart     # 歷史紀錄折疊面板、常錯特訓與題庫網格
│       └── settings_tab.dart  # 考期日期設定、JSON 匯入與數據重置後台
├── services/
│   └── firestore_service.dart # Firestore 數據存取、Batch 批次寫入與原子交易封裝
└── utils/
    ├── animated_background.dart # 現代感微動漸層背景
    ├── data_importer.dart      # JSON 題庫解碼與背景 compute 運算解析
    └── glassmorphism.dart      # iOS 風格玻璃擬態卡片容器
```

---

## ⚙️ 環境配置與啟動步驟

### 1. 配置 Firebase 憑證
1. 前往 [Firebase Console](https://console.firebase.google.com/) 建立專案。
2. 開啟 **Firestore Database** 並在規則中允許安全讀寫。
3. 開啟 **Authentication** 認證服務，並啟用 **Anonymous（匿名登入）**。
4. 下載平台憑證：
   - **Android**: 將 `google-services.json` 放置於 `android/app/` 資料夾下。
   - **iOS**: 用 Xcode 打開專案，將 `GoogleService-Info.plist` 拖曳至 `Runner/` 目錄並連結。

### 2. 初始化與啟動應用程式
確保已安裝 Flutter SDK (建議 $\ge 3.19.x$)，在專案根目錄下依序執行：

```bash
# 1. 取得專案相依套件
flutter pub get

# 2. 執行代碼靜態分析，確保重構後 0 警告
flutter analyze

# 3. 啟動本機開發伺服器 / 模擬器執行
flutter run
```

### 3. 匯入初始題庫
1. 進入 App，切換至 **「設定」** Tab。
2. 點選 **「載入內建題庫」**，系統將讀取 `assets/JSON/` 中的本地預置題目並背景批次同步至 Firestore。
3. 您也可以點選 **「上傳外部 JSON 題庫」** 選擇自訂的 JSON 題庫檔案進行匯入。
