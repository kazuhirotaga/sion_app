from duckduckgo_search import DDGS

try:
    results = []
    with DDGS() as ddgs:
        for r in ddgs.text("Apple 最新ニュース", region='jp-jp', safesearch='moderate', max_results=3):
            print(f"・{r['title']}: {r['body']}")
except Exception as e:
    print(f"Search Error: {str(e)}")
