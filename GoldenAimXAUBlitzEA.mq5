//+------------------------------------------------------------------+
//|                  Golden Aim XAU Blitz EA                         |
//|                      SWEET BUT DEADLY                            |
//|                 Kin Legacy Holdings Limited                      |
//|             BUILDING A DYNASTY, LEAVING A LEGACY                  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Golden Aim XAU Blitz EA"
#property description "Sweet but Deadly"
#property description "Kin Legacy Holdings Limited"
#property description "Building a Dynasty, Leaving a Legacy"

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
// INPUTS
//====================================================================
input bool   InpAllowDemo                 = false;
input bool   InpAllowLive                 = true;
input bool   InpMassExecution             = false;

input double InpDailyProfitTarget         = 12.0;
input double InpRiskPercent               = 0.35;
input double InpDailyLossLimitPct         = 2.00;
input double InpMaxCombinedRiskPct        = 0.80;

input int    InpMaxPositions              = 1;
input int    InpMaxEntriesPerMinute       = 1;
input int    InpCooldownSeconds           = 30;
input int    InpMaxSpreadPoints           = 150;

input int    InpFastEMA                   = 9;
input int    InpSlowEMA                   = 21;
input int    InpTrendEMA                  = 50;

input int    InpRSIPeriod                 = 14;
input int    InpADXPeriod                 = 14;
input int    InpATRPeriod                 = 14;

input bool   InpUseSMIConfirmation        = false;
input int    InpSMIKPeriod                = 5;
input int    InpSMIDPeriod                = 3;
input int    InpSMISlowing                = 3;

input int    InpSMCLookback               = 10;
input bool   InpRequireSMCConfirmation    = true;
input bool   InpAllowLiquiditySweeps      = true;

input bool   InpUseSMTConfirmation        = true;
input string InpSMTSymbol                 = "";
input int    InpSMTLookback               = 10;

input double InpMinimumADX                = 15.0;
input double InpBuyRSIMin                 = 50.0;
input double InpBuyRSIMax                 = 72.0;
input double InpSellRSIMin                = 28.0;
input double InpSellRSIMax                = 50.0;

input double InpStopATRMultiplier         = 1.5;
input double InpRewardRiskRatio            = 1.5;
input double InpBreakEvenAtR               = 0.8;

input bool   InpUseLondonSession          = true;
input bool   InpUseNewYorkSession         = true;
input bool   InpUseAsianSession           = false;

input int    InpAsianStartHour            = 0;
input int    InpAsianEndHour              = 8;
input int    InpLondonStartHour           = 8;
input int    InpLondonEndHour             = 17;
input int    InpNewYorkStartHour          = 13;
input int    InpNewYorkEndHour            = 22;

input int    InpRapidMaxEntriesPerMinute  = 1;
input int    InpRapidCooldownSeconds      = 30;
input int    InpNormalMaxEntriesPerMinute = 1;
input int    InpNormalCooldownSeconds     = 30;

input bool   InpUseManualNewsFilter       = true;
input string InpNewsTimes                 = "";
input int    InpNewsMinutesBefore         = 30;
input int    InpNewsMinutesAfter          = 30;

input ulong  InpMagicNumber               = 26101501;
input int    InpDeviationPoints           = 20;

//====================================================================
// GLOBAL STATE
//====================================================================
int g_fastHandle  = INVALID_HANDLE;
int g_slowHandle  = INVALID_HANDLE;
int g_trendHandle = INVALID_HANDLE;
int g_rsiHandle   = INVALID_HANDLE;
int g_adxHandle   = INVALID_HANDLE;
int g_atrHandle   = INVALID_HANDLE;

string g_status = "INITIALIZING";
string g_currency = "";
string g_brokerSymbol = "";
string g_oppositeSymbol = "";

bool g_authorized = true;
bool g_tradingEnabled = false;
bool g_stopForToday = false;
bool g_dailyLossLocked = false;
bool g_dailyTargetOverride = false;
bool g_rapidMode = false;
bool g_specsRead = false;

double g_dayStartEquity = 0.0;
int g_dayKey = 0;

datetime g_lastEntryTime = 0;
datetime g_entryWindowStart = 0;
int g_entriesInWindow = 0;
datetime g_lastSignalBar = 0;

double g_lastSpread = 0.0;
double g_lastRiskBudget = 0.0;
double g_lastMinimumLotRisk = 0.0;

string OBJ_PREFIX = "GAXB_";

//====================================================================
// BASIC UTILITIES
//====================================================================
string UpperText(string value)
{
   StringToUpper(value);
   return value;
}

//--------------------------------------------------------------------
bool IsGoldName(string symbol)
{
   string s = UpperText(symbol);

   if(StringFind(s,"XAU") >= 0) return true;
   if(StringFind(s,"GOLD") >= 0) return true;

   return false;
}

//--------------------------------------------------------------------
bool IsSilverName(string symbol)
{
   string s = UpperText(symbol);

   if(StringFind(s,"XAG") >= 0) return true;
   if(StringFind(s,"SILVER") >= 0) return true;

   return false;
}

//--------------------------------------------------------------------
bool IsMetalSymbol(string symbol)
{
   return (IsGoldName(symbol) || IsSilverName(symbol));
}

//--------------------------------------------------------------------
bool IsGoldChart()
{
   return IsGoldName(_Symbol);
}

//--------------------------------------------------------------------
bool IsSilverChart()
{
   return IsSilverName(_Symbol);
}

//--------------------------------------------------------------------
bool IsAllowedChartMetal()
{
   return IsMetalSymbol(_Symbol);
}

//--------------------------------------------------------------------
int CurrentDayKey()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);

   return dt.year*10000 + dt.mon*100 + dt.day;
}

//--------------------------------------------------------------------
datetime StartOfToday()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);

   dt.hour=0;
   dt.min=0;
   dt.sec=0;

   return StructToTime(dt);
}

//--------------------------------------------------------------------
double CurrentSpreadPoints()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return 999999.0;

   if(_Point <= 0.0)
      return 999999.0;

   return (tick.ask-tick.bid)/_Point;
}

//--------------------------------------------------------------------
bool IsDemoAccount()
{
   ENUM_ACCOUNT_TRADE_MODE mode =
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);

   return (mode == ACCOUNT_TRADE_MODE_DEMO);
}

//--------------------------------------------------------------------
bool IsAccountAllowed()
{
   if(IsDemoAccount())
      return InpAllowDemo;

   return InpAllowLive;
}

//--------------------------------------------------------------------
bool IsValidTimeframe()
{
   return (_Period == PERIOD_M1 || _Period == PERIOD_M5);
}

//--------------------------------------------------------------------
double NormalizePriceToTick(double price)
{
   double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0.0)
      tickSize = _Point;

   if(tickSize <= 0.0)
      return price;

   double result = MathRound(price/tickSize)*tickSize;

   return NormalizeDouble(result,_Digits);
}

