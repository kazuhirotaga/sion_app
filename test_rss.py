import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET

query = "今日のニュース"
url = f"https://news.google.com/rss/search?q={urllib.parse.quote(query)}&hl=ja&gl=JP&ceid=JP:ja"

try:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response:
        xml_data = response.read()
    root = ET.fromstring(xml_data)
    
    results = []
    for item in root.findall('.//item')[:3]:
        title = item.find('title').text if item.find('title') is not None else ""
        pubDate = item.find('pubDate').text if item.find('pubDate') is not None else ""
        results.append(f"・{title} ({pubDate})")
        
    print("\n".join(results))
except Exception as e:
    print(f"Error: {e}")
