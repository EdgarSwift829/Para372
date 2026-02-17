//+------------------------------------------------------------------+
//|                                                      Para372.mq5 |
//|                                 Copyright 2026, Anthropic        |
//|                                             https://claude.ai   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Anthropic"
#property link      "https://claude.ai"
#property version   "1.20"
#property description "372手法改良版EA v1.2 - 経済指標停止機能追加"

//--- インクルード
#include <Trade\Trade.mqh>

//--- グローバル変数
CTrade trade;
int sar15m_handle, sar1h_handle, sar4h_handle;
int atr_handle;
datetime lastBarTime = 0;
int consecutiveLosses = 0;
datetime breakEndTime = 0;
bool isInBreak = false;

// 経済指標データ構造体
struct NewsEvent
{
    datetime time;        // 指標発表時刻
    string currency;      // 通貨（USD, EUR等）
    string title;         // 指標名
    int importance;       // 重要度（1=低、2=中、3=高）
};

NewsEvent newsEvents[];
int newsEventsCount = 0;
datetime lastNewsUpdate = 0;

//+------------------------------------------------------------------+
//| 入力パラメータ                                                      |
//+------------------------------------------------------------------+

//--- 基本設定
input group "=== 基本設定 ==="
input int Magic = 20250216;                    // マジックナンバー
input double RiskPercent = 2.0;                // リスク（口座残高の%）

//--- パラボリックSAR設定
input group "=== パラボリックSAR設定 ==="
input double Step15m = 0.02;                   // 15分足ステップ（大きいほどシグナル少）
input double Step1h = 0.02;                    // 1時間足ステップ
input double Step4h = 0.04;                    // 4時間足ステップ
input double Maximum = 0.2;                    // 最大値

//--- 決済条件設定
input group "=== 決済条件設定 ==="
input bool Close_Use15m = true;                // 15m足SARで決済
input bool Close_Use1h  = false;               // 1h足SARで決済（15mとOR条件）

//--- SL/TP設定
input group "=== ストップロス/テイクプロフィット設定 ==="
input int ATR_Period = 14;                     // ATR期間
input double ATR_Multiplier = 1.5;             // ATR倍率（SL幅）
input double RiskRewardRatio = 1.5;            // リスクリワード比率

//--- トレンドフィルター
input group "=== マルチタイムフレームトレンドフィルター ==="
input bool UseDailyTrend = true;               // 日足トレンドフィルター使用
input bool Use4HTrend = false;                 // 4時間足トレンドフィルター使用
input bool Use1HTrend = false;                 // 1時間足トレンドフィルター使用

//--- 負け後の休止機能
input group "=== 負け後の休止機能 ==="
input bool UseLossBreak = true;                // 休止機能使用
input int LossBreakCount = 5;                  // 連敗回数でトリガー
input string LossBreakUnit = "Hours";          // 単位（Hours/Bars/Days）
input int LossBreakPeriod = 4;                 // 休止期間

//--- 経済指標停止
input group "=== 経済指標フィルター ==="
input bool UseNewsFilter = true;               // 経済指標フィルター使用
input int NewsStopMinutesBefore = 60;          // 指標前停止時間（分）
input int NewsStopMinutesAfter = 60;           // 指標後停止時間（分）
input bool StopOn_High_Impact = true;          // 高重要度指標で停止
input bool StopOn_Medium_Impact = false;       // 中重要度指標で停止
input string NewsCalendarURL = "https://www.forexfactory.com/calendar"; // カレンダーURL（参考用）

//--- 月末・月初停止
input group "=== 月末・月初停止 ==="
input bool UseMonthEndStart = false;           // 月末月初停止機能使用

//--- ロット管理
input group "=== ロット管理 ==="
input int    LotMode     = 0;                  // 0=残高%リスク 1=残高ステップ固定
input double StepBalance = 50000;             // [Mode1] 何円ごとに0.01lot増やすか
input double BaseLot     = 0.01;              // [Mode1] 基準ロット（最小単位）

