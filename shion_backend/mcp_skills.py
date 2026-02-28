import asyncio
import httpx
from mcp.server import Server
import mcp.types as types
from duckduckgo_search import DDGS
from datetime import datetime

# Initialize the MCP Server
app = Server("shion-skills-server")

@app.list_tools()
async def list_tools() -> list[types.Tool]:
    """List available tools exposed by this MCP server."""
    return [
        types.Tool(
            name="get_current_time",
            description="現在の日付と時刻を取得します。",
            inputSchema={
                "type": "object",
                "properties": {},
            }
        ),
        types.Tool(
            name="get_weather",
            description="指定した場所の現在の天気と気温を取得します。",
            inputSchema={
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "天気を知りたい地域（例：東京、大阪、New York）"
                    }
                },
                "required": ["location"]
            }
        ),
        types.Tool(
            name="get_news_or_search",
            description="最新のニュースや、指定したキーワードに関するWeb上の最新情報を検索します。",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "検索キーワード（例：今日のITニュース、Appleの新製品、日経平均株価）"
                    }
                },
                "required": ["query"]
            }
        ),
        types.Tool(
            name="get_map_location",
            description="指定した地名や施設の住所、場所の概要を取得します。",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "検索したい場所の名前（例：東京タワー、渋谷駅、スカイツリー）"
                    }
                },
                "required": ["query"]
            }
        )
    ]

@app.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
    """Execute a tool called by the LLM."""
    
    if name == "get_current_time":
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        return [types.TextContent(type="text", text=f"現在の日付と時刻は {current_time} です。")]
        
    elif name == "get_weather":
        location = arguments.get("location", "Tokyo")
        try:
            async with httpx.AsyncClient() as client:
                # 1. Geocoding (Location to Lat/Lon via Nominatim)
                geo_url = f"https://nominatim.openstreetmap.org/search?q={location}&format=json&limit=1"
                headers = {'User-Agent': 'ShionCore/1.0'}
                geo_res = await client.get(geo_url, headers=headers)
                if geo_res.status_code != 200 or not geo_res.json():
                    return [types.TextContent(type="text", text=f"{location}の正確な場所を取得できませんでした。")]
                
                geo_data = geo_res.json()[0]
                lat = geo_data['lat']
                lon = geo_data['lon']
                display_name = geo_data['display_name']
                
                # 2. Get Weather via Open-Meteo
                weather_url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current_weather=true"
                weather_res = await client.get(weather_url)
                if weather_res.status_code != 200:
                    return [types.TextContent(type="text", text="天気情報の取得に失敗しました。")]
                
                w_data = weather_res.json()['current_weather']
                temp = w_data['temperature']
                code = w_data['weathercode']
                
                # Basic WMO Weather interpretation
                weather_desc = "不明"
                if code == 0: weather_desc = "快晴"
                elif code in [1, 2, 3]: weather_desc = "晴れ/曇り"
                elif code in [45, 48]: weather_desc = "霧"
                elif code in [51, 53, 55, 56, 57]: weather_desc = "霧雨"
                elif code in [61, 63, 65, 66, 67]: weather_desc = "雨"
                elif code in [71, 73, 75, 77]: weather_desc = "雪"
                elif code in [80, 81, 82]: weather_desc = "にわか雨"
                elif code in [95, 96, 99]: weather_desc = "雷雨"

                result = f"場所: {display_name}\n現在の天気: {weather_desc}\n気温: {temp}℃"
                return [types.TextContent(type="text", text=result)]
        except Exception as e:
            return [types.TextContent(type="text", text=f"天気取得エラー: {str(e)}")]

    elif name == "get_news_or_search":
        query = arguments.get("query", "最新ニュース")
        try:
            import wikipedia
            from googlesearch import search
            import urllib.request
            import urllib.parse
            import xml.etree.ElementTree as ET
            
            wikipedia.set_lang("ja")
            results = []
            
            # 1. Try Google News RSS (Extremely reliable for real-time news & general topics)
            try:
                rss_url = f"https://news.google.com/rss/search?q={urllib.parse.quote(query)}&hl=ja&gl=JP&ceid=JP:ja"
                req = urllib.request.Request(rss_url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(req, timeout=5) as response:
                    xml_data = response.read()
                root = ET.fromstring(xml_data)
                
                for item in root.findall('.//item')[:3]:
                    title = item.find('title').text if item.find('title') is not None else ""
                    pubDate = item.find('pubDate').text if item.find('pubDate') is not None else ""
                    results.append(f"・ニュース: {title} ({pubDate})")
            except Exception as e:
                pass
                
            # 2. Try Wikipedia if no news or as supplement
            if not results:
                try:
                    wiki_pages = wikipedia.search(query, results=1)
                    if wiki_pages:
                        summary = wikipedia.summary(wiki_pages[0], sentences=2)
                        results.append(f"・Wikipedia要約: {summary}")
                except Exception as e:
                    pass
            
            # 3. Add Google Search Links (Gemini can just report these)
            try:
                for idx, url in enumerate(search(query, num=2, stop=2, lang='ja')):
                    results.append(f"・参考リンク {idx+1}: {url}")
            except Exception as e:
                pass
            
            if not results:
                return [types.TextContent(type="text", text="関連する情報が見つかりませんでした。")]
                
            result_text = "\n".join(results)
            return [types.TextContent(type="text", text=f"「{query}」の関連情報:\n{result_text}")]
        except Exception as e:
            return [types.TextContent(type="text", text=f"検索機能エラー: {str(e)}")]

    elif name == "get_map_location":
        query = arguments.get("query", "")
        if not query:
            return [types.TextContent(type="text", text="検索キーワードが指定されていません。")]
        
        try:
            async with httpx.AsyncClient() as client:
                geo_url = f"https://nominatim.openstreetmap.org/search?q={query}&format=json&limit=1&addressdetails=1"
                headers = {'User-Agent': 'ShionCore/1.0'}
                geo_res = await client.get(geo_url, headers=headers)
                data = geo_res.json()
                
                if not data:
                    return [types.TextContent(type="text", text=f"「{query}」の場所が見つかりませんでした。")]
                
                info = data[0]
                result_text = f"名称/住所: {info.get('display_name', '不明')}\n緯度: {info.get('lat')}\n経度: {info.get('lon')}\n種別: {info.get('type', '不明')}"
                return [types.TextContent(type="text", text=result_text)]
        except Exception as e:
            return [types.TextContent(type="text", text=f"場所検索エラー: {str(e)}")]

    else:
        raise ValueError(f"Unknown tool: {name}")

async def main():
    import mcp.server.stdio
    # Run the server on standard I/O (this is how the client communicates with it)
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await app.run(read_stream, write_stream, app.create_initialization_options())

if __name__ == "__main__":
    asyncio.run(main())
