import requests
import json

url = "https://sion-app.onrender.com/chat"
payload = {
    "message": "hello",
    "history": []
}
headers = {
    "Content-Type": "application/json"
}

try:
    response = requests.post(url, json=payload, headers=headers)
    print(f"Status Code: {response.status_code}")
    print(f"Response Body: {response.text}")
except Exception as e:
    print(f"Error: {e}")
