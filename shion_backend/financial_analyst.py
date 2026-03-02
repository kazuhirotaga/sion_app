"""
Financial AI Analyst Module for Shion
Periodically fetches financial news, analyzes with Gemini, 
saves results, and runs PDCA cycle for continuous improvement.
"""
import os
import json
import asyncio
from datetime import datetime, timedelta
from pathlib import Path
from google import genai
from google.genai import types
from duckduckgo_search import DDGS
from dotenv import load_dotenv

load_dotenv()

# Directories for storing analysis data
DATA_DIR = Path(__file__).parent / "data"
ANALYSES_DIR = DATA_DIR / "analyses"
LEARNING_NOTES_PATH = DATA_DIR / "learning_notes.json"

# Ensure directories exist
ANALYSES_DIR.mkdir(parents=True, exist_ok=True)

# Gemini client
genai_client = genai.Client()

ANALYSIS_PROMPT = """
あなたは金融市場の専門アナリストです。以下のニュースを分析し、JSON形式で結果を出力してください。

【ニュース一覧】
{news_text}

【過去の学習メモ（予測精度向上のための振り返り）】
{learning_context}

以下のJSONフォーマットで出力してください（バッククォートは不要）：
{{
  "speech_summary": "ユーザーに読み上げる1〜3文の簡潔な市場サマリー（日本語・敬語）",
  "market_sentiment": "bullish / bearish / neutral",
  "key_sectors": ["注目セクター1", "セクター2"],
  "predictions": [
    {{"target": "日経平均", "direction": "上昇/下落/横ばい", "confidence": 0.7, "reasoning": "理由"}},
    {{"target": "USD/JPY", "direction": "円安/円高/横ばい", "confidence": 0.6, "reasoning": "理由"}},
    {{"target": "S&P500", "direction": "上昇/下落/横ばい", "confidence": 0.5, "reasoning": "理由"}}
  ],
  "risk_factors": ["リスク1", "リスク2"],
  "action_advice": "短期的な投資アドバイス1文"
}}
"""

PDCA_PROMPT = """
あなたは金融アナリストの自己評価AIです。
過去の予測と、その後の実際のニュース動向を比較し、学習メモを生成してください。

【過去の予測（{past_time}時点）】
{past_predictions}

【その後のニュース動向】
{recent_news}

以下のJSON形式で学習メモを出力してください（バッククォートは不要）：
{{
  "evaluation_date": "{eval_date}",
  "accuracy_notes": "予測の当たり外れについての分析（1〜2文）",
  "lessons_learned": ["学んだこと1", "学んだこと2"],
  "bias_warnings": ["注意すべきバイアスや傾向"]
}}
"""


def fetch_financial_news() -> list[dict]:
    """Fetch financial news from DuckDuckGo."""
    queries = [
        "株式市場 日経平均 最新",
        "米国株 S&P500 ニュース",
        "為替 ドル円 最新",
        "金融政策 日銀 FRB",
    ]
    
    all_results = []
    for query in queries:
        try:
            with DDGS() as ddgs:
                results = list(ddgs.news(query, max_results=3))
                all_results.extend(results)
        except Exception as e:
            print(f"FinancialAnalyst: Error fetching news for '{query}': {e}")
    
    print(f"FinancialAnalyst: Fetched {len(all_results)} news items total")
    return all_results


def get_learning_context() -> str:
    """Load learning notes for PDCA context."""
    if not LEARNING_NOTES_PATH.exists():
        return "まだ学習メモはありません。初回分析です。"
    
    try:
        with open(LEARNING_NOTES_PATH, "r", encoding="utf-8") as f:
            notes = json.load(f)
        
        # Use last 5 notes for context
        recent_notes = notes[-5:] if len(notes) > 5 else notes
        context_parts = []
        for note in recent_notes:
            context_parts.append(
                f"- [{note.get('evaluation_date', '不明')}] "
                f"{note.get('accuracy_notes', '')}"
            )
            for lesson in note.get("lessons_learned", []):
                context_parts.append(f"  → {lesson}")
        
        return "\n".join(context_parts) if context_parts else "学習メモは空です。"
    except Exception as e:
        print(f"FinancialAnalyst: Error reading learning notes: {e}")
        return "学習メモの読み込みに失敗しました。"


