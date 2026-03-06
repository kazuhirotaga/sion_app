import os
from dotenv import load_dotenv
load_dotenv()
from google import genai

try:
    print(f"Loaded KEY: {os.environ.get('GEMINI_API_KEY')}")
    client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY"))
    print("Client initialized successfully!")
except Exception as e:
    print(f"Init Error: {type(e).__name__}: {e}")
