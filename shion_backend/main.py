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
    
    # Schedule every 3 minutes
    scheduler.add_job(
        run_analysis_cycle,
        trigger=IntervalTrigger(minutes=3),
        id="financial_analysis",
        replace_existing=True,
        misfire_grace_time=300,
        coalesce=True,
    )
    scheduler.start()
    print("FinancialAnalyst: Scheduler started (every 3 minutes)")
    
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

class TtsRequest(BaseModel):
    text: str
    voice: str = "Aoede"

@app.post("/tts")
async def tts_endpoint(request: TtsRequest):
    """Generate speech audio using Gemini TTS and return WAV as base64."""
    import base64
    import wave
    import io
    from google import genai
    from google.genai import types

    try:
        import os
        client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY"))
        response = client.models.generate_content(
            model="gemini-2.5-flash-preview-tts",
            contents=request.text,
            config=types.GenerateContentConfig(
                response_modalities=["AUDIO"],
                speech_config=types.SpeechConfig(
                    voice_config=types.VoiceConfig(
                        prebuilt_voice_config=types.PrebuiltVoiceConfig(
                            voice_name=request.voice,
                        )
                    )
                ),
            ),
        )

        pcm_data = response.candidates[0].content.parts[0].inline_data.data

        # Convert PCM to WAV in memory
        wav_buffer = io.BytesIO()
        with wave.open(wav_buffer, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(24000)
            wf.writeframes(pcm_data)

        wav_bytes = wav_buffer.getvalue()
        audio_base64 = base64.b64encode(wav_bytes).decode("utf-8")

        return {"status": "ok", "audio_base64": audio_base64}
    except Exception as e:
        print(f"TTS Error: {e}")
        return {"status": "error", "error": str(e)}