//--------------------------------------------------------------------
int VolumeDigitsFromStep(double step)
{
   for(int digits=0; digits<=8; digits++)
   {
      if(MathAbs(step-NormalizeDouble(step,digits)) < 0.000000001)
         return digits;
   }

   return 8;
}
   
//--------------------------------------------------------------------
double NormalizeVolumeDown(double volume)
{
   double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);

   if(step <= 0.0 || minLot <= 0.0 || maxLot <= 0.0)
      return 0.0;

   volume = MathMin(volume,maxLot);

   double steps = MathFloor((volume+1e-10)/step);
   double result = steps*step;

   result = NormalizeDouble(result,VolumeDigitsFromStep(step));

   if(result < minLot-1e-9)
      return 0.0;

   return result;
}

//====================================================================
// SYMBOL DISCOVERY AND LIVE BROKER SPECIFICATIONS
//====================================================================
bool SymbolHasUsableData(string symbol)
{
   if(symbol == "")
      return false;

   if(!SymbolSelect(symbol,true))
      return false;

   long tradeMode = SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);

   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
      return false;

   MqlTick tick;

   if(!SymbolInfoTick(symbol,tick))
      return false;

   if(tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask < tick.bid)
      return false;

   if(Bars(symbol,PERIOD_M1) < 20)
      return false;

   return true;
}
//--------------------------------------------------------------------
string FindOppositeMetalSymbol()
{
   bool chartGold = IsGoldName(_Symbol);
   bool chartSilver = IsSilverName(_Symbol);

   if(!chartGold && !chartSilver)
      return "";

   // First try the user's requested comparison symbol.
   if(InpSMTSymbol != "" && InpSMTSymbol != _Symbol)
   {
      if(SymbolHasUsableData(InpSMTSymbol))
      {
         if((chartGold && IsSilverName(InpSMTSymbol)) ||
            (chartSilver && IsGoldName(InpSMTSymbol)))
            return InpSMTSymbol;
      }
   }

   // Next, search symbols already visible in Market Watch.
   int total = SymbolsTotal(true);

   for(int i=0; i<total; i++)
   {
      string candidate = SymbolName(i,true);

      if(candidate == _Symbol)
         continue;

      if(!IsMetalSymbol(candidate))
         continue;

      if((chartGold && IsSilverName(candidate)) ||
         (chartSilver && IsGoldName(candidate)))
      {
         if(SymbolHasUsableData(candidate))
            return candidate;
      }
   }

   // Finally, search all broker symbols.
   total = SymbolsTotal(false);

   for(int i=0; i<total; i++)
   {
      string candidate = SymbolName(i,false);

      if(candidate == _Symbol)
         continue;

      if(!IsMetalSymbol(candidate))
         continue;

      if((chartGold && IsSilverName(candidate)) ||
         (chartSilver && IsGoldName(candidate)))
      {
         if(SymbolHasUsableData(candidate))
            return candidate;
      }
   }

   return "";
}
//--------------------------------------------------------------------
bool ReadBrokerSpecifications()
{
   string company = AccountInfoString(ACCOUNT_COMPANY);
   string server = AccountInfoString(ACCOUNT_SERVER);

   g_currency = AccountInfoString(ACCOUNT_CURRENCY);
   g_brokerSymbol = _Symbol;

   double contract = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickValueProfit =
      SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_PROFIT);
   double tickValueLoss =
      SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);

   double minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   long digits = SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   long stops = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   long tradeMode = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   long filling = SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   long calcMode = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_CALC_MODE);

   Print("==================================================");
   Print("Golden Aim XAU Blitz EA - LIVE BROKER SPECIFICATIONS");
   
      Print("Company: ",company);
   Print("Server: ",server);
   Print("Account currency: ",g_currency);
   Print("Chart symbol: ",_Symbol);
   Print("Timeframe: ",EnumToString((ENUM_TIMEFRAMES)_Period));
   Print("Digits: ",digits);
   Print("Contract size: ",DoubleToString(contract,4));
   Print("Tick size: ",DoubleToString(tickSize,8));
   Print("Tick value: ",DoubleToString(tickValue,8));
   Print("Tick value profit: ",DoubleToString(tickValueProfit,8));
   Print("Tick value loss: ",DoubleToString(tickValueLoss,8));
   Print("Minimum lot: ",DoubleToString(minLot,8));
   Print("Maximum lot: ",DoubleToString(maxLot,8));
   Print("Lot step: ",DoubleToString(lotStep,8));
   Print("Stops level: ",stops);
   Print("Freeze level: ",freeze);
   Print("Trade mode: ",tradeMode);
   Print("Filling mode: ",filling);
   Print("Calculation mode: ",calcMode);
   Print("==================================================");

   if(contract <= 0.0 || tickSize <= 0.0 ||
      minLot <= 0.0 || maxLot < minLot || lotStep <= 0.0)
   {
      Print("ERROR: Broker symbol specifications are invalid.");
      return false;
   }

   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED ||
      tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      Print("ERROR: This symbol is not currently open for new trades.");
      return false;
   }

   g_specsRead = true;
   g_oppositeSymbol = FindOppositeMetalSymbol();

   if(g_oppositeSymbol != "")
      Print("SMT comparison symbol found: ",g_oppositeSymbol);
   else
      Print("SMT comparison symbol not found. SMT confirmation unavailable.");

   return true;
}

//====================================================================
// PERSISTENT DAILY STATE
//====================================================================
string StateKey(string suffix)
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);

   return "GAXB_" + IntegerToString((int)login) + "_" +
          IntegerToString((int)InpMagicNumber) + "_" + suffix;
}
//--------------------------------------------------------------------
void SaveDailyState()
{
   GlobalVariableSet(StateKey("DAY"),(double)g_dayKey);
   GlobalVariableSet(StateKey("START_EQ"),g_dayStartEquity);
   GlobalVariableSet(StateKey("STOP_TODAY"),g_stopForToday ? 1.0 : 0.0);
   GlobalVariableSet(StateKey("LOSS_LOCK"),g_dailyLossLocked ? 1.0 : 0.0);
}
//--------------------------------------------------------------------
void LoadDailyState()
{
   g_dayKey = CurrentDayKey();

   if(GlobalVariableCheck(StateKey("DAY")) &&
      (int)GlobalVariableGet(StateKey("DAY")) == g_dayKey)
   {
      if(GlobalVariableCheck(StateKey("START_EQ")))
         g_dayStartEquity = GlobalVariableGet(StateKey("START_EQ"));

      if(GlobalVariableCheck(StateKey("STOP_TODAY")))
         g_stopForToday = (GlobalVariableGet(StateKey("STOP_TODAY")) > 0.5);

      if(GlobalVariableCheck(StateKey("LOSS_LOCK")))
         g_dailyLossLocked = (GlobalVariableGet(StateKey("LOSS_LOCK")) > 0.5);
   }
   else
   {
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_stopForToday = false;
      g_dailyLossLocked = false;
      g_dailyTargetOverride = false;
      SaveDailyState();
   }

   if(g_dayStartEquity <= 0.0)
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
}
//--------------------------------------------------------------------
void UpdateRiskPeriods()
{
   int today = CurrentDayKey();

   if(today != g_dayKey)
   {
      g_dayKey = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_stopForToday = false;
      g_dailyLossLocked = false;
      g_dailyTargetOverride = false;
      g_tradingEnabled = false;

      g_status = "NEW DAY - CLICK CONTINUE";
      SaveDailyState();

      Print("Golden Aim XAU Blitz EA: new trading day. Daily state reset.");
   }
}