async def analyze_news(news_items: list[dict]) -> dict:
    """Analyze news using Gemini and return structured analysis."""
    # Format news for prompt
    news_text = ""
    for i, item in enumerate(news_items, 1):
        title = item.get("title", "タイトルなし")
        body = item.get("body", item.get("description", ""))
        source = item.get("source", "不明")
        news_text += f"{i}. [{source}] {title}\n   {body}\n\n"
    
    if not news_text.strip():
        news_text = "ニュースの取得に失敗しました。一般的な市場分析を行ってください。"
    
    learning_context = get_learning_context()
    
    prompt = ANALYSIS_PROMPT.format(
        news_text=news_text,
        learning_context=learning_context
    )
    
    try:
        response = await genai_client.aio.models.generate_content(
            model="gemini-3.0-flash",
            contents=prompt,
        )
        
        result_text = response.text.strip()
        # Clean up markdown code block if present
        if result_text.startswith("```"):
            result_text = result_text.split("\n", 1)[1]
            result_text = result_text.rsplit("```", 1)[0].strip()
        
        analysis = json.loads(result_text)
        analysis["timestamp"] = datetime.now().isoformat()
        analysis["news_count"] = len(news_items)
        
        return analysis
    except Exception as e:
        print(f"FinancialAnalyst: Error analyzing news: {e}")
        return {
            "timestamp": datetime.now().isoformat(),
            "speech_summary": "ニュース分析でエラーが発生しました。次のサイクルで再試行します。",
            "market_sentiment": "neutral",
            "predictions": [],
            "risk_factors": ["分析エラー"],
            "error": str(e)
        }


def save_analysis(analysis: dict) -> str:
    """Save analysis result to a JSON file. Returns the filename."""
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M")
    filename = f"{timestamp}.json"
    filepath = ANALYSES_DIR / filename
    
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(analysis, f, ensure_ascii=False, indent=2)
    
    print(f"FinancialAnalyst: Saved analysis to {filepath}")
    return filename


def get_latest_analysis() -> dict | None:
    """Get the most recent analysis result."""
    files = sorted(ANALYSES_DIR.glob("*.json"), reverse=True)
    if not files:
        return None
    
    try:
        with open(files[0], "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"FinancialAnalyst: Error reading latest analysis: {e}")
        return None


def get_analysis_history(n: int = 10) -> list[dict]:
    """Get the last N analysis results."""
    files = sorted(ANALYSES_DIR.glob("*.json"), reverse=True)[:n]
    results = []
    
    for f in files:
        try:
            with open(f, "r", encoding="utf-8") as fh:
                results.append(json.load(fh))
        except Exception:
            pass
    
    return results


async def run_pdca_check():
    """Compare past predictions with recent news to learn and improve."""
    history = get_analysis_history(5)
    if len(history) < 2:
        print("FinancialAnalyst: Not enough history for PDCA check yet")
        return
    
    # Get the oldest analysis in our window as "past prediction"
    past_analysis = history[-1]
    past_predictions = json.dumps(
        past_analysis.get("predictions", []), ensure_ascii=False, indent=2
    )
    past_time = past_analysis.get("timestamp", "不明")
    
    # Fetch recent news to compare
    recent_news_items = fetch_financial_news()
    recent_news = "\n".join(
        f"- {item.get('title', '')}" for item in recent_news_items[:10]
    )
    
    eval_date = datetime.now().strftime("%Y-%m-%d %H:%M")
    
    prompt = PDCA_PROMPT.format(
        past_time=past_time,
        past_predictions=past_predictions,
        recent_news=recent_news,
        eval_date=eval_date
    )
    
    try:
        response = await genai_client.aio.models.generate_content(
            model="gemini-3.0-flash",
            contents=prompt,
        )
        
        result_text = response.text.strip()
        if result_text.startswith("```"):
            result_text = result_text.split("\n", 1)[1]
            result_text = result_text.rsplit("```", 1)[0].strip()
        
        pdca_note = json.loads(result_text)
        
        # Append to learning notes
        notes = []
        if LEARNING_NOTES_PATH.exists():
            with open(LEARNING_NOTES_PATH, "r", encoding="utf-8") as f:
                notes = json.load(f)
        
        notes.append(pdca_note)
        
        # Keep only last 20 notes
        if len(notes) > 20:
            notes = notes[-20:]
        
        with open(LEARNING_NOTES_PATH, "w", encoding="utf-8") as f:
            json.dump(notes, f, ensure_ascii=False, indent=2)
        
        print(f"FinancialAnalyst: PDCA check complete. Learning note added.")
    except Exception as e:
        print(f"FinancialAnalyst: PDCA check error: {e}")


async def run_analysis_cycle():
    """Main analysis cycle: fetch news -> analyze -> save -> PDCA check."""
    print(f"FinancialAnalyst: === Starting analysis cycle at {datetime.now().isoformat()} ===")
    
    # 1. PDCA Check (compare past predictions with reality)
    await run_pdca_check()
    
    # 2. Fetch fresh news
    news_items = fetch_financial_news()
    
    # 3. Analyze with Gemini
    analysis = await analyze_news(news_items)
    
    # 4. Save results
    save_analysis(analysis)
    
    print(f"FinancialAnalyst: === Cycle complete. Sentiment: {analysis.get('market_sentiment', 'unknown')} ===")
    return analysis
