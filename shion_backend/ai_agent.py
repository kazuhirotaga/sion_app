import os
import json
import asyncio
from google import genai
from google.genai import types
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from dotenv import load_dotenv

load_dotenv()

# Initialize Gemini Client
# Assumes GEMINI_API_KEY is set in environment variables
genai_client = genai.Client()

SYSTEM_INSTRUCTION = """
あなたは「シオン」という名前のAIロボットです。
短く、親しみやすい日本語で返答してください。音声で読み上げるため、1〜2文程度の簡潔な文章でお願いします。
また、利用可能なツール（検索やMCP機能）を積極的に使ってユーザーの質問に答えてください。

【重要】
ユーザーへの返答時は、以下のJSONフォーマットのみを絶対に出力してください（バッククォートなどのマークダウンは不要です）：
{
  "text": "ユーザーに話しかける言葉",
  "emotion": "joy, anger, surprise, thought, default 等の感情ステータス",
  "action": "nod, tilt, shake, none などのアクション動作"
}
"""

async def process_chat(message: str, history: list) -> str:
    """
    Process a chat message using Gemini, integrating with local MCP server.
    """
    
    # 1. Convert history format
    contents = []
    for turn in history:
        role = turn.get("role", "user")
        parts = turn.get("parts", [])
        text = ""
        if parts and len(parts) > 0:
            text = parts.get("text", "") if isinstance(parts, dict) else parts[0].get("text", "")
            
        contents.append(types.Content(role=role, parts=[types.Part.from_text(text=text)]))
        
    contents.append(types.Content(role="user", parts=[types.Part.from_text(text=message)]))

    # 2. Connect to MCP Server 
    server_params = StdioServerParameters(
        command="python",
        args=["mcp_skills.py"],
        env=os.environ.copy()
    )

    try:
        async with stdio_client(server_params) as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                
                # Fetch tools from MCP and map to Gemini format
                mcp_tools_res = await session.list_tools()
                
                # Helper dictionary type converter
                def convert_schema(schema: dict) -> dict:
                    new_schema = {}
                    for k, v in schema.items():
                        if k == "type" and isinstance(v, str):
                            new_schema[k] = v.upper()
                        elif isinstance(v, dict):
                            new_schema[k] = convert_schema(v)
                        elif isinstance(v, list) and k == "properties":
                            # strictly properties is a dict, but if someone puts list
                            new_schema[k] = v
                        else:
                            new_schema[k] = v
                    return new_schema
                
                # Map MCP tools to Gemini function declarations
                function_declarations = []
                for t in mcp_tools_res.tools:
                    gemini_schema = convert_schema(t.inputSchema)
                    function_declarations.append(
                        types.FunctionDeclaration(
                            name=t.name,
                            description=t.description or "",
                            parameters=gemini_schema
                        )
                    )
                
                # A single Tool object can hold both google_search and function_declarations
                if function_declarations:
                    gemini_tools = [types.Tool(
                        google_search={}, 
                        function_declarations=function_declarations
                    )]
                else:
                    gemini_tools = [types.Tool(google_search={})]
                
                config = types.GenerateContentConfig(
                    system_instruction=SYSTEM_INSTRUCTION,
                    tools=gemini_tools,
                    temperature=0.7
                )

                # 3. First Call to Gemini
                response = genai_client.models.generate_content(
                    model='gemini-2.5-flash',
                    contents=contents,
                    config=config,
                )
                
                # 4. Handle tool calls (Function Calling loop)
                while response.function_calls:
                    # Append Gemini's tool call request to history
                    if response.candidates and response.candidates[0].content:
                         contents.append(response.candidates[0].content)
                    
                    tool_responses_parts = []
                    for fc in response.function_calls:
                        print(f"Executing MCP Tool: {fc.name} with args {fc.args}")
                        try:
                            # Execute the tool via MCP
                            result = await session.call_tool(fc.name, arguments=fc.args or {})
                            res_text = result.content[0].text if result.content else "Success"
                            tool_responses_parts.append(
                                types.Part.from_function_response(name=fc.name, response={"result": res_text})
                            )
                        except Exception as e:
                            tool_responses_parts.append(
                                types.Part.from_function_response(name=fc.name, response={"error": str(e)})
                            )
                            
                    # Append tool results to history
                    contents.append(types.Content(role="tool", parts=tool_responses_parts))
                    
                    # 5. Call Gemini again with the tool output
                    print("Sending tool results back to Gemini...")
                    response = genai_client.models.generate_content(
                        model='gemini-2.5-flash',
                        contents=contents,
                        config=config,
                    )
                
                # Final response extraction
                if response.text:
                    try:
                        # Clean up text in case Gemini adds markdown code blocks
                        raw_text = response.text.strip()
                        if raw_text.startswith("```json"):
                            raw_text = raw_text[7:]
                        elif raw_text.startswith("```"):
                            raw_text = raw_text[3:]
                        if raw_text.endswith("```"):
                            raw_text = raw_text[:-3]
                            
                        return json.loads(raw_text.strip())
                    except json.JSONDecodeError:
                        return {"text": response.text, "emotion": "default", "action": "none"}
                else:
                    return {"text": "返答がありませんでした。", "emotion": "default", "action": "none"}

    except Exception as e:
        import traceback
        err_str = traceback.format_exc()
        print(f"Agent Error: {e}\n{err_str}")
        return {"text": "通信エラーが発生しました。", "emotion": "default", "action": "none"}

# Basic test script if run directly
if __name__ == "__main__":
    async def run_test():
        reply = await process_chat("こんにちは", [])
        print("Reply:", reply)
        
        reply2 = await process_chat("最新のAIニュースを教えて", [])
        print("Reply 2:", json.dumps(reply2, ensure_ascii=False, indent=2))
        
    asyncio.run(run_test())