//====================================================================
// DAILY PROFIT / LOSS CALCULATIONS
//====================================================================
double GetDailyNet()
{
   datetime fromTime = StartOfToday();
   datetime toTime = TimeCurrent();

   if(!HistorySelect(fromTime,toTime))
      return 0.0;

   double net = 0.0;
   int total = HistoryDealsTotal();

   for(int i=0; i<total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);

      if(ticket == 0)
         continue;

      long magic = HistoryDealGetInteger(ticket,DEAL_MAGIC);

      if((ulong)magic != InpMagicNumber)
         continue;

      ENUM_DEAL_TYPE type =
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);

      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         continue;

      net += HistoryDealGetDouble(ticket,DEAL_PROFIT);
      net += HistoryDealGetDouble(ticket,DEAL_SWAP);
      net += HistoryDealGetDouble(ticket,DEAL_COMMISSION);
   }
   
      return net;
}
//--------------------------------------------------------------------
double GetDailyEquityDrawdownPct()
{
   if(g_dayStartEquity <= 0.0)
      return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = g_dayStartEquity-equity;

   if(drawdown <= 0.0)
      return 0.0;

   return 100.0*drawdown/g_dayStartEquity;
}
//--------------------------------------------------------------------
bool CheckLossLimits()
{
   if(InpDailyLossLimitPct <= 0.0)
      return true;

   double dd = GetDailyEquityDrawdownPct();

   if(dd >= InpDailyLossLimitPct)
   {
      g_dailyLossLocked = true;
      g_tradingEnabled = false;
      g_status = "DAILY LOSS LIMIT - LOCKED";
      SaveDailyState();

      Print("Golden Aim XAU Blitz EA: daily loss limit reached. Drawdown=",
            DoubleToString(dd,2),"%");

      return false;
   }

   return true;
}

//====================================================================
// POSITION AND RISK CALCULATIONS
//====================================================================
int CountMyPositions()
{
   int count = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(!IsMetalSymbol(PositionGetString(POSITION_SYMBOL)))
         continue;

      count++;
   }

   return count;
}
//--------------------------------------------------------------------
double GetOpenRiskMoney()
{
   double risk = 0.0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double stop = PositionGetDouble(POSITION_SL);

      if(stop <= 0.0)
      {
         // A position without a stop has unknown downside risk.
         return AccountInfoDouble(ACCOUNT_EQUITY);
      }

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      ENUM_ORDER_TYPE orderType =
         (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      double pnlAtStop = 0.0;

      if(!OrderCalcProfit(orderType,symbol,volume,openPrice,stop,pnlAtStop))
         return AccountInfoDouble(ACCOUNT_EQUITY);

      if(pnlAtStop < 0.0)
         risk += MathAbs(pnlAtStop);
   }

   return risk;
}
//--------------------------------------------------------------------
bool CalculateRiskAtStop(ENUM_ORDER_TYPE direction,
                         double entry,
                         double stop,
                         double volume,
                         double &riskMoney)
{
   riskMoney = 0.0;

   if(volume <= 0.0 || entry <= 0.0 || stop <= 0.0)
      return false;

   double pnl = 0.0;

   ResetLastError();

   if(!OrderCalcProfit(direction,_Symbol,volume,entry,stop,pnl))
   {
      Print("OrderCalcProfit failed. Error=",GetLastError(),
            " Symbol=",_Symbol,
            " Volume=",DoubleToString(volume,4));

      return false;
   }

   riskMoney = MathAbs(MathMin(0.0,pnl));

   return true;
}
//--------------------------------------------------------------------
double CalculateVolume(ENUM_ORDER_TYPE direction,
                       double entry,
                       double stop)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
   {
      g_status = "INVALID ACCOUNT EQUITY";
      return 0.0;
   }

   double riskBudget = equity*InpRiskPercent/100.0;
   double combinedLimit = equity*InpMaxCombinedRiskPct/100.0;
   double openRisk = GetOpenRiskMoney();
   double remainingCombinedRisk = combinedLimit-openRisk;

   g_lastRiskBudget = riskBudget;

   if(remainingCombinedRisk <= 0.0)
   {
      g_status = "COMBINED RISK LIMIT";
      return 0.0;
   }

   double allowedRisk = MathMin(riskBudget,remainingCombinedRisk);

   double minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(minLot <= 0.0 || maxLot < minLot || lotStep <= 0.0)
   {
      g_status = "INVALID BROKER LOT SETTINGS";
      return 0.0;
   }

   double minimumRisk = 0.0;

   if(!CalculateRiskAtStop(direction,entry,stop,minLot,minimumRisk))
   {
      g_status = "CANNOT CALCULATE MINIMUM LOT RISK";
      return 0.0;
   }

   g_lastMinimumLotRisk = minimumRisk;

   if(minimumRisk > allowedRisk+0.01)
   {
      g_status = "MIN LOT EXCEEDS RISK LIMIT";

      Print("Golden Aim XAU Blitz EA: trade skipped on ",_Symbol,
            ". Minimum lot would exceed the risk budget.",
            " Currency=",g_currency,
            " Equity=",DoubleToString(equity,2),
            " Risk budget=",DoubleToString(allowedRisk,2),
            " Minimum lot=",DoubleToString(minLot,4),
            " Minimum lot risk=",DoubleToString(minimumRisk,2),
            " Open risk=",DoubleToString(openRisk,2),
            " Combined risk room=",DoubleToString(remainingCombinedRisk,2),
            " Entry=",DoubleToString(entry,_Digits),
            " Stop=",DoubleToString(stop,_Digits));

      return 0.0;
   }

   double oneLotRisk = 0.0;

   if(!CalculateRiskAtStop(direction,entry,stop,1.0,oneLotRisk))
   {
      g_status = "CANNOT CALCULATE LOT RISK";
      return 0.0;
   }

   if(oneLotRisk <= 0.0)
   {
      g_status = "INVALID STOP RISK";
      return 0.0;
   }

   double rawVolume = allowedRisk/oneLotRisk;
   double volume = NormalizeVolumeDown(rawVolume);

   if(volume < minLot)
   {
      g_status = "LOT BELOW BROKER MINIMUM";
      return 0.0;
   }

   double actualRisk = 0.0;

   if(!CalculateRiskAtStop(direction,entry,stop,volume,actualRisk))
   {
      g_status = "FINAL RISK CALCULATION FAILED";
      return 0.0;
   }

   // Always round down and reject volume exceeding either risk limit.
   while(volume >= minLot && actualRisk > allowedRisk+0.01)
   {
      volume = NormalizeVolumeDown(volume-lotStep);

      if(volume < minLot)
         break;

      if(!CalculateRiskAtStop(direction,entry,stop,volume,actualRisk))
         return 0.0;
   }

   if(volume < minLot)
   {
      g_status = "NO SAFE BROKER LOT";
      return 0.0;
   }

   double margin = 0.0;

   if(!OrderCalcMargin(direction,_Symbol,volume,entry,margin))
   {
      g_status = "MARGIN CALCULATION FAILED";
      return 0.0;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   if(margin > freeMargin)
   {
      g_status = "INSUFFICIENT FREE MARGIN";
      return 0.0;
   }

   return volume;
}

