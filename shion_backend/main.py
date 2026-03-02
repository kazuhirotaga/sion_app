import os
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from ai_agent import process_chat
from financial_analyst import run_analysis_cycle, get_latest_analysis, get_analysis_history

# APScheduler instance
scheduler = AsyncIOScheduler()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: run first analysis + start scheduler. Shutdown: stop scheduler."""
    print("FinancialAnalyst: Running initial analysis on startup...")
    try:
        await run_analysis_cycle()
    except Exception as e:
        print(f"FinancialAnalyst: Initial analysis failed: {e}")
    
    # Schedule every 10 minutes
    scheduler.add_job(
        run_analysis_cycle,
        trigger=IntervalTrigger(minutes=10),
        id="financial_analysis",
        replace_existing=True,
        misfire_grace_time=300,
        coalesce=True,
    )
    scheduler.start()
    print("FinancialAnalyst: Scheduler started (every 10 minutes)")
    
    yield
    
    scheduler.shutdown()
    print("FinancialAnalyst: Scheduler stopped")

app = FastAPI(title="Shion API Gateway", lifespan=lifespan)

# Allow CORS for Flutter client
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    message: str
    history: list = []
    image_base64: str | None = None

@app.get("/")
def read_root():
    return {"status": "ok", "message": "Shion AI Gateway is running."}

@app.post("/chat")
async def chat_endpoint(request: ChatRequest):
    # Run in a separate thread to avoid blocking the event loop (and APScheduler)
    reply_data = await asyncio.to_thread(
        lambda: asyncio.run(process_chat(request.message, request.history, request.image_base64))
    )
    
    reply_text = reply_data.get("text", "") if isinstance(reply_data, dict) else str(reply_data)
    
    new_history = request.history.copy()
    new_history.append({
        "role": "user",
        "parts": [{"text": request.message}]
    })
    new_history.append({
        "role": "model",
        "parts": [{"text": reply_text}]
    })
    
    return {
        "reply": reply_data,
        "history": new_history
    }

@app.get("/finance/latest")
def finance_latest():
    """Return the most recent financial analysis."""
    analysis = get_latest_analysis()
    if analysis:
        return {"status": "ok", "analysis": analysis}
    return {"status": "no_data", "analysis": None}

@app.get("/finance/history")
def finance_history(n: int = 10):
    """Return the last N financial analyses."""
    history = get_analysis_history(n)
    return {"status": "ok", "count": len(history), "analyses": history}
