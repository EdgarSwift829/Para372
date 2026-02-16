# 372手法改良版EA - バックテスト推奨設定

## 基本設定

### テスト環境
- **プラットフォーム**: MetaTrader 5
- **テストモード**: 全ティック（Every tick based on real ticks）
- **最適化モード**: Complete algorithm（遺伝的アルゴリズム）

## 通貨ペア別推奨設定

### USD/JPY（推奨メイン通貨ペア）

#### 保守的設定
```
[基本設定]
Magic = 20250216
RiskPercent = 1.5

[パラボリックSAR]
Step15m = 0.001
Step1h = 0.01
Step4h = 0.035
Maximum = 0.2

[SL/TP]
ATR_Period = 14
ATR_Multiplier = 2.0
RiskRewardRatio = 1.5

[フィルター]
UseDailyTrend = true
Use4HTrend = true
Use1HTrend = false
UseLossBreak = true
UseMonthEndStart = true

[休止設定]
LossBreakCount = 5
LossBreakUnit = "Hours"
LossBreakPeriod = 6
```

#### 標準設定
```
[基本設定]
Magic = 20250216
RiskPercent = 2.0

[パラボリックSAR]
Step15m = 0.001
Step1h = 0.01
Step4h = 0.035
Maximum = 0.2

[SL/TP]
ATR_Period = 14
ATR_Multiplier = 1.5
RiskRewardRatio = 1.5

[フィルター]
UseDailyTrend = true
Use4HTrend = false
Use1HTrend = false
UseLossBreak = true
UseMonthEndStart = false

[休止設定]
LossBreakCount = 5
LossBreakUnit = "Hours"
LossBreakPeriod = 4
```

#### アグレッシブ設定
```
[基本設定]
Magic = 20250216
RiskPercent = 3.0

[パラボリックSAR]
Step15m = 0.001
Step1h = 0.01
Step4h = 0.035
Maximum = 0.2

[SL/TP]
ATR_Period = 14
ATR_Multiplier = 1.2
RiskRewardRatio = 2.0

[フィルター]
UseDailyTrend = false
Use4HTrend = false
Use1HTrend = false
UseLossBreak = true
UseMonthEndStart = false

[休止設定]
LossBreakCount = 7
LossBreakUnit = "Hours"
LossBreakPeriod = 2
```

### EUR/USD

#### 標準設定
```
[基本設定]
RiskPercent = 2.0

[パラボリックSAR]
Step15m = 0.0008
Step1h = 0.008
Step4h = 0.03
Maximum = 0.2

[SL/TP]
ATR_Period = 14
ATR_Multiplier = 1.5
RiskRewardRatio = 1.5

[フィルター]
UseDailyTrend = true
Use4HTrend = false
Use1HTrend = false
```

### GBP/USD

#### 標準設定
```
[基本設定]
RiskPercent = 1.5

[パラボリックSAR]
Step15m = 0.0012
Step1h = 0.012
Step4h = 0.04
Maximum = 0.2

[SL/TP]
ATR_Period = 14
ATR_Multiplier = 2.0
RiskRewardRatio = 1.5

[フィルター]
UseDailyTrend = true
Use4HTrend = true
Use1HTrend = false
```
※ GBP/USDはボラティリティが高いため、ATR_Multiplierを大きめに設定

### AUD/USD

#### 標準設定
```
[基本設定]
RiskPercent = 2.0

[パラボリックSAR]
Step15m = 0.001
Step1h = 0.01
Step4h = 0.035
Maximum = 0.2

[SL/TP]
ATR_Period = 14
ATR_Multiplier = 1.5
RiskRewardRatio = 1.5

[フィルター]
UseDailyTrend = true
Use4HTrend = false
Use1HTrend = false
```

## テスト期間の推奨

### ショートテスト（動作確認）
- **期間**: 直近1年間（2024年1月～2024年12月）
- **目的**: EAの基本動作を確認
- **所要時間**: 約10～30分

### ミディアムテスト（性能評価）
- **期間**: 直近5年間（2020年1月～2024年12月）
- **目的**: 様々な相場環境での性能を評価
- **所要時間**: 約1～3時間

### ロングテスト（信頼性確認）
- **期間**: 10年間（2015年1月～2024年12月）
- **目的**: 長期的な信頼性とドローダウンを確認
- **所要時間**: 約3～8時間