//====================================================================
// TRADING SESSIONS
// Sessions influence speed; they do not block all outside-session
// trading. Times use the broker server clock.
//====================================================================
bool HourInsideRange(int hour,int startHour,int endHour)
{
   if(startHour == endHour)
      return true;

   if(startHour < endHour)
      return (hour >= startHour && hour < endHour);

   return (hour >= startHour || hour < endHour);
}
//--------------------------------------------------------------------
bool IsRapidSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
      bool london =
      InpUseLondonSession &&
      HourInsideRange(dt.hour,InpLondonStartHour,InpLondonEndHour);

   bool newYork =
      InpUseNewYorkSession &&
      HourInsideRange(dt.hour,InpNewYorkStartHour,InpNewYorkEndHour);

   return (london || newYork);
}
//--------------------------------------------------------------------
bool IsSessionEnabled()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);

   bool london =
      InpUseLondonSession &&
      HourInsideRange(dt.hour,InpLondonStartHour,InpLondonEndHour);

   bool newYork =
      InpUseNewYorkSession &&
      HourInsideRange(dt.hour,InpNewYorkStartHour,InpNewYorkEndHour);

   bool asian =
      InpUseAsianSession &&
      HourInsideRange(dt.hour,InpAsianStartHour,InpAsianEndHour);

   return (london || newYork || asian);
}

//====================================================================
// MANUAL NEWS FILTER
// Enter server-time values separated by semicolons, for example:
// 2026.10.21 13:30;2026.10.22 15:00
//====================================================================
bool IsManualNewsBlocked()
{
   if(!InpUseManualNewsFilter || InpNewsTimes == "")
      return false;

   string entries[];
   ushort separator = StringGetCharacter(";",0);
   int count = StringSplit(InpNewsTimes,separator,entries);

   datetime now = TimeCurrent();

   for(int i=0; i<count; i++)
   {
      string item = entries[i];
      StringTrimLeft(item);
      StringTrimRight(item);

      if(item == "")
         continue;

      datetime newsTime = StringToTime(item);

      if(newsTime <= 0)
         continue;

      datetime fromTime = newsTime-InpNewsMinutesBefore*60;
      datetime toTime = newsTime+InpNewsMinutesAfter*60;

      if(now >= fromTime && now <= toTime)
         return true;
   }

   return false;
}

//====================================================================
// INDICATOR READING
//====================================================================
bool ReadBufferValue(int handle,int buffer,int shift,double &value)
{
   value = 0.0;

   if(handle == INVALID_HANDLE)
      return false;

   double values[];
   ArraySetAsSeries(values,true);

   if(CopyBuffer(handle,buffer,shift,1,values) != 1)
      return false;

   value = values[0];

   return (value != EMPTY_VALUE);
}
//--------------------------------------------------------------------
bool ReadIndicators(double &fast,
                    double &slow,
                    double &trend,
                    double &rsi,
                    double &adx,
                    double &plusDI,
                    double &minusDI,
                    double &atr,
                    double &close1,
                    double &close2,
                    double &closeM5)
{
   if(!ReadBufferValue(g_fastHandle,0,1,fast)) return false;
   if(!ReadBufferValue(g_slowHandle,0,1,slow)) return false;
   if(!ReadBufferValue(g_trendHandle,0,1,trend)) return false;
   if(!ReadBufferValue(g_rsiHandle,0,1,rsi)) return false;
   if(!ReadBufferValue(g_adxHandle,0,1,adx)) return false;
   if(!ReadBufferValue(g_adxHandle,1,1,plusDI)) return false;
   if(!ReadBufferValue(g_adxHandle,2,1,minusDI)) return false;
   if(!ReadBufferValue(g_atrHandle,0,1,atr)) return false;

   close1 = iClose(_Symbol,PERIOD_M1,1);
   close2 = iClose(_Symbol,PERIOD_M1,2);
   closeM5 = iClose(_Symbol,PERIOD_M5,1);

   if(close1 <= 0.0 || close2 <= 0.0 || closeM5 <= 0.0 || atr <= 0.0)
      return false;

   return true;
}

//====================================================================
// SMC / LIQUIDITY SWEEP CHECK
//====================================================================
int GetSMCSignal()
{
   int lookback = MathMax(3,InpSMCLookback);

   if(Bars(_Symbol,PERIOD_M1) < lookback+5)
      return 0;

   double priorHigh = -DBL_MAX;
   double priorLow = DBL_MAX;

   for(int i=2; i<lookback+2; i++)
   {
      double high = iHigh(_Symbol,PERIOD_M1,i);
      double low = iLow(_Symbol,PERIOD_M1,i);

      if(high > priorHigh) priorHigh = high;
      if(low < priorLow) priorLow = low;
   }

   double close1 = iClose(_Symbol,PERIOD_M1,1);
   double high1 = iHigh(_Symbol,PERIOD_M1,1);
   double low1 = iLow(_Symbol,PERIOD_M1,1);

   if(close1 <= 0.0 || high1 <= 0.0 || low1 <= 0.0)
         return 0;

   bool bullishBreak = (close1 > priorHigh);
   bool bearishBreak = (close1 < priorLow);

   bool bullishSweep =
      InpAllowLiquiditySweeps &&
      low1 < priorLow &&
      close1 > priorLow;

   bool bearishSweep =
      InpAllowLiquiditySweeps &&
      high1 > priorHigh &&
      close1 < priorHigh;

   if(bullishBreak || bullishSweep)
      return 1;

   if(bearishBreak || bearishSweep)
      return -1;

   return 0;
}