//--- ログ設定
input group "=== ログ出力設定 ==="
input bool VerboseLog = true;                  // 詳細ログ出力

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- トレード設定
    trade.SetExpertMagicNumber(Magic);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetAsyncMode(false);
    
    //--- パラボリックSARハンドル作成（15分足）
    sar15m_handle = iSAR(_Symbol, PERIOD_M15, Step15m, Maximum);
    if(sar15m_handle == INVALID_HANDLE)
    {
        Print("❌ 15分足SARインジケーターの作成に失敗しました");
        return(INIT_FAILED);
    }
    
    //--- パラボリックSARハンドル作成（1時間足）
    sar1h_handle = iSAR(_Symbol, PERIOD_H1, Step1h, Maximum);
    if(sar1h_handle == INVALID_HANDLE)
    {
        Print("❌ 1時間足SARインジケーターの作成に失敗しました");
        return(INIT_FAILED);
    }
    
    //--- パラボリックSARハンドル作成（4時間足）
    sar4h_handle = iSAR(_Symbol, PERIOD_H4, Step4h, Maximum);
    if(sar4h_handle == INVALID_HANDLE)
    {
        Print("❌ 4時間足SARインジケーターの作成に失敗しました");
        return(INIT_FAILED);
    }
    
    //--- ATRハンドル作成
    atr_handle = iATR(_Symbol, PERIOD_M15, ATR_Period);
    if(atr_handle == INVALID_HANDLE)
    {
        Print("❌ ATRインジケーターの作成に失敗しました");
        return(INIT_FAILED);
    }
    
    //--- 経済指標データを読み込み
    if(UseNewsFilter)
    {
        LoadNewsEvents();
    }
    
    //--- 初期化成功
    Print("========================================");
    Print("✅ 372手法改良版EA v1.2 - 初期化成功");
    Print("通貨ペア: ", _Symbol);
    Print("リスク設定: ", RiskPercent, "%");
    Print("経済指標フィルター: ", UseNewsFilter ? "有効" : "無効");
    Print("========================================");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- インジケーターハンドル解放
    if(sar15m_handle != INVALID_HANDLE) IndicatorRelease(sar15m_handle);
    if(sar1h_handle != INVALID_HANDLE) IndicatorRelease(sar1h_handle);
    if(sar4h_handle != INVALID_HANDLE) IndicatorRelease(sar4h_handle);
    if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
    
    Print("372手法改良版EA v1.2 - 終了");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- 新しいバーの確認
    datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
    if(currentBarTime == lastBarTime)
        return; // 同じバーなら何もしない
    
    lastBarTime = currentBarTime;
    
    //--- 経済指標フィルターチェック（最優先）
    if(UseNewsFilter && IsNewsTime())
    {
        if(VerboseLog)
            Print("📰 経済指標発表前後のため取引を停止中");
        return;
    }
    
    //--- 休止期間中かチェック
    if(CheckIfInBreak())
        return;
    
    //--- 月末・月初停止チェック
    if(UseMonthEndStart && IsMonthEndOrStart())
    {
        if(VerboseLog)
            Print("📅 月末または月初のため取引を停止中");
        return;
    }
    
    //--- 既存ポジションの確認
    if(PositionSelect(_Symbol))
    {
        // ポジションがある場合、決済シグナルをチェック
        CheckForClose();
    }
    else
    {
        // ポジションがない場合、エントリーシグナルをチェック
        CheckForEntry();
    }
}

