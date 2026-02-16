//+------------------------------------------------------------------+
//|                                                      Para372.mq5 |
//|                                 Copyright 2023, Yusuke Yamaguchi |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Anthropic"
#property link      "https://claude.ai"
#property version   "1.00"
#property description "372手法改良版EA - 3本のパラボリックSARを使用したトレンドフォロー戦略"

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

//+------------------------------------------------------------------+
//| 入力パラメータ                                                      |
//+------------------------------------------------------------------+

//--- 基本設定
input group "=== 基本設定 ==="
input int Magic = 20250216;                    // マジックナンバー
input double RiskPercent = 2.0;                // リスク（口座残高の%）

//--- パラボリックSAR設定
input group "=== パラボリックSAR設定 ==="
input double Step15m = 0.001;                  // 15分足ステップ
input double Step1h = 0.01;                    // 1時間足ステップ
input double Step4h = 0.035;                   // 4時間足ステップ
input double Maximum = 0.2;                    // 最大値

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

//--- 経済指標停止（今後実装予定）
input group "=== 経済指標フィルター（未実装） ==="
input bool UseNewsFilter = false;              // 経済指標フィルター使用（v2.0で実装予定）

//--- 月末・月初停止
input group "=== 月末・月初停止 ==="
input bool UseMonthEndStart = false;           // 月末月初停止機能使用

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
        Print("15分足SARインジケーターの作成に失敗しました");
        return(INIT_FAILED);
    }
    
    //--- パラボリックSARハンドル作成（1時間足）
    sar1h_handle = iSAR(_Symbol, PERIOD_H1, Step1h, Maximum);
    if(sar1h_handle == INVALID_HANDLE)
    {
        Print("1時間足SARインジケーターの作成に失敗しました");
        return(INIT_FAILED);
    }
    
    //--- パラボリックSARハンドル作成（4時間足）
    sar4h_handle = iSAR(_Symbol, PERIOD_H4, Step4h, Maximum);
    if(sar4h_handle == INVALID_HANDLE)
    {
        Print("4時間足SARインジケーターの作成に失敗しました");
        return(INIT_FAILED);
    }
    
    //--- ATRハンドル作成
    atr_handle = iATR(_Symbol, PERIOD_M15, ATR_Period);
    if(atr_handle == INVALID_HANDLE)
    {
        Print("ATRインジケーターの作成に失敗しました");
        return(INIT_FAILED);
    }
    
    //--- 初期化成功
    Print("372手法改良版EA - 初期化成功");
    Print("通貨ペア: ", _Symbol);
    Print("リスク設定: ", RiskPercent, "%");
    
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
    
    Print("372手法改良版EA - 終了");
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
    
    //--- 休止期間中かチェック
    if(CheckIfInBreak())
        return;
    
    //--- 月末・月初停止チェック
    if(UseMonthEndStart && IsMonthEndOrStart())
    {
        Print("月末または月初のため取引を停止中");
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
    
    double currentPrice = tick.last;
    
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
    
    //--- ドテン判定
    bool shouldCloseBuy = false;
    bool shouldCloseSell = false;
    
    if(positionType == POSITION_TYPE_BUY)
    {
        // 買いポジションを持っている場合、売りシグナルで決済
        shouldCloseBuy = (close1 < sar15m[1]) && (close1 < sar1h[1]) && (close1 < sar4h[1]);
        
        if(shouldCloseBuy)
        {
            ClosePosition();
            // ドテン: 即座に売りポジションを開く
            if(CheckTrendFilter(false))
                OpenPosition(ORDER_TYPE_SELL);
        }
    }
    else if(positionType == POSITION_TYPE_SELL)
    {
        // 売りポジションを持っている場合、買いシグナルで決済
        shouldCloseSell = (close1 > sar15m[1]) && (close1 > sar1h[1]) && (close1 > sar4h[1]);
        
        if(shouldCloseSell)
        {
            ClosePosition();
            // ドテン: 即座に買いポジションを開く
            if(CheckTrendFilter(true))
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
        Print("ATR値の取得に失敗しました");
        return;
    }
    
    double atrValue = atr[1]; // 確定足のATR
    
    //--- ストップロス幅を計算（ATR × 倍率）
    double slDistance = atrValue * ATR_Multiplier;
    
    //--- ロットサイズを計算
    double lotSize = CalculateLotSize(slDistance);
    
    if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
    {
        Print("計算されたロットサイズが最小値未満です。エントリーを見送ります。");
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
            Print("買いポジションオープン成功: Lot=", lotSize, " SL=", sl, " TP=", tp);
        }
        else
        {
            Print("買いポジションオープン失敗: ", trade.ResultRetcodeDescription());
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
            Print("売りポジションオープン成功: Lot=", lotSize, " SL=", sl, " TP=", tp);
        }
        else
        {
            Print("売りポジションオープン失敗: ", trade.ResultRetcodeDescription());
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
        Print("ポジション決済成功");
        
        //--- 損益を判定して連敗カウンターを更新
        bool isProfit = false;
        if(positionType == POSITION_TYPE_BUY)
            isProfit = (currentPrice > openPrice);
        else
            isProfit = (currentPrice < openPrice);
        
        if(isProfit)
        {
            consecutiveLosses = 0; // 勝ちでリセット
            Print("勝ちトレード - 連敗カウンターリセット");
        }
        else
        {
            consecutiveLosses++;
            Print("負けトレード - 連敗カウント: ", consecutiveLosses);
            
            //--- 連敗数が設定値に達したら休止開始
            if(UseLossBreak && consecutiveLosses >= LossBreakCount)
            {
                StartBreakPeriod();
            }
        }
    }
    else
    {
        Print("ポジション決済失敗: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| ロットサイズを計算                                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
    //--- 口座残高を取得
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    //--- リスク金額を計算
    double riskAmount = accountBalance * (RiskPercent / 100.0);
    
    //--- ピップ価値を計算
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    //--- SL幅をピップに変換
    double slPips = slDistance / point;
    
    //--- ロットサイズを計算
    double lotSize = riskAmount / (slPips * tickValue / tickSize);
    
    //--- ロット制限を適用
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
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
    
    Print("=== 休止期間開始 ===");
    Print("連敗回数: ", consecutiveLosses);
    Print("休止終了時刻: ", TimeToString(breakEndTime));
    
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
        Print("=== 休止期間終了 - 取引再開 ===");
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