//====================================================================
// SMI-STYLE MOMENTUM CONFIRMATION
// This is a smoothed stochastic momentum calculation, not a separate
// broker-provided indicator.
//====================================================================
double EMAOnArrayValue(double &data[],int count,int period)
{
   if(count <= 0 || period <= 0)
      return 0.0;

   double alpha = 2.0/(period+1.0);
   double result = data[count-1];

   for(int i=count-2; i>=0; i--)
      result = alpha*data[i]+(1.0-alpha)*result;

   return result;
}
//--------------------------------------------------------------------
int GetSMIMomentumSignal()
{
   int lookback = MathMax(5,InpSMIKPeriod+InpSMISlowing+InpSMIDPeriod+5);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);

   int copied = CopyRates(_Symbol,PERIOD_M1,1,lookback,rates);

   if(copied < lookback)
      return 0;

   double momentum[];
   ArrayResize(momentum,copied);

   for(int i=0; i<copied; i++)
   {
      int endIndex = MathMin(copied-1,i+InpSMIKPeriod-1);

      double highest = -DBL_MAX;
      double lowest = DBL_MAX;

      for(int j=i; j<=endIndex; j++)
      {
         if(rates[j].high > highest) highest = rates[j].high;
         if(rates[j].low < lowest) lowest = rates[j].low;
      }

      double midpoint = (highest+lowest)/2.0;
      double range = highest-lowest;

      if(range <= 0.0)
         momentum[i] = 0.0;
      else
         momentum[i] = 100.0*(rates[i].close-midpoint)/(range/2.0);
   }

   // CopyRates with series=true returns newest at index 0.
   // Use recent momentum and a simple smoothing comparison.
   double recent = momentum[0];
   double previous = momentum[1];

   if(recent > previous && recent > 0.0)
      return 1;

   if(recent < previous && recent < 0.0)
      return -1;

   return 0;
}

//====================================================================
// SMT DIVERGENCE
// Returns 1 bullish, -1 bearish, 0 unavailable/neutral.
//====================================================================
int GetSMTSignal()
{
   if(!InpUseSMTConfirmation)
      return 0;

   if(g_oppositeSymbol == "")
      return 0;

   int lookback = MathMax(3,InpSMTLookback);

   if(Bars(_Symbol,PERIOD_M1) < lookback+3 ||
      Bars(g_oppositeSymbol,PERIOD_M1) < lookback+3)
      return 0;

   double chartHigh = iHigh(_Symbol,PERIOD_M1,1);
   double chartLow = iLow(_Symbol,PERIOD_M1,1);
   double otherHigh = iHigh(g_oppositeSymbol,PERIOD_M1,1);
   double otherLow = iLow(g_oppositeSymbol,PERIOD_M1,1);

   double priorChartHigh = -DBL_MAX;
   double priorChartLow = DBL_MAX;
   double priorOtherHigh = -DBL_MAX;
   double priorOtherLow = DBL_MAX;

   for(int i=2; i<lookback+2; i++)
   {
      priorChartHigh = MathMax(priorChartHigh,iHigh(_Symbol,PERIOD_M1,i));
      priorChartLow = MathMin(priorChartLow,iLow(_Symbol,PERIOD_M1,i));

      priorOtherHigh =
         MathMax(priorOtherHigh,iHigh(g_oppositeSymbol,PERIOD_M1,i));

      priorOtherLow =
         MathMin(priorOtherLow,iLow(g_oppositeSymbol,PERIOD_M1,i));
   }

   bool chartLowerSweep = (chartLow < priorChartLow);
   bool otherLowerSweep = (otherLow < priorOtherLow);

   bool chartHigherSweep = (chartHigh > priorChartHigh);
   bool otherHigherSweep = (otherHigh > priorOtherHigh);

   if(chartLowerSweep && !otherLowerSweep)
      return 1;

   if(chartHigherSweep && !otherHigherSweep)
      return -1;

   return 0;
}

//====================================================================
// SIGNAL GENERATION
//====================================================================
int GetSignal()
{
   double fast,slow,trend,rsi,adx,plusDI,minusDI,atr;
   double close1,close2,closeM5;

   if(!ReadIndicators(fast,slow,trend,rsi,adx,plusDI,minusDI,
                      atr,close1,close2,closeM5))
   {
      g_status = "WAITING FOR INDICATOR DATA";
      return 0;
   }

   // Keep ADX as a trend-strength safeguard.
   if(adx < InpMinimumADX)
   {
      g_status = "ADX BELOW MINIMUM";
      return 0;
   }

   // Core trend direction.
   bool bullishTrend = (fast > slow && close1 > trend);
   bool bearishTrend = (fast < slow && close1 < trend);

   // Allow either directional DI confirmation OR candle momentum.
   bool bullishMomentum = (plusDI > minusDI || close1 >= close2);
   bool bearishMomentum = (minusDI > plusDI || close1 <= close2);

   // Keep RSI ranges, but don't require every indicator to agree.
   bool bullishRSI =
      (rsi >= InpBuyRSIMin && rsi <= InpBuyRSIMax);

   bool bearishRSI =
      (rsi >= InpSellRSIMin && rsi <= InpSellRSIMax);

   // M5 trend acts as a filter, not an additional close-price test.
   bool bullish =
      bullishTrend &&
      closeM5 > trend &&
      bullishMomentum &&
      bullishRSI;

   bool bearish =
      bearishTrend &&
      closeM5 < trend &&
      bearishMomentum &&
      bearishRSI;

   if(!bullish && !bearish)
   {
      g_status = "WAITING FOR TREND / RSI";
      return 0;
   }

   int direction = bullish ? 1 : -1;

   // Optional SMC confirmation remains controlled by its input.
   if(InpRequireSMCConfirmation)
   {
      int smc = GetSMCSignal();

      if(smc != direction)
      {
         g_status = "WAITING FOR SMC";
         return 0;
      }
   }

   // Optional momentum confirmation remains controlled by its input.
   if(InpUseSMIConfirmation)
   {
      int smi = GetSMIMomentumSignal();

      if(smi != direction)
      {
         g_status = "WAITING FOR MOMENTUM";
         return 0;
      }
   }

   // SMT is supporting information only; it cannot veto the signal.
   if(InpUseSMTConfirmation)
   {
      int smt = GetSMTSignal();

      if(smt == direction)
      {
         Print("Golden Aim XAU Blitz EA: SMT supports ",
               direction > 0 ? "BUY" : "SELL",
               " on ",_Symbol);
      }
   }

   g_status = (direction > 0) ? "BUY SIGNAL" : "SELL SIGNAL";

   return direction;
}
//====================================================================
// STOP LOSS / TAKE PROFIT
//====================================================================
bool BuildStops(int direction,double &entry,double &stop,double &target)
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double atr = 0.0;

   if(!ReadBufferValue(g_atrHandle,0,1,atr) || atr <= 0.0)
      return false;

   entry = (direction > 0) ? tick.ask : tick.bid;

   if(entry <= 0.0)
      return false;

   long stopsLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);

   double minimumDistance = (double)stopsLevel*_Point;
   double spreadDistance = tick.ask-tick.bid;

   // Keep the stop beyond the broker's minimum distance and spread.
   minimumDistance = MathMax(minimumDistance,spreadDistance*1.5);
   minimumDistance = MathMax(minimumDistance,_Point*2.0);

   double atrDistance = atr*InpStopATRMultiplier;
   double stopDistance = MathMax(atrDistance,minimumDistance+_Point);