//+------------------------------------------------------------------+
//| エントリーシグナルをチェック                                        |
//+------------------------------------------------------------------+
void CheckForEntry()
{
    //--- SAR値を取得
    double sar15m[], sar1h[], sar4h[];
    ArraySetAsSeries(sar15m, true);
    ArraySetAsSeries(sar1h, true);
    ArraySetAsSeries(sar4h, true);
    
    if(CopyBuffer(sar15m_handle, 0, 0, 3, sar15m) <= 0) return;
    if(CopyBuffer(sar1h_handle, 0, 0, 3, sar1h) <= 0) return;
    if(CopyBuffer(sar4h_handle, 0, 0, 3, sar4h) <= 0) return;
    
    //--- 現在価格を取得
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;
    
    //--- 確定足の価格を取得（Close[1]）
    double close1 = iClose(_Symbol, PERIOD_M15, 1);
    
    //--- 買いシグナル判定
    bool buySignal = (close1 > sar15m[1]) && (close1 > sar1h[1]) && (close1 > sar4h[1]);
    
    //--- 売りシグナル判定
    bool sellSignal = (close1 < sar15m[1]) && (close1 < sar1h[1]) && (close1 < sar4h[1]);
    
    //--- トレンドフィルターを適用
    if(buySignal && !CheckTrendFilter(true))
        buySignal = false;
    
    if(sellSignal && !CheckTrendFilter(false))
        sellSignal = false;
    
    //--- エントリー実行
    if(buySignal)
    {
        OpenPosition(ORDER_TYPE_BUY);
    }
    else if(sellSignal)
    {
        OpenPosition(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| 決済シグナルをチェック                                             |
//+------------------------------------------------------------------+
void CheckForClose()
{
    if(!PositionSelect(_Symbol)) return;
    
    long positionType = PositionGetInteger(POSITION_TYPE);
    
    //--- SAR値を取得
    double sar15m[], sar1h[], sar4h[];
    ArraySetAsSeries(sar15m, true);
    ArraySetAsSeries(sar1h, true);
    ArraySetAsSeries(sar4h, true);
    
    if(CopyBuffer(sar15m_handle, 0, 0, 3, sar15m) <= 0) return;
    if(CopyBuffer(sar1h_handle, 0, 0, 3, sar1h) <= 0) return;
    if(CopyBuffer(sar4h_handle, 0, 0, 3, sar4h) <= 0) return;
    
    //--- 確定足の価格を取得
    double close1 = iClose(_Symbol, PERIOD_M15, 1);
    
    //--- 決済シグナル判定（OR条件 = どちらか1つでも反転したら決済）
    bool closeSellSignal = false;
    bool closeBuySignal  = false;
    
    // 買いポジション決済条件（売りシグナル）
    if(Close_Use15m && (close1 < sar15m[1]))
        closeSellSignal = true;
    if(Close_Use1h && (close1 < sar1h[1]))
        closeSellSignal = true;
    
    // 売りポジション決済条件（買いシグナル）
    if(Close_Use15m && (close1 > sar15m[1]))
        closeBuySignal = true;
    if(Close_Use1h && (close1 > sar1h[1]))
        closeBuySignal = true;
    
    if(positionType == POSITION_TYPE_BUY)
    {
        if(closeSellSignal)
        {
            if(VerboseLog)
            {
                string trigger = Close_Use15m && (close1 < sar15m[1]) ? "15m" : "1h";
                Print("🔄 決済シグナル(買→決済) ", trigger, "足SAR反転");
            }
            ClosePosition();
            // ドテン
            if(CheckTrendFilter(false) && !IsNewsTime())
                OpenPosition(ORDER_TYPE_SELL);
        }
    }
    else if(positionType == POSITION_TYPE_SELL)
    {
        if(closeBuySignal)
        {
            if(VerboseLog)
            {
                string trigger = Close_Use15m && (close1 > sar15m[1]) ? "15m" : "1h";
                Print("🔄 決済シグナル(売→決済) ", trigger, "足SAR反転");
            }
            ClosePosition();
            // ドテン
            if(CheckTrendFilter(true) && !IsNewsTime())
                OpenPosition(ORDER_TYPE_BUY);
        }
    }
}

//+------------------------------------------------------------------+
//| ポジションを開く                                                   |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType)
{
    //--- ATR値を取得
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atr_handle, 0, 0, 2, atr) <= 0)
    {
        Print("❌ ATR値の取得に失敗しました");
        return;
    }
    
    double atrValue = atr[1]; // 確定足のATR
    
    //--- ストップロス幅を計算（ATR × 倍率）
    double slDistance = atrValue * ATR_Multiplier;
    
    //--- ロットサイズを計算
    double lotSize = CalculateLotSize(slDistance);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if(lotSize < minLot)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double riskAmount = accountBalance * (RiskPercent / 100.0);
        Print("========================================");
        Print("❌ エントリー見送り: 資金不足");
        Print("現在の口座残高: ", accountBalance, " 円");
        Print("リスク金額: ", riskAmount, " 円 (", RiskPercent, "%)");
        Print("必要ロット: ", lotSize, " → 最小ロット未満");
        Print("最小ロット(", minLot, ")でエントリーするには、");
        Print("約 ", NormalizeDouble(minLot * slDistance / _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / (RiskPercent / 100.0), 0), " 円の資金が必要です");
        Print("========================================");
        return;
    }
    
    //--- 現在価格を取得
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;
    
    double price, sl, tp;
    
    if(orderType == ORDER_TYPE_BUY)
    {
        price = tick.ask;
        sl = price - slDistance;
        tp = price + (slDistance * RiskRewardRatio);
        
        //--- 価格を正規化
        sl = NormalizeDouble(sl, _Digits);
        tp = NormalizeDouble(tp, _Digits);
        
        if(trade.Buy(lotSize, _Symbol, price, sl, tp, "372EA Buy"))
        {
            double slPips = (price - sl) / _Point;
            double tpPips = (tp - price) / _Point;
            Print("✅ 買いポジションオープン成功");
            Print("  ロット: ", lotSize);
            Print("  エントリー: ", price);
            Print("  SL: ", sl, " (", NormalizeDouble(slPips, 1), " pips)");
            Print("  TP: ", tp, " (", NormalizeDouble(tpPips, 1), " pips)");
            Print("  リスク金額: ", NormalizeDouble(lotSize * slPips * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 0), " 円");
        }
        else
        {
            Print("❌ 買いポジションオープン失敗: ", trade.ResultRetcodeDescription());
        }
    }
    else if(orderType == ORDER_TYPE_SELL)
    {
        price = tick.bid;
        sl = price + slDistance;
        tp = price - (slDistance * RiskRewardRatio);
        
        //--- 価格を正規化
        sl = NormalizeDouble(sl, _Digits);
        tp = NormalizeDouble(tp, _Digits);
        
        if(trade.Sell(lotSize, _Symbol, price, sl, tp, "372EA Sell"))
        {
            double slPips = (sl - price) / _Point;
            double tpPips = (price - tp) / _Point;
            Print("✅ 売りポジションオープン成功");
            Print("  ロット: ", lotSize);
            Print("  エントリー: ", price);
            Print("  SL: ", sl, " (", NormalizeDouble(slPips, 1), " pips)");
            Print("  TP: ", tp, " (", NormalizeDouble(tpPips, 1), " pips)");
            Print("  リスク金額: ", NormalizeDouble(lotSize * slPips * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 0), " 円");
        }
        else
        {
            Print("❌ 売りポジションオープン失敗: ", trade.ResultRetcodeDescription());
        }
    }
}

