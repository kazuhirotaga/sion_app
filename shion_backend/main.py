import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Shion API Gateway")

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

@app.get("/")
def read_root():
    return {"status": "ok", "message": "Shion AI Gateway is running."}

from ai_agent import process_chat

@app.post("/chat")
async def chat_endpoint(request: ChatRequest):
    # Call Gemini via AI Agent
    reply_data = await process_chat(request.message, request.history)
    
    # extract the spoken text for the history array
    reply_text = reply_data.get("text", "") if isinstance(reply_data, dict) else str(reply_data)
    
    # Append the model's reply to the history array to send back
    new_history = request.history.copy()
    
    # Add user message
    new_history.append({
        "role": "user",
        "parts": [{"text": request.message}]
    })
    
    # Add model reply
    new_history.append({
        "role": "model",
        "parts": [{"text": reply_text}]
    })
    
    return {
        "reply": reply_data,
        "history": new_history
    }