Print("GAXB STOP DIAGNOSTIC | Symbol=",_Symbol,
      " | ATR=",DoubleToString(atr,_Digits),
      " | ATR distance=",DoubleToString(atrDistance,_Digits),
      " | Minimum distance=",DoubleToString(minimumDistance,_Digits),
      " | Final stop distance=",DoubleToString(stopDistance,_Digits),
      " | Tick size=",DoubleToString(
         SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),8),
      " | Tick value loss=",DoubleToString(
         SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS),8),
      " | Contract size=",DoubleToString(
         SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),2));


   if(direction > 0)
   {
      stop = entry-stopDistance;
      target = entry+stopDistance*InpRewardRiskRatio;
   }
   else
   {
         stop = entry+stopDistance;
      target = entry-stopDistance*InpRewardRiskRatio;
   }

   stop = NormalizePriceToTick(stop);
   target = NormalizePriceToTick(target);

   // Validate distances against current market prices after rounding.
   if(direction > 0)
   {
      if(stop >= tick.bid || target <= tick.ask)
         return false;

      if((tick.bid-stop) < minimumDistance ||
         (target-tick.ask) < minimumDistance)
      {
         g_status = "BROKER STOP DISTANCE";
         return false;
      }
   }
   else
   {
      if(stop <= tick.ask || target >= tick.bid)
         return false;

      if((stop-tick.ask) < minimumDistance ||
         (tick.bid-target) < minimumDistance)
      {
         g_status = "BROKER STOP DISTANCE";
         return false;
      }
   }

   return true;
}

//====================================================================
// ENTRY RATE CONTROL
//====================================================================
void UpdateEntryWindow()
{
   datetime now = TimeCurrent();

   if(g_entryWindowStart == 0 || now-g_entryWindowStart >= 60)
   {
      g_entryWindowStart = now;
      g_entriesInWindow = 0;
   }
}
//--------------------------------------------------------------------
bool EntryRateAllowed()
{
   UpdateEntryWindow();

   g_rapidMode = IsRapidSession();

   int maxEntries = g_rapidMode
                    ? InpRapidMaxEntriesPerMinute
                    : InpNormalMaxEntriesPerMinute;

   int cooldown = g_rapidMode
                  ? InpRapidCooldownSeconds
                  : InpNormalCooldownSeconds;

   if(maxEntries < 1)
      maxEntries = 1;

   if(cooldown < 0)
      cooldown = 0;

   if(g_entriesInWindow >= maxEntries)
   {
      g_status = "ENTRY RATE LIMIT";
      return false;
   }

   if(g_lastEntryTime > 0 && TimeCurrent()-g_lastEntryTime < cooldown)
   {
      g_status = "ENTRY COOLDOWN";
      return false;
   }

   return true;
}

//====================================================================
// ENTRY PERMISSION CHECKS
//====================================================================
bool EntryAllowed()
{
   if(!g_tradingEnabled)
   {
      g_status = "CLICK CONTINUE TO START";
      return false;
   }

   if(!InpMassExecution)
   {
      g_status = "MASS EXECUTION OFF";
      return false;
   }

   if(g_stopForToday)
   {
      g_status = "STOPPED FOR TODAY";
      return false;
   }

   if(g_dailyLossLocked)
   {
      g_status = "DAILY LOSS LOCK";
      return false;
   }

   if(!IsAccountAllowed())
   {
      g_status = IsDemoAccount() ? "DEMO TRADING DISABLED"
                                 : "LIVE TRADING DISABLED";
      return false;
   }

   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      g_status = "TERMINAL DISCONNECTED";
      return false;
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      g_status = "ENABLE ALGO TRADING";
      return false;
   }

   if(!CheckLossLimits())
      return false;

   if(IsManualNewsBlocked())
   {
      g_status = "MANUAL NEWS FILTER";
      return false;
   }

   double dailyNet = GetDailyNet();

   if(InpDailyProfitTarget > 0.0 &&
      dailyNet >= InpDailyProfitTarget &&
      !g_dailyTargetOverride)
   {
         g_tradingEnabled = false;
      g_status = "DAILY TARGET REACHED";
      return false;
   }

   g_lastSpread = CurrentSpreadPoints();

   if(g_lastSpread > InpMaxSpreadPoints)
   {
      g_status = "SPREAD TOO HIGH";
      return false;
   }

   if(CountMyPositions() >= InpMaxPositions)
   {
      g_status = "MAX POSITIONS REACHED";
      return false;
   }

   if(!EntryRateAllowed())
      return false;

   return true;
}

//====================================================================
// OPEN TRADE
//====================================================================
void TryOpenTrade()
{
   if(!EntryAllowed())
      return;

   int direction = GetSignal();

   if(direction == 0)
      return;

   double entry=0.0,stop=0.0,target=0.0;

   if(!BuildStops(direction,entry,stop,target))
   {
      if(g_status == "BUY SIGNAL" || g_status == "SELL SIGNAL")
         g_status = "STOP BUILD FAILED";

      return;
   }

   ENUM_ORDER_TYPE orderType =
      (direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double volume = CalculateVolume(orderType,entry,stop);

   if(volume <= 0.0)
      return;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   bool sent = false;

   ResetLastError();

   if(direction > 0)
   {
      sent = trade.Buy(volume,_Symbol,0.0,stop,target,
                       "Golden Aim XAU Blitz EA");
   }
   else
   {
      sent = trade.Sell(volume,_Symbol,0.0,stop,target,
                        "Golden Aim XAU Blitz EA");
   }

   uint retcode = trade.ResultRetcode();

   if(sent &&
      (retcode == TRADE_RETCODE_DONE ||
       retcode == TRADE_RETCODE_DONE_PARTIAL ||
       retcode == TRADE_RETCODE_PLACED))
   {
      g_lastEntryTime = TimeCurrent();
      g_entriesInWindow++;

      g_status = (direction > 0) ? "BUY ORDER ACCEPTED"
                                 : "SELL ORDER ACCEPTED";

      Print("Golden Aim XAU Blitz EA: order accepted.",
            " Symbol=",_Symbol,
            " Direction=",(direction > 0 ? "BUY" : "SELL"),
            " Volume=",DoubleToString(volume,VolumeDigitsFromStep(
                         SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))),
            " Entry=",DoubleToString(trade.ResultPrice(),_Digits),
            " SL=",DoubleToString(stop,_Digits),
            " TP=",DoubleToString(target,_Digits),
            " Currency=",g_currency,
            " Retcode=",retcode);
   }
   else
   {
      g_status = "ORDER REJECTED";

      Print("Golden Aim XAU Blitz EA: order rejected.",
            " Symbol=",_Symbol,
            " Volume=",DoubleToString(volume,4),
            " Retcode=",retcode,
            " Description=",trade.ResultRetcodeDescription(),
            " LastError=",GetLastError());
   }
}