//+------------------------------------------------------------------+
//| ポジションを閉じる                                                 |
//+------------------------------------------------------------------+
void ClosePosition()
{
    if(!PositionSelect(_Symbol)) return;
    
    ulong ticket = PositionGetInteger(POSITION_TICKET);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    long positionType = PositionGetInteger(POSITION_TYPE);
    
    if(trade.PositionClose(ticket))
    {
        Print("✅ ポジション決済成功");
        
        //--- 損益を判定して連敗カウンターを更新
        bool isProfit = false;
        if(positionType == POSITION_TYPE_BUY)
            isProfit = (currentPrice > openPrice);
        else
            isProfit = (currentPrice < openPrice);
        
        if(isProfit)
        {
            consecutiveLosses = 0; // 勝ちでリセット
            Print("💰 勝ちトレード - 連敗カウンターリセット");
        }
        else
        {
            consecutiveLosses++;
            Print("📉 負けトレード - 連敗カウント: ", consecutiveLosses);
            
            //--- 連敗数が設定値に達したら休止開始
            if(UseLossBreak && consecutiveLosses >= LossBreakCount)
            {
                StartBreakPeriod();
            }
        }
    }
    else
    {
        Print("❌ ポジション決済失敗: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| ロットサイズを計算（v1.1修正版）                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double lotSize = minLot;

    //==========================================================
    // Mode 0: 残高に対して%リスク（デフォルト）
    //==========================================================
    if(LotMode == 0)
    {
        double riskAmount  = accountBalance * (RiskPercent / 100.0);
        double tickValue   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double slPoints    = slDistance / point;
        double riskPerLot  = slPoints * tickValue;
        
        lotSize = riskAmount / riskPerLot;
        
        if(VerboseLog)
        {
            Print("--- ロット計算 [Mode0: %リスク] ---");
            Print("口座残高: ", accountBalance, " / リスク: ", RiskPercent, "% = ", riskAmount);
            Print("SL幅: ", slPoints, " pts / 1lotリスク: ", riskPerLot);
            Print("計算ロット: ", lotSize);
        }
        
        if(lotSize < minLot)
        {
            Print("⚠️ 計算ロット(", NormalizeDouble(lotSize,3), ")が最小ロット(", minLot, ")未満");
            Print("   必要資金目安: ", NormalizeDouble(riskPerLot * minLot / (RiskPercent / 100.0), 0), " 円");
        }
    }
    //==========================================================
    // Mode 1: 残高ステップ固定（〇万円ごとに0.01lot）
    //==========================================================
    else if(LotMode == 1)
    {
        // 例: StepBalance=50000, BaseLot=0.01
        // 残高  5万円 → 0.01lot
        // 残高 10万円 → 0.02lot
        // 残高 15万円 → 0.03lot
        double steps = MathFloor(accountBalance / StepBalance);
        steps = MathMax(steps, 1); // 最低1ステップ
        lotSize = BaseLot * steps;
        
        if(VerboseLog)
        {
            Print("--- ロット計算 [Mode1: 残高ステップ] ---");
            Print("口座残高: ", accountBalance, " / ステップ単位: ", StepBalance, " 円");
            Print("ステップ数: ", steps, " / ロット: ", BaseLot, " × ", steps, " = ", lotSize);
        }
    }

    //--- ロットステップに合わせて切り捨て
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    //--- 最小・最大ロット範囲内に収める
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    if(VerboseLog)
        Print("最終ロット: ", lotSize);
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| トレンドフィルターをチェック                                        |
//+------------------------------------------------------------------+
bool CheckTrendFilter(bool isBuy)
{
    //--- 日足トレンドフィルター
    if(UseDailyTrend)
    {
        if(!CheckTimeframeTrend(PERIOD_D1, isBuy))
            return false;
    }
    
    //--- 4時間足トレンドフィルター
    if(Use4HTrend)
    {
        if(!CheckTimeframeTrend(PERIOD_H4, isBuy))
            return false;
    }
    
    //--- 1時間足トレンドフィルター
    if(Use1HTrend)
    {
        if(!CheckTimeframeTrend(PERIOD_H1, isBuy))
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| 指定時間足のトレンドをチェック                                      |
//+------------------------------------------------------------------+
bool CheckTimeframeTrend(ENUM_TIMEFRAMES timeframe, bool isBuy)
{
    double close1 = iClose(_Symbol, timeframe, 1);
    double close2 = iClose(_Symbol, timeframe, 2);
    double close3 = iClose(_Symbol, timeframe, 3);
    
    if(isBuy)
    {
        // 上昇トレンド判定
        return (close1 > close2) && (close2 > close3);
    }
    else
    {
        // 下降トレンド判定
        return (close1 < close2) && (close2 < close3);
    }
}

//+------------------------------------------------------------------+
//| 休止期間を開始                                                     |
//+------------------------------------------------------------------+
void StartBreakPeriod()
{
    isInBreak = true;
    
    if(LossBreakUnit == "Hours")
    {
        breakEndTime = TimeCurrent() + (LossBreakPeriod * 3600);
    }
    else if(LossBreakUnit == "Days")
    {
        breakEndTime = TimeCurrent() + (LossBreakPeriod * 86400);
    }
    else if(LossBreakUnit == "Bars")
    {
        // バー数での計算（15分足基準）
        breakEndTime = iTime(_Symbol, PERIOD_M15, 0) + (LossBreakPeriod * 15 * 60);
    }
    else
    {
        // デフォルトは時間
        breakEndTime = TimeCurrent() + (LossBreakPeriod * 3600);
    }
    
    Print("========================================");
    Print("🛑 休止期間開始");
    Print("連敗回数: ", consecutiveLosses);
    Print("休止終了時刻: ", TimeToString(breakEndTime));
    Print("========================================");
    
    consecutiveLosses = 0; // カウンターリセット
}

//+------------------------------------------------------------------+
//| 休止期間中かチェック                                               |
//+------------------------------------------------------------------+
bool CheckIfInBreak()
{
    if(!UseLossBreak) return false;
    if(!isInBreak) return false;
    
    if(TimeCurrent() >= breakEndTime)
    {
        isInBreak = false;
        Print("========================================");
        Print("✅ 休止期間終了 - 取引再開");
        Print("========================================");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| 月末・月初かチェック                                               |
//+------------------------------------------------------------------+
bool IsMonthEndOrStart()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    //--- 月初（1日）
    if(dt.day == 1)
        return true;
    
    //--- 月末の判定
    // 次の日が翌月の1日かチェック
    datetime tomorrow = TimeCurrent() + 86400;
    MqlDateTime dtTomorrow;
    TimeToStruct(tomorrow, dtTomorrow);
    
    if(dtTomorrow.day == 1)
        return true; // 今日が月の最終日
    
    return false;
}

//+------------------------------------------------------------------+
//| 経済指標データを読み込み                                            |
//+------------------------------------------------------------------+
void LoadNewsEvents()
{
    // この関数では手動で経済指標を登録します
    // 実際の運用では、毎週月曜日に手動で更新するか、
    // 外部ファイル（CSVなど）から読み込むことを推奨
    
    ArrayResize(newsEvents, 50); // 最大50件
    newsEventsCount = 0;
    
    // サンプル: 手動で指標を登録
    // AddNewsEvent("2026.02.17 22:30", "USD", "米国雇用統計", 3);
    // AddNewsEvent("2026.02.18 04:00", "USD", "FOMC政策金利", 3);
    
    Print("📰 経済指標データ読み込み完了: ", newsEventsCount, "件");
    
    if(newsEventsCount == 0)
    {
        Print("⚠️ 経済指標が登録されていません");
        Print("   手動でAddNewsEvent関数を使用して登録してください");
    }
}

//+------------------------------------------------------------------+
//| 経済指標を手動追加                                                  |
//+------------------------------------------------------------------+
void AddNewsEvent(string timeStr, string currency, string title, int importance)
{
    if(newsEventsCount >= ArraySize(newsEvents))
    {
        ArrayResize(newsEvents, ArraySize(newsEvents) + 50);
    }
    
    newsEvents[newsEventsCount].time = StringToTime(timeStr);
    newsEvents[newsEventsCount].currency = currency;
    newsEvents[newsEventsCount].title = title;
    newsEvents[newsEventsCount].importance = importance;
    
    newsEventsCount++;
}

//+------------------------------------------------------------------+
//| 経済指標時間帯かチェック                                            |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
    if(!UseNewsFilter || newsEventsCount == 0)
        return false;
    
    datetime currentTime = TimeCurrent();
    
    // 通貨ペアから関連通貨を抽出
    string baseCurrency = StringSubstr(_Symbol, 0, 3);
    string quoteCurrency = StringSubstr(_Symbol, 3, 3);
    
    for(int i = 0; i < newsEventsCount; i++)
    {
        // 指標時刻の前後チェック
        datetime startTime = newsEvents[i].time - (NewsStopMinutesBefore * 60);
        datetime endTime = newsEvents[i].time + (NewsStopMinutesAfter * 60);
        
        if(currentTime >= startTime && currentTime <= endTime)
        {
            // 通貨ペアに関連する指標かチェック
            if(newsEvents[i].currency == baseCurrency || 
               newsEvents[i].currency == quoteCurrency)
            {
                // 重要度チェック
                if(newsEvents[i].importance == 3 && StopOn_High_Impact)
                {
                    if(VerboseLog)
                    {
                        Print("📰 高重要度指標: ", newsEvents[i].title);
                        Print("   発表時刻: ", TimeToString(newsEvents[i].time));
                    }
                    return true;
                }
                
                if(newsEvents[i].importance == 2 && StopOn_Medium_Impact)
                {
                    if(VerboseLog)
                    {
                        Print("📰 中重要度指標: ", newsEvents[i].title);
                        Print("   発表時刻: ", TimeToString(newsEvents[i].time));
                    }
                    return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| OnTester - 最適化スコア計算                                         |
//| 「Custom max」基準で最適化する際に使用される                          |
//+------------------------------------------------------------------+
double OnTester()
{
    //--- テスト結果を取得
    double profit        = TesterStatistics(STAT_PROFIT);              // 純利益
    double profitFactor  = TesterStatistics(STAT_PROFIT_FACTOR);       // プロフィットファクター
    double maxDrawdown   = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);// 最大ドローダウン（%）
    double totalTrades   = TesterStatistics(STAT_TRADES);              // 総トレード数
    double profitTrades  = TesterStatistics(STAT_PROFIT_TRADES);       // 利益トレード数
    double sharpeRatio   = TesterStatistics(STAT_SHARPE_RATIO);        // シャープレシオ

    //--- 勝率を計算
    double winRate = (totalTrades > 0) ? (profitTrades / totalTrades * 100.0) : 0;

    //--- トレード数が少なすぎる場合は0を返す（信頼性が低い結果を排除）
    if(totalTrades < 30)
        return 0;

    //--- 利益がマイナスの場合は0を返す
    if(profit <= 0)
        return 0;

    //--- ドローダウンが大きすぎる場合は0を返す（20%超は除外）
    if(maxDrawdown > 20.0)
        return 0;

    //--- カスタムスコアの計算
    // プロフィットファクター × 勝率の重み - ドローダウンのペナルティ
    double score = profitFactor * (winRate / 100.0) - (maxDrawdown / 100.0);

    //--- シャープレシオが正の場合はボーナス加算
    if(sharpeRatio > 0)
        score += sharpeRatio * 0.1;

    return score;
}
//+------------------------------------------------------------------+
