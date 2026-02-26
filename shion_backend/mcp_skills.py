import asyncio
from mcp.server import Server
import mcp.types as types

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
            description="指定した地域の天気を取得します。",
            inputSchema={
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "天気を知りたい地域（例：東京、大阪）"
                    }
                },
                "required": ["location"]
            }
        )
    ]

@app.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
    """Execute a tool called by the LLM."""
    if name == "get_current_time":
        from datetime import datetime
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        return [types.TextContent(type="text", text=f"現在の日付と時刻は {current_time} です。")]
        
    elif name == "get_weather":
        location = arguments.get("location", "不明")
        # Dummy weather data for demonstration
        return [types.TextContent(type="text", text=f"{location}の今日の天気は晴れ、気温は25度です。")]
    
    else:
        raise ValueError(f"Unknown tool: {name}")

async def main():
    import mcp.server.stdio
    # Run the server on standard I/O (this is how the client communicates with it)
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await app.run(read_stream, write_stream, app.create_initialization_options())

if __name__ == "__main__":
    asyncio.run(main())