//====================================================================
// POSITION MANAGEMENT - BREAK EVEN
//====================================================================
void ManagePositions()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      if(currentSL <= 0.0 || openPrice <= 0.0)
         continue;

      double initialRisk = MathAbs(openPrice-currentSL);
      
      if(initialRisk <= 0.0)
         continue;

      double favorableMove = 0.0;

      if(type == POSITION_TYPE_BUY)
         favorableMove = tick.bid-openPrice;
      else
         favorableMove = openPrice-tick.ask;

      if(favorableMove < initialRisk*InpBreakEvenAtR)
         continue;

      double newSL = NormalizePriceToTick(openPrice);

      // Never move the stop backwards.
      if(type == POSITION_TYPE_BUY && currentSL >= newSL)
         continue;

      if(type == POSITION_TYPE_SELL && currentSL <= newSL)
         continue;

      long stopsLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
      long freezeLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

      double requiredDistance =
         MathMax((double)stopsLevel,(double)freezeLevel)*_Point;

      if(type == POSITION_TYPE_BUY &&
         tick.bid-newSL < requiredDistance)
         continue;

      if(type == POSITION_TYPE_SELL &&
         newSL-tick.ask < requiredDistance)
         continue;

      ResetLastError();

      bool modified = trade.PositionModify(ticket,newSL,currentTP);

      if(!modified || trade.ResultRetcode() != TRADE_RETCODE_DONE)
      {
         Print("Golden Aim XAU Blitz EA: break-even modification failed.",
               " Ticket=",ticket,
               " Retcode=",trade.ResultRetcode(),
               " Description=",trade.ResultRetcodeDescription(),
               " Error=",GetLastError());
      }
      else
      {
         Print("Golden Aim XAU Blitz EA: break-even stop applied.",
               " Ticket=",ticket,
               " NewSL=",DoubleToString(newSL,_Digits));
      }
   }
}

//====================================================================
// DASHBOARD OBJECT HELPERS
//====================================================================
void DeleteDashboard()
{
   ObjectsDeleteAll(0,OBJ_PREFIX);
}
//--------------------------------------------------------------------
bool CreateLabel(string name,string text,int x,int y,int fontSize,
                 color textColor,string font="Arial")
{
   string objectName = OBJ_PREFIX+name;

   if(ObjectFind(0,objectName) < 0)
   {
      if(!ObjectCreate(0,objectName,OBJ_LABEL,0,0,0))
         return false;
   }

   ObjectSetInteger(0,objectName,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,objectName,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,objectName,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,objectName,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,objectName,OBJPROP_COLOR,textColor);
   ObjectSetString(0,objectName,OBJPROP_FONT,font);
   ObjectSetString(0,objectName,OBJPROP_TEXT,text);
   ObjectSetInteger(0,objectName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,objectName,OBJPROP_HIDDEN,true);

   return true;
}
//--------------------------------------------------------------------
bool CreateButton(string name,string text,int x,int y,int width,int height,
                  color textColor,color backgroundColor)
{
   string objectName = OBJ_PREFIX+name;

   if(ObjectFind(0,objectName) < 0)
   {
      if(!ObjectCreate(0,objectName,OBJ_BUTTON,0,0,0))
         return false;
   }

   ObjectSetInteger(0,objectName,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,objectName,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,objectName,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,objectName,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,objectName,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,objectName,OBJPROP_COLOR,textColor);
   ObjectSetInteger(0,objectName,OBJPROP_BGCOLOR,backgroundColor);
   ObjectSetInteger(0,objectName,OBJPROP_BORDER_COLOR,clrGoldenrod);
   ObjectSetInteger(0,objectName,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,objectName,OBJPROP_FONT,"Arial Bold");
   ObjectSetString(0,objectName,OBJPROP_TEXT,text);
   ObjectSetInteger(0,objectName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,objectName,OBJPROP_HIDDEN,true);

   return true;
}
//--------------------------------------------------------------------
bool CreatePanel()
{
   string name = OBJ_PREFIX+"BG";

   if(ObjectFind(0,name) < 0)
   {
      if(!ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0))
         return false;
   }

   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,370);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,260);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrGoldenrod);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);

   return true;
}
//--------------------------------------------------------------------
void BuildDashboard()
{
   CreatePanel();

   CreateLabel("TITLE","GOLDEN AIM XAU BLITZ EA",
               22,28,13,clrGold,"Arial Bold");
               
   CreateLabel("SUBTITLE","SWEET BUT DEADLY",
               22,49,10,clrWhite,"Arial Bold");

   CreateLabel("COMPANY","Kin Legacy Holdings Limited",
               22,68,9,clrSilver);

   CreateLabel("SLOGAN","Building a Dynasty, Leaving a Legacy",
               22,84,8,clrGoldenrod);

   CreateLabel("EXEC","MASS EXECUTION",
               22,109,10,clrWhite,"Arial Bold");

   CreateLabel("STATUS","Status: INITIALIZING",
               22,132,9,clrLime);

   CreateLabel("SYMBOL","Symbol: "+_Symbol,
               22,152,9,clrWhite);

   CreateLabel("SPREAD","Spread: --",
               22,172,9,clrWhite);

   CreateLabel("EQUITY","Equity: --",
               22,192,9,clrWhite);

   CreateLabel("DAILY","Today's Net: --",
               22,212,9,clrWhite);

   CreateButton("CONTINUE","CONTINUE",22,238,150,28,
                clrBlack,clrGold);

   CreateButton("STOP","STOP FOR TODAY",190,238,170,28,
                clrWhite,clrFireBrick);

   ChartRedraw(0);
}
//--------------------------------------------------------------------
void UpdateDashboard()
{
   if(ObjectFind(0,OBJ_PREFIX+"BG") < 0)
      BuildDashboard();

   string modeText = g_rapidMode ? "RAPID" : "NORMAL";
   string execText = "MASS EXECUTION: " +
                     string(InpMassExecution ? "ON" : "OFF") +
                     " | " + modeText;

   color statusColor = clrWhite;

   if(g_tradingEnabled && !g_stopForToday && !g_dailyLossLocked)
      statusColor = clrLime;

   if(g_dailyLossLocked || g_stopForToday)
      statusColor = clrTomato;

   if(StringFind(g_status,"EXCEEDS RISK") >= 0 ||
      StringFind(g_status,"RISK LIMIT") >= 0)
      statusColor = clrOrange;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyNet = GetDailyNet();
   double spread = CurrentSpreadPoints();

   string equityText =
      "Equity: "+DoubleToString(equity,2)+" "+g_currency;

   string dailyText =
      "Today's Net: "+DoubleToString(dailyNet,2)+" "+g_currency+
      " / "+DoubleToString(InpDailyProfitTarget,2);

   string spreadText =
      "Spread: "+DoubleToString(spread,1)+
      " points / "+IntegerToString(InpMaxSpreadPoints);

   ObjectSetString(0,OBJ_PREFIX+"EXEC",OBJPROP_TEXT,execText);
   ObjectSetInteger(0,OBJ_PREFIX+"EXEC",OBJPROP_COLOR,
                    InpMassExecution ? clrLime : clrTomato);

   ObjectSetString(0,OBJ_PREFIX+"STATUS",OBJPROP_TEXT,
                   "Status: "+g_status);
   ObjectSetInteger(0,OBJ_PREFIX+"STATUS",OBJPROP_COLOR,statusColor);

   ObjectSetString(0,OBJ_PREFIX+"SYMBOL",OBJPROP_TEXT,
                   "Symbol: "+_Symbol+" | "+
                   EnumToString((ENUM_TIMEFRAMES)_Period));

   ObjectSetString(0,OBJ_PREFIX+"SPREAD",OBJPROP_TEXT,spreadText);
   ObjectSetString(0,OBJ_PREFIX+"EQUITY",OBJPROP_TEXT,equityText);
   ObjectSetString(0,OBJ_PREFIX+"DAILY",OBJPROP_TEXT,dailyText);

   ChartRedraw(0);
}