### フルテスト（最高精度）
- **期間**: 可能な限り長期間（2010年～2024年）
- **目的**: 最も信頼性の高い統計データを取得
- **所要時間**: 1日以上

## 最適化パラメータ

### 優先度1: 最重要パラメータ
```
ATR_Multiplier
- 開始: 1.0
- 終了: 3.0
- ステップ: 0.2
- 説明: ストップロス幅を決定する最も重要なパラメータ

RiskRewardRatio
- 開始: 1.0
- 終了: 2.5
- ステップ: 0.25
- 説明: 利益目標を決定
```

### 優先度2: 重要パラメータ
```
RiskPercent
- 開始: 1.0
- 終了: 3.0
- ステップ: 0.5
- 説明: 1トレードあたりのリスク

Step15m
- 開始: 0.0005
- 終了: 0.002
- ステップ: 0.0001
- 説明: 15分足SARの感度
```

### 優先度3: 微調整パラメータ
```
Step1h
- 開始: 0.005
- 終了: 0.02
- ステップ: 0.001

Step4h
- 開始: 0.02
- 終了: 0.05
- ステップ: 0.005

LossBreakCount
- 開始: 3
- 終了: 7
- ステップ: 1
```

## 評価指標

### 必須チェック項目
1. **総利益 (Total Net Profit)**
   - 目標: プラス収支
   
2. **プロフィットファクター (Profit Factor)**
   - 最低基準: 1.2以上
   - 良好: 1.5以上
   - 優秀: 2.0以上

3. **最大ドローダウン (Max Drawdown)**
   - 許容範囲: 20%以下
   - 推奨: 10%以下

4. **総トレード数 (Total Trades)**
   - 最低: 100回以上
   - 推奨: 500回以上

5. **勝率 (Win Rate)**
   - 最低: 50%以上
   - 目標: 60～70%

### 補足指標
6. **シャープレシオ (Sharpe Ratio)**
   - 良好: 1.0以上
   - 優秀: 2.0以上

7. **期待利得 (Expected Payoff)**
   - プラスであること

8. **最大連敗 (Max Consecutive Losses)**
   - 許容: 10回以下

9. **リカバリーファクター (Recovery Factor)**
   - 良好: 2.0以上

## テスト手順

### ステップ1: 初回テスト
1. MT5のストラテジーテスターを開く
2. 上記の「標準設定」を適用
3. USD/JPYで2015-2024年のテストを実行
4. 結果を評価

### ステップ2: パラメータ最適化
1. 最適化モードに切り替え
2. 優先度1のパラメータを最適化
3. 最良の結果を記録
4. 優先度2のパラメータを追加で最適化

### ステップ3: ロバストネステスト
1. 最適化されたパラメータを使用
2. 異なる期間でテスト（2020-2024年など）
3. 異なる通貨ペアでテスト（EUR/USDなど）
4. 結果の一貫性を確認

### ステップ4: フォワードテスト
1. 最終パラメータを決定
2. デモ口座で3～6ヶ月運用
3. バックテストとの乖離を確認

## 注意事項

### オーバーフィッティングに注意
- 最適化しすぎると実運用で機能しなくなる
- パラメータは丸めの値を使用（1.47ではなく1.5など）
- 複数の期間・通貨ペアで安定した結果を目指す

### スプレッドの考慮
- バックテストではスプレッドを実際より広めに設定
- ブローカーの平均スプレッドを確認
- スリッページも考慮（5pips程度）

### データ品質
- 高品質な履歴データを使用
- ティックデータの欠損がないか確認
- 可能であればDukasCopyなどのデータを使用

## 結果の記録テンプレート

```
=== バックテスト結果 ===
日付: 2026/02/XX
通貨ペア: USD/JPY
期間: 2015/01/01 - 2024/12/31
初期資金: 1,000,000円

[パラメータ]
RiskPercent: 2.0%
ATR_Multiplier: 1.5
RiskRewardRatio: 1.5
UseDailyTrend: true

[結果]
総利益: XXX,XXX円
プロフィットファクター: X.XX
最大ドローダウン: XX.X%
総トレード数: XXX回
勝率: XX.X%
シャープレシオ: X.XX

[評価]
✓ プロフィットファクター > 1.5
✓ ドローダウン < 10%
✗ 勝率が目標未達

[次のアクション]
- ATR_Multiplierを2.0に増やして再テスト
- 4時間足フィルターを有効化して検証
```

---

**作成日**: 2026年2月16日
**対象EA**: 372手法改良版EA v1.0