//====================================================================
// INITIALIZATION
//====================================================================
int OnInit()
{
   if(!IsAllowedChartMetal())
   {
      Print("Golden Aim XAU Blitz EA: attach to a gold or silver symbol.");
      return INIT_FAILED;
   }

   if(!IsValidTimeframe())
   {
      Print("Golden Aim XAU Blitz EA: only M1 and M5 charts are supported.");
      return INIT_FAILED;
   }

   if(InpRiskPercent <= 0.0 ||
      InpMaxCombinedRiskPct <= 0.0 ||
      InpStopATRMultiplier <= 0.0 ||
      InpRewardRiskRatio <= 0.0 ||
      InpMaxPositions < 1 ||
      InpMaxSpreadPoints < 1)
   {
      Print("Golden Aim XAU Blitz EA: invalid input settings.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!ReadBrokerSpecifications())
   {
      Print("Golden Aim XAU Blitz EA: broker specification check failed.");
      return INIT_FAILED;
   }

   g_fastHandle = iMA(_Symbol,PERIOD_M1,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_slowHandle = iMA(_Symbol,PERIOD_M1,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_trendHandle = iMA(_Symbol,PERIOD_M5,InpTrendEMA,0,MODE_EMA,PRICE_CLOSE);
   g_rsiHandle = iRSI(_Symbol,PERIOD_M1,InpRSIPeriod,PRICE_CLOSE);
   g_adxHandle = iADX(_Symbol,PERIOD_M1,InpADXPeriod);
   g_atrHandle = iATR(_Symbol,PERIOD_M1,InpATRPeriod);

   if(g_fastHandle == INVALID_HANDLE ||
      g_slowHandle == INVALID_HANDLE ||
      g_trendHandle == INVALID_HANDLE ||
      g_rsiHandle == INVALID_HANDLE ||
      g_adxHandle == INVALID_HANDLE ||
      g_atrHandle == INVALID_HANDLE)
   {
      Print("Golden Aim XAU Blitz EA: failed to initialize indicators.");
      return INIT_FAILED;
   }

   LoadDailyState();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   g_tradingEnabled = false;
   g_status = g_stopForToday ? "STOPPED FOR TODAY"
                             : "READY - CLICK CONTINUE";

   BuildDashboard();
   UpdateDashboard();

   EventSetTimer(1);

   Print("==================================================");
   Print("Golden Aim XAU Blitz EA initialized.");
   Print("Company: Kin Legacy Holdings Limited");
   Print("Slogan: Building a Dynasty, Leaving a Legacy");
   Print("Symbol: ",_Symbol);
   Print("Broker: ",AccountInfoString(ACCOUNT_COMPANY));
   Print("Server: ",AccountInfoString(ACCOUNT_SERVER));
   Print("Account currency: ",g_currency);
   Print("Timeframe: ",EnumToString((ENUM_TIMEFRAMES)_Period));
   Print("Trading remains disabled until CONTINUE is clicked.");
   Print("No PIN gate. No weekly loss limit.");
   Print("Trade comment: Golden Aim XAU Blitz EA");
   Print("==================================================");

   return INIT_SUCCEEDED;
}

//====================================================================
// SHUTDOWN
//====================================================================
void OnDeinit(const int reason)
{
   EventKillTimer();

   if(g_fastHandle != INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle != INVALID_HANDLE) IndicatorRelease(g_slowHandle);
   if(g_trendHandle != INVALID_HANDLE) IndicatorRelease(g_trendHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);

   DeleteDashboard();
   ChartRedraw(0);
}

//====================================================================
// MAIN TICK
//====================================================================
void OnTick()
{
   UpdateRiskPeriods();

   g_rapidMode = IsRapidSession();
   ManagePositions();

   if(!IsValidTimeframe())
   {
      g_status = "USE M1 OR M5";
      UpdateDashboard();
      return;
   }

   TryOpenTrade();
   UpdateDashboard();
}

//====================================================================
// TIMER
//====================================================================
void OnTimer()
{
   UpdateRiskPeriods();

   g_rapidMode = IsRapidSession();

   if(!CheckLossLimits() && g_tradingEnabled)
      g_tradingEnabled = false;

   UpdateDashboard();
}

//====================================================================
// DASHBOARD BUTTONS
//====================================================================
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == OBJ_PREFIX+"CONTINUE")
   {
      ObjectSetInteger(0,OBJ_PREFIX+"CONTINUE",OBJPROP_STATE,false);

      UpdateRiskPeriods();

      if(g_stopForToday)
      {
         g_status = "STOPPED FOR TODAY";
         g_tradingEnabled = false;
      }
      else if(g_dailyLossLocked)
      {
         g_status = "DAILY LOSS LOCK - WAIT FOR NEW DAY";
         g_tradingEnabled = false;
      }
      else if(!IsAccountAllowed())
      {
         g_status = IsDemoAccount() ? "DEMO TRADING DISABLED"
                                    : "LIVE TRADING DISABLED";
         g_tradingEnabled = false;
      }
      else if(!CheckLossLimits())
      {
         g_tradingEnabled = false;
      }
      else
      {
         g_tradingEnabled = true;

         // The user may manually resume after the daily profit target.
         g_dailyTargetOverride = true;

         g_status = "TRADING ENABLED";
         Print("Golden Aim XAU Blitz EA: CONTINUE clicked.");
      }

      UpdateDashboard();
      ChartRedraw(0);
      return;
   }

   if(sparam == OBJ_PREFIX+"STOP")
   {
      ObjectSetInteger(0,OBJ_PREFIX+"STOP",OBJPROP_STATE,false);

      g_stopForToday = true;
      g_tradingEnabled = false;
      g_status = "STOPPED FOR TODAY";

      SaveDailyState();

      Print("Golden Aim XAU Blitz EA: STOP FOR TODAY clicked. ",
            "New entries disabled until the next server day.");

      UpdateDashboard();
      ChartRedraw(0);
      return;
   }
}
//+------------------------------------------------------------------+